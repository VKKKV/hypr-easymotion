local M = {}

local escape_map = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function encode_string(s)
  return '"' .. tostring(s):gsub('["\\%z\1-\31]', function(c)
    return escape_map[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end

local function is_array(t)
  local max = 0
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    if k > max then max = k end
    count = count + 1
  end
  return max == count
end

function M.encode(value)
  local ty = type(value)
  if value == nil then
    return "null"
  elseif ty == "string" then
    return encode_string(value)
  elseif ty == "number" then
    return tostring(value)
  elseif ty == "boolean" then
    return value and "true" or "false"
  elseif ty == "table" then
    local parts = {}
    if is_array(value) then
      for i = 1, #value do
        parts[#parts + 1] = M.encode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, v in pairs(value) do
      parts[#parts + 1] = encode_string(k) .. ":" .. M.encode(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("unsupported JSON type: " .. ty)
end

local Parser = {}
Parser.__index = Parser

function Parser:peek()
  return self.s:sub(self.i, self.i)
end

function Parser:skip_ws()
  local _, e = self.s:find("^[ \n\r\t]*", self.i)
  self.i = (e or self.i - 1) + 1
end

function Parser:expect(ch)
  if self:peek() ~= ch then
    error("expected '" .. ch .. "' at byte " .. self.i)
  end
  self.i = self.i + 1
end

function Parser:string()
  self:expect('"')
  local out = {}
  while self.i <= #self.s do
    local ch = self:peek()
    self.i = self.i + 1
    if ch == '"' then
      return table.concat(out)
    elseif ch == "\\" then
      local esc = self:peek()
      self.i = self.i + 1
      if esc == '"' or esc == "\\" or esc == "/" then out[#out + 1] = esc
      elseif esc == "b" then out[#out + 1] = "\b"
      elseif esc == "f" then out[#out + 1] = "\f"
      elseif esc == "n" then out[#out + 1] = "\n"
      elseif esc == "r" then out[#out + 1] = "\r"
      elseif esc == "t" then out[#out + 1] = "\t"
      elseif esc == "u" then
        local hex = self.s:sub(self.i, self.i + 3)
        self.i = self.i + 4
        local n = tonumber(hex, 16) or 63
        if n < 128 then out[#out + 1] = string.char(n) else out[#out + 1] = "?" end
      else
        error("invalid escape at byte " .. self.i)
      end
    else
      out[#out + 1] = ch
    end
  end
  error("unterminated string")
end

function Parser:number()
  local b, e = self.s:find("^-?%d+%.?%d*[eE]?[+-]?%d*", self.i)
  if not b then error("invalid number at byte " .. self.i) end
  local n = tonumber(self.s:sub(b, e))
  self.i = e + 1
  return n
end

function Parser:array()
  self:expect("[")
  local out = {}
  self:skip_ws()
  if self:peek() == "]" then self.i = self.i + 1; return out end
  while true do
    out[#out + 1] = self:value()
    self:skip_ws()
    local ch = self:peek()
    if ch == "]" then self.i = self.i + 1; return out end
    self:expect(",")
  end
end

function Parser:object()
  self:expect("{")
  local out = {}
  self:skip_ws()
  if self:peek() == "}" then self.i = self.i + 1; return out end
  while true do
    self:skip_ws()
    local key = self:string()
    self:skip_ws()
    self:expect(":")
    out[key] = self:value()
    self:skip_ws()
    local ch = self:peek()
    if ch == "}" then self.i = self.i + 1; return out end
    self:expect(",")
  end
end

function Parser:value()
  self:skip_ws()
  local ch = self:peek()
  if ch == '"' then return self:string()
  elseif ch == "{" then return self:object()
  elseif ch == "[" then return self:array()
  elseif ch == "t" and self.s:sub(self.i, self.i + 3) == "true" then self.i = self.i + 4; return true
  elseif ch == "f" and self.s:sub(self.i, self.i + 4) == "false" then self.i = self.i + 5; return false
  elseif ch == "n" and self.s:sub(self.i, self.i + 3) == "null" then self.i = self.i + 4; return nil
  else return self:number() end
end

function M.decode(s)
  local p = setmetatable({ s = s, i = 1 }, Parser)
  local ok, result = pcall(function() return p:value() end)
  if ok then return result end
  return nil, result
end

return M
