local _EXTRACTOR        = require "kong.observability.tracing.propagation.extractors._base"
local propagation_utils = require "kong.observability.tracing.propagation.utils"
local from_hex          = propagation_utils.from_hex

local INSTANA_EXTRACTOR = _EXTRACTOR:new({
  headers_validate = {
    any = {
      "x-instana-t",
      "x-instana-s",
      "x-instana-l",
    }
  }
})

function INSTANA_EXTRACTOR:get_context(headers)

  local trace_id = headers["x-instana-t"]
  local span_id = headers["x-instana-s"]
  local level_id = headers["x-instana-l"] 

  if trace_id then
    trace_id = trace_id:match("^(%x+)")
    if not trace_id then
      kong.log.warn("x-instana-t header invalid; ignoring.")
    end
  end
  
  if span_id then
    span_id = span_id:match("^(%x+)")
    if not span_id then
      kong.log.warn("x-instana-s header invalid; ignoring.")
    end
  end
  
  if level_id then
    -- the flag can come in as "0" or "1" 
    -- or something like the following format
    -- "1,correlationType=web;correlationId=1234567890abcdef"
    -- here we only care about the first value
    level_id = level_id:match("^([0-1])$") 
              or level_id:match("^([0-1]),correlationType=(.-);correlationId=(.*)")
  end
  local should_sample = level_id or "1"
  
  
  
  trace_id = from_hex(trace_id) or nil
  span_id = from_hex(span_id) or nil
  
  return {
    trace_id      = trace_id,
    span_id       = span_id,
    should_sample = should_sample,
  }
end

return INSTANA_EXTRACTOR
