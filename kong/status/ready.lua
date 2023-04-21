local declarative = require "kong.db.declarative"
local constants = require "kong.constants"

local tonumber = tonumber
local kong = kong
local fmt = string.format

local get_current_hash = declarative.get_current_hash


local worker_count = ngx.worker.count()
local kong_shm     = ngx.shared.kong

local is_dbless = kong.configuration.database == "off"
local is_control_plane = kong.configuration.role == "control_plane"

local DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY = 
                                constants.DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY
local DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY =
                                constants.DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local function is_dbless_ready(router_rebuilds, plugins_iterator_rebuilds)
  if router_rebuilds < worker_count then
    return false, fmt("router builds not yet complete, router ready"
      .. " on %d of %d workers", router_rebuilds, worker_count)
  end

  if plugins_iterator_rebuilds < worker_count then
    return false, fmt("plugins iterator builds not yet complete, "
      .. "plugins iterator ready on %d of %d workers",
      plugins_iterator_rebuilds, worker_count)
  end

  local current_hash = get_current_hash()

  if not current_hash then
    return false, "no configuration available (configuration hash is not initialized)"
  end

  if current_hash == DECLARATIVE_EMPTY_CONFIG_HASH then
    return false, "no configuration available (configuration hash is empty)"
  end

  return true
end


local function is_traditional_ready(router_rebuilds, plugins_iterator_rebuilds)
    -- data plane with db, only build once, because
    -- build_router() will not be called for each worker because of ROUTER_CACHE
    if router_rebuilds == 0 then
      return false, "router builds not yet complete"
    end

    if plugins_iterator_rebuilds == 0 then
      return false, "plugins iterator build not yet complete"
    end

    return true
end

--[[
Checks if Kong is ready to serve.

@return boolean indicating if Kong is ready to serve.
@return string|nil an error message if Kong is not ready, or nil otherwise.
--]]
local function is_ready()
  -- control plane has no need to serve traffic
  if is_control_plane then
    return true
  end

  local ok = kong.db:connect() -- for dbless, always ok

  if not ok then
    kong.db:close()
    return false, "failed to connect to database"
  end
  
  kong.db:close()

  local router_rebuilds = 
      tonumber(kong_shm:get(DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY)) or 0
  local plugins_iterator_rebuilds = 
      tonumber(kong_shm:get(DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY)) or 0

  local err
  -- full check for dbless mode
  if is_dbless then
    ok, err = is_dbless_ready(router_rebuilds, plugins_iterator_rebuilds)

  else
    ok, err = is_traditional_ready(router_rebuilds, plugins_iterator_rebuilds)
  end

  return ok, err
end

return {
  ["/status/ready"] = {
    GET = function(self, dao, helpers)
      local ok, err = is_ready()
      if ok then
        return kong.response.exit(200, { message = "ready" })

      else
        return kong.response.exit(503, { message = err })
      end
    end
  }
}
