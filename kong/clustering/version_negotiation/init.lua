
local cjson = require "cjson.safe"
local pl_file = require "pl.file"
local http = require "resty.http"

local constants = require "kong.constants"
local clustering_utils = require "kong.clustering.utils"

local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local _log_prefix = "[version-negotiation] "

local KONG_VERSION
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS


local _M = {}


local function get_body()
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  if body then
    return body
  end

  local fname = ngx.req.get_body_file()
  if fname then
    return pl_file.read(fname)
  end

  return ""
end

local function response(status, body)
  ngx.status = status

  if type(body) == "table" then
    ngx.header["Content-Type"] = "application/json"
    body = cjson.encode(body)
  end

  ngx.say(body)
  return ngx.exit(status)
end

local function response_err(msg)
  return response(400, { message = msg })
end

local function verify_request(body)
  if type(body.node) ~= "table" then
    return false, "field \"node\" must be an object."
  end

  if type(body.node.id) ~= "string" then
    return false, "field \"node.id\" must be a string."
  end

  if type(body.node.type) ~= "string" then
    return false, "field \"node.type\" must be a string."
  end

  if type(body.node.version) ~= "string" then
    return false, "field \"node.version\" must be a string."
  end

  if type(body.services_requested) ~= "table" then
    return false, "field \"services_requested\" must be an array."
  end

  return true
end


local function node_info()
  return {
    id = kong.node.get_id()
  }
end

local function cp_priority(name, req_versions, known_versions)
  local versions_set = {}
  for _, version in ipairs(req_versions) do
    versions_set[version] = true
  end

  for _, v in ipairs(known_versions) do
    if versions_set[v.version] then
      return true, {
        name = name,
        version = v.version,
        message = v.message,
      }
    end
  end

  return false, { name = name, message = "No valid version" }
end

local all_known_services = require "kong.clustering.version_negotiation.services_known"

local function check_node_compatibility(client_node)
  if client_node.type ~= "KONG" then
    return nil, ("unknown node type %q"):format(client_node.type), CLUSTERING_SYNC_STATUS.UNKNOWN
  end

  local ok, msg, status = clustering_utils.check_kong_version_compatibility(KONG_VERSION, client_node.version)
  if not ok then
    return ok, msg, status
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end

local function do_negotiation(req_body)
  local services_accepted = {}
  local services_rejected = {}

  for _, req_service in ipairs(req_body.services_requested) do
    if type(req_service) ~= "table" or type(req_service.name) ~= "string" then
      goto continue
    end

    local name = req_service.name

    if type(req_service.versions) ~= "table" then
      table.insert(services_rejected, {
        name = name,
        message = "invalid \"versions\" table.",
      })
      goto continue
    end

    local known_service = all_known_services[name]
    if not known_service then
      table.insert(services_rejected, {
        name = name,
        message = "unknown service.",
      })
      goto continue
    end

    local ok, service_response = cp_priority(name, req_service.versions, known_service)
    if ok then
      table.insert(services_accepted, service_response)
    else
      table.insert(services_rejected, service_response)
    end

    ::continue::
  end

  return {
    node = node_info(),
    services_accepted = services_accepted,
    services_rejected = services_rejected,
  }
end


local function register_client(conf, client_node, services_accepted)
  local services_map = {}
  for _, service in ipairs(services_accepted) do
    services_map[service.name] = service.version
  end

  local ok, err = kong.db.clustering_data_planes:upsert({ id = client_node.id, }, {
    last_seen = ngx.time(),
    config_hash = "00000000000000000000000000000000",
    hostname = client_node.hostname,
    ip = ngx.var.realip_remote_addr or ngx.var.remote_addr,
    version = client_node.version,
    sync_status = client_node.sync_status,
    services_accepted = services_map,
  }, { ttl = conf.cluster_data_plane_purge_delay })

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err)
    return nil, err
  end

  return true
end


function _M.serve_version_handshake(conf)
  if KONG_VERSION == nil then
    KONG_VERSION = kong.version
  end

  local body_in = cjson.decode(get_body())
  if not body_in then
    return response_err("Not valid JSON data")
  end

  local ok, err = verify_request(body_in)
  if not ok then
    return response_err(err)
  end

  ok, err, body_in.node.sync_status = check_node_compatibility(body_in.node)
  if not ok then
    return response_err(err)
  end

  local body_out = do_negotiation(body_in)

  ok, err = register_client(conf, body_in.node, body_out.services_accepted)
  if not ok then
    return response_err(err)
  end

  return response(200, body_out)
end


function _M.request_version_handshake(conf, cert, cert_key)
  local body = cjson.encode{
    node = {
      id = kong.node.get_id(),
      type = "KONG",
      version = kong.version,
      hostname = kong.node.get_hostname(),
    },
    services_requested = require "kong.clustering.version_negotiation.services_requested",
  }

  local params = {
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = body,

    ssl_verify = false,
    client_cert = cert,
    client_priv_key = cert_key,
  }
  if conf.cluster_mtls == "shared" then
    params.ssl_server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      params.ssl_server_name = conf.cluster_server_name
    end
  end

  local c = http.new()
  local res, err = c:request_uri("https://" .. conf.cluster_control_plane .. "/version-handshake", params)

  if not res then
    return nil, err
  end

  if res.status < 200 or res.status >= 300 then
    return nil, res.status .. ": " .. res.reason
  end

  local response_data = cjson.decode(res.body)
  if not response_data then
    return nil, "invalid response"
  end

  for _, service in ipairs(response_data.services_accepted) do
    ngx_log(ngx_DEBUG, _log_prefix, "accepted: \"" .. service.name .. "\", version \"" .. service.version .. "\": ".. service.message)

    _M.set_negotiated_service(service.name, service.version, service.message)
  end

  for _, service in ipairs(response_data.services_rejected) do
    ngx_log(ngx_DEBUG, _log_prefix, "rejectec: \"" .. service.name .. "\": " .. service.message)
    _M.set_negotiated_service(service.name, nil, service.message)
  end

  return response_data, nil
end


local kong_shm = ngx.shared.kong
local SERVICE_KEY_PREFIX = "version_negotiation:service:"

function _M.set_negotiated_service(name, version, message)
  local ok, err = kong_shm:set(SERVICE_KEY_PREFIX .. name, cjson.encode{
    version = version,
    message = message,
  })
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, string.format("couldn't store negotiated service %q (%q): %s",
      name, version, err))
  end
end

function _M.get_negotiated_service(name)
  local val, err = kong_shm:get(SERVICE_KEY_PREFIX .. name)
  if not val then
    return nil, err
  end

  val = cjson.decode(val)
  if not val then
    return nil, "corrupted dictionary"
  end

  return val.version, val.message
end

return _M
