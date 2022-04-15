local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_cast = ffi.cast
local band = bit.band
local base = require "resty.core.base"
local new_tab = base.new_tab

local cucharpp = ffi_new("const unsigned char*[1]")
local ucharpp = ffi_new("unsigned char*[1]")
local charpp = ffi_new("char*[1]")


ffi.cdef [[
  typedef struct asn1_string_st ASN1_OCTET_STRING;
  typedef struct asn1_string_st ASN1_INTEGER;
  typedef struct asn1_string_st ASN1_ENUMERATED;
  typedef struct asn1_string_st ASN1_STRING;

  ASN1_OCTET_STRING *ASN1_OCTET_STRING_new();
  ASN1_INTEGER *ASN1_INTEGER_new();
  ASN1_ENUMERATED *ASN1_ENUMERATED_new();

  void ASN1_INTEGER_free(ASN1_INTEGER *a);
  void ASN1_STRING_free(ASN1_STRING *a);

  long ASN1_INTEGER_get(const ASN1_INTEGER *a);
  long ASN1_ENUMERATED_get(const ASN1_ENUMERATED *a);

  int ASN1_INTEGER_set(ASN1_INTEGER *a, long v);
  int ASN1_ENUMERATED_set(ASN1_ENUMERATED *a, long v);
  int ASN1_STRING_set(ASN1_STRING *str, const void *data, int len);

  const unsigned char *ASN1_STRING_get0_data(const ASN1_STRING *x);
  // openssl 1.1.0
  unsigned char *ASN1_STRING_data(ASN1_STRING *x);

  ASN1_OCTET_STRING *d2i_ASN1_OCTET_STRING(ASN1_OCTET_STRING **a, const unsigned char **ppin, long length);
  ASN1_INTEGER *d2i_ASN1_INTEGER(ASN1_INTEGER **a, const unsigned char **ppin, long length);
  ASN1_ENUMERATED *d2i_ASN1_ENUMERATED(ASN1_ENUMERATED **a, const unsigned char **ppin, long length);

  int i2d_ASN1_OCTET_STRING(const ASN1_OCTET_STRING *a, unsigned char **pp);
  int i2d_ASN1_INTEGER(const ASN1_INTEGER *a, unsigned char **pp);
  int i2d_ASN1_ENUMERATED(const ASN1_ENUMERATED *a, unsigned char **pp);

  int ASN1_get_object(const unsigned char **pp, long *plength, int *ptag,
                      int *pclass, long omax);
  int ASN1_object_size(int constructed, int length, int tag);

  void ASN1_put_object(unsigned char **pp, int constructed, int length,
                      int tag, int xclass);
]]


local ASN1_STRING_get0_data
if not pcall(function() return C.ASN1_STRING_get0_data end) then
  ASN1_STRING_get0_data = C.ASN1_STRING_data
else
  ASN1_STRING_get0_data = C.ASN1_STRING_get0_data
end


local _M = new_tab(0, 7)


local CLASS = {
  UNIVERSAL = 0x00,
  APPLICATION = 0x40,
  CONTEXT_SPECIFIC = 0x80,
  PRIVATE = 0xc0
}
_M.CLASS = CLASS


local TAG = {
  -- ASN.1 tag values
  EOC = 0,
  BOOLEAN = 1,
  INTEGER = 2,
  OCTET_STRING = 4,
  NULL = 5,
  ENUMERATED = 10,
  SEQUENCE = 16,
}
_M.TAG = TAG


local asn1_get_object
do
  local lenp = ffi_new("long[1]")
  local tagp = ffi_new("int[1]")
  local classp = ffi_new("int[1]")
  local strpp = ffi_new("const unsigned char*[1]")

  function asn1_get_object(der, start, stop)
    start = start or 0
    stop = stop or #der
    if stop < start or stop > #der then
      return nil, "invalid offset"
    end

    local s_der = ffi_cast("const unsigned char *", der)
    strpp[0] = s_der + start

    local ret = C.ASN1_get_object(strpp, lenp, tagp, classp, stop - start + 1)
    if band(ret, 0x80) == 0x80 then
      return nil, "der with error encoding: " .. ret
    end

    local cons = false
    if band(ret, 0x20) == 0x20 then
      cons = true
    end

    local obj = {
      tag = tagp[0],
      class = classp[0],
      len = tonumber(lenp[0]),
      offset = strpp[0] - s_der,
      hl = strpp[0] - s_der - start,
      cons = cons,
    }

    return obj
  end
end
_M.get_object = asn1_get_object


local function asn1_put_object(tag, class, constructed, data, len)
  len = type(data) == "string" and #data or len or 0
  local outbuf = ffi.new("unsigned char[?]", len)
  ucharpp[0] = outbuf

  C.ASN1_put_object(ucharpp, constructed, len, tag, class)
  if not data then
    return ffi_string(outbuf)
  end
  return ffi_string(outbuf) .. data
