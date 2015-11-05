local cjson = require "cjson"
local utils = require "kong.tools.utils"

local str_gsub = string.gsub
local os_date = os.date
local tostring = tostring
local ngx_log = ngx.log
local ngx_timer_at = ngx.timer.at
local ngx_socket_udp = ngx.socket.udp
local table_concat = table.concat

local _M = {}

local SENDER_NAME = "kong"
local HOSTNAME = utils.getHostname()

local LOG_LEVELS = { 
  debug = 7, 
  info = 6, 
  notice = 5, 
  warning = 4, 
  err = 3, 
  crit = 2, 
  alert = 1, 
  emerg = 0
}

local function merge(conf, message, pri)
  local tags_list = conf.tags
  local tags = {}
  for i = 1, #tags_list do
    table.insert(tags, "tag=".."\""..tags_list[i].."\"")
  end
  
  local udp_message = { 
    "<"..pri..">1", 
    os_date("!%Y-%m-%dT%XZ"), 
    HOSTNAME, 
    SENDER_NAME, 
    "-", 
    "-", 
    "["..conf.key.."@41058", table.concat(tags, " ").."]", 
    cjson.encode(message) 
  }
  return table_concat(udp_message, " ")
end

local function send_to_loggly(conf, message, pri)
  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout
  local udp_message = merge(conf, message, pri)
  local sock = ngx_socket_udp()
  sock:settimeout(timeout)

  local ok, err = sock:setpeername(host, port)
  if not ok then
    ngx_log(ngx.ERR, "failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end
  local ok, err = sock:send(udp_message)
  if not ok then
    ngx_log(ngx.ERR, "failed to send data to ".. host..":"..tostring(port)..": ", err)
  end

  local ok, err = sock:close()
  if not ok then
    ngx_log(ngx.ERR, "failed to close connection from "..host..":"..tostring(port)..": ", err)
    return
  end
end

local function decide_severity(conf, severity, message)
  if LOG_LEVELS[severity] <= LOG_LEVELS[conf.log_level] then
    local pri = 8 + LOG_LEVELS[severity]
    return send_to_loggly(conf, message, pri)
  end
end

local function log(premature, conf, message)
  if message.response.status >= 500 then
    return decide_severity(conf.log_level, conf.server_errors_severity, message)
  elseif message.response.status >= 400 then
    return decide_severity(conf.log_level, conf.client_errors_severity, message)
  else
    return decide_severity(conf, conf.successful_severity, message)
  end
end

function _M.execute(conf, message)
  local ok, err = ngx_timer_at(0, log, conf, message)
  if not ok then
    ngx_log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
