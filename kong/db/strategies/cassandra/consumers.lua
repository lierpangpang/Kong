local cassandra = require "cassandra"

local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec)
      return {}
    end
  end
end


local CQL_TYPE =  [[
  SELECT id, username, custom_id, created_at
  FROM consumers WHERE type = ? ALLOW FILTERING
]]

local Consumers = {}

function Consumers:page_by_type(type, size, offset, options)
  local opts = new_tab(0, 2)

  if offset then
    local offset_decoded = decode_base64(offset)
    if not offset_decoded then
        return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    offset = offset_decoded
  end

  local args = { cassandra.int(type) }

  opts.page_size = size
  opts.paging_state = offset

  local rows, err = self.connector:query(CQL_TYPE, args, opts, "read")
  if not rows then
    if err:match("Invalid value for the paging state") then
      return nil, self.errors:invalid_offset(offset, err)
    end
    return nil, self.errors:database_error("could not execute page query: "
                                            .. err)
  end

  local next_offset
  if rows.meta and rows.meta.paging_state then
    next_offset = encode_base64(rows.meta.paging_state)
  end

  rows.meta = nil
  rows.type = nil

  for i = 1, #rows do
    rows[i] = self:deserialize_row(rows[i])
  end

  return rows, nil, next_offset

end


return Consumers