end
_M.put_object = asn1_put_object


local encode
do
  local encoder = new_tab(0, 2)

  -- Integer
  encoder[TAG.INTEGER] = function(val)
    local typ = C.ASN1_INTEGER_new()
    C.ASN1_INTEGER_set(typ, val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_INTEGER(typ, charpp)
    C.ASN1_INTEGER_free(typ)
    return ffi_string(charpp[0], ret)
  end

  -- Octet String
  encoder[TAG.OCTET_STRING] = function(val)
    local typ = C.ASN1_OCTET_STRING_new()
    C.ASN1_STRING_set(typ, val, #val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_OCTET_STRING(typ, charpp)
    C.ASN1_STRING_free(typ)
    return ffi_string(charpp[0], ret)
  end

  encoder[TAG.ENUMERATED] = function(val)
    local typ = C.ASN1_ENUMERATED_new()
    C.ASN1_ENUMERATED_set(typ, val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_ENUMERATED(typ, charpp)
    C.ASN1_INTEGER_free(typ)
    return ffi_string(charpp[0], ret)
  end

  encoder[TAG.SEQUENCE] = function(val)
    return asn1_put_object(TAG.SEQUENCE, CLASS.UNIVERSAL, 1, val)
  end

  function encode(val, tag)
    if tag == nil then
      local typ = type(val)
      if typ == "string" then
        tag = TAG.OCTET_STRING
      elseif typ == "number" then
        tag = TAG.INTEGER
      end
    end

    if encoder[tag] then
      return encoder[tag](val)
    end
  end
end
_M.encode = encode


local decode
do
  local decoder = new_tab(0, 2)

  decoder[TAG.OCTET_STRING] = function(der, offset, len)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, len)
    local ret = ASN1_STRING_get0_data(typ)
    C.ASN1_STRING_free(typ)
    return ffi_string(ret)
  end

  decoder[TAG.INTEGER] = function(der, offset, len)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_INTEGER(nil, cucharpp, len)
    local ret = C.ASN1_INTEGER_get(typ)
    C.ASN1_INTEGER_free(typ)
    return tonumber(ret)
  end

  decoder[TAG.ENUMERATED] = function(der, offset, len)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_INTEGER(nil, cucharpp, len)
    local ret = C.ASN1_INTEGER_get(typ)
    C.ASN1_INTEGER_free(typ)
    return tonumber(ret)
  end

  -- offset starts from 0
  function decode(der, offset)
    local obj, err = asn1_get_object(der, offset)
    if not obj then
      return nil, nil, err
    end

    local ret
    if decoder[obj.tag] then
      ret = decoder[obj.tag](der, offset, obj.len)
    end
    return obj.offset + obj.len, ret
  end
end
_M.decode = decode


--[[
Encoded LDAP Result: https://ldap.com/ldapv3-wire-protocol-reference-ldap-result/

30 0c -- Begin the LDAPMessage sequence
   02 01 03 -- The message ID (integer value 3)
   69 07 -- Begin the add response protocol op
      0a 01 00 -- success result code (enumerated value 0)
      04 00 -- No matched DN (0-byte octet string)
      04 00 -- No diagnostic message (0-byte octet string)
--]]

local function parse_ldap_result(der)
  local p = ffi_cast("const unsigned char *", der)
  cucharpp[0] = p
  local obj, err = asn1_get_object(der)
  if not obj then
    return nil, err
  end

  -- message ID (integer)
  local asn1_int = C.d2i_ASN1_INTEGER(nil, cucharpp, #der)
  local id = C.ASN1_INTEGER_get(asn1_int)
  C.ASN1_INTEGER_free(asn1_int)

  -- response protocol op
  obj = asn1_get_object(der, obj.offset + obj.len)
  if not obj then
    return nil, err
  end
  local op = obj.tag

  -- success result code
  cucharpp[0] = p + obj.offset
  local asn1_enum = C.d2i_ASN1_ENUMERATED(nil, cucharpp, obj.len)
  local code = C.ASN1_ENUMERATED_get(asn1_enum)
  C.ASN1_INTEGER_free(asn1_enum)

  -- matched DN (octet string)
  local asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local matched_dn = ASN1_STRING_get0_data(asn1_str)
  C.ASN1_STRING_free(asn1_str)

  -- diagnostic message (octet string)
  local asn1_str1 = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local diagnostic_msg = ASN1_STRING_get0_data(asn1_str1)
  C.ASN1_STRING_free(asn1_str1)

  local res = {
    message_id = tonumber(id),
    protocol_op = op,
    result_code = tonumber(code),
    matched_dn = ffi_string(matched_dn),
    diagnostic_msg = ffi_string(diagnostic_msg),
  }

  return res
end
_M.parse_ldap_result = parse_ldap_result


return _M
