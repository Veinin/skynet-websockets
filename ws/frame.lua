local function xor_mask(encoded, mask, payload)
    local umasked = {}
    for i = 1, payload do
        local j = (i - 1) % 4 + 1 
        umasked[i] = string.char(string.byte(encoded, i) ~ mask[j])
    end
    return table.concat(umasked)
end

local encode = function(data, opcode, masked, fin)
    local header = opcode or 1-- TEXT is default opcode

    if fin == nil or fin == true then
        header = header | 0x80
    end

    local payload = 0
    if masked then
        payload = payload | 0x80
    end
    
    local len = #data
    local chunks = {}
    table.insert(chunks, string.pack("B", header))

    if len < 126 then
        payload = payload | len
        table.insert(chunks, string.pack("B", payload))
    elseif len <= 0xffff then
        payload = payload | 126
        table.insert(chunks, string.pack(">BH", payload, len))
    elseif len < 2^53 then
        payload = payload | 127
        table.insert(chunks, string.pack(">BL", payload, len))
    end

    if not masked then
        table.insert(chunks, data)
    else
        local m1 = math.random(0, 0xff)
        local m2 = math.random(0, 0xff)
        local m3 = math.random(0, 0xff)
        local m4 = math.random(0, 0xff)
        local mask = {m1, m2, m3, m4}
        table.insert(chunks, string.pack(">BBBB", m1, m2, m3, m4))
        table.insert(chunks, xor_mask(data, mask, #data))
    end

    return table.concat(chunks)
end

local decode = function(encoded)
    local encoded_bak = encoded
    if #encoded < 2 then
        return nil, 2-#encoded
    end

    local header, payload, pos = string.unpack("BB", encoded)
    encoded = string.sub(encoded, pos)
    
    local bytes = 2
    local fin = header & 0x80 > 0
    local opcode = header & 0xf
    local mask = payload & 0x80 > 0
    payload = payload & 0x7f

    if payload > 125 then
        if payload == 126 then
            if #encoded < 2 then
                return nil, 2-#encoded
            end
            payload, pos = string.unpack(">H", encoded)
        elseif payload == 127 then
            if #encoded < 8 then
                return nil, 8 - #encoded
            end
            payload, pos = string.unpack(">L", encoded)
            if payload < 0xffff or payload > 2^53 then
                assert(false, 'INVALID PAYLOAD '..payload)
            end
        else
            assert(false, 'INVALID PAYLOAD '..payload)
        end
        encoded = string.sub(encoded, pos)
        bytes = bytes + pos - 1
    end

    local decoded
    if mask then
        local bytes_short = payload + 4 - #encoded
        if bytes_short > 0 then
            return nil, bytes_short
        end
        local m1, m2, m3, m4, pos = string.unpack("BBBB", encoded)
        encoded = string.sub(encoded, pos)
        local mask = {m1, m2, m3, m4}
        decoded = xor_mask(encoded, mask, payload)
        bytes = bytes + 4 + payload
    else
        local bytes_short = payload - #encoded
        if bytes_short > 0 then
          return nil, bytes_short
        end
        if #encoded > payload then
            decoded = string.sub(encoded, 1, payload)
        else
            decoded = encoded
        end
        bytes = bytes + payload
    end
    return decoded, fin, opcode, encoded_bak:sub(bytes + 1), mask
end

local encode_close = function(code, reason)
    if code then
        local data = string.pack(">H", code)
        if reason then
            data = data .. tostring(reason)
        end
        return data
    end
    return ''
end

local decode_close = function(data)
    local _, code, reason
    if data then
        if #data > 1 then
            code = string.unpack(">H", data)
        end
        if #data > 2 then
            reason = data:sub(3)
        end
    end
    return code, reason
end

return {
    encode = encode,
    decode = decode,
    encode_close = encode_close,
    decode_close = decode_close,
    CONTINUATION = 0,
    TEXT = 1,
    BINARY = 2,
    CLOSE = 8,
    PING = 9,
    PONG = 10
}