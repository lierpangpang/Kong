-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _INJECTOR = require "kong.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local pairs = pairs
local ngx_escape_uri = ngx.escape_uri

local OT_INJECTOR = _INJECTOR:new({
  name = "ot",
  context_validate = {
    all = { "trace_id", "span_id" },
  },
  trace_id_allowed_sizes = { 8, 16 },
  span_id_size_bytes = 8,
})


function OT_INJECTOR:create_headers(out_tracing_ctx)
  local headers = {
    ["ot-tracer-traceid"] = to_hex(out_tracing_ctx.trace_id),
    ["ot-tracer-spanid"] = to_hex(out_tracing_ctx.span_id),
  }

  if out_tracing_ctx.should_sample ~= nil then
    headers["ot-tracer-sampled"] = out_tracing_ctx.should_sample and "1" or "0"
  end

  local baggage = out_tracing_ctx.baggage
  if baggage then
    for k, v in pairs(baggage) do
      headers["ot-baggage-" .. k] = ngx_escape_uri(v)
    end
  end

  return headers
end


function OT_INJECTOR:get_formatted_trace_id(trace_id)
  return { ot = to_hex(trace_id) }
end


return OT_INJECTOR