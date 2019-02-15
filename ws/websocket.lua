local socket = require "skynet.socket"
local frame = require "ws.frame"
local handshake = require "ws.handshake"

local readbytes = socket.read
local writebytes = socket.write

local websocket = {}

function websocket.start_handshake(fd)
    socket.start(fd)
    
    -- set socket buffer limit (8K)
    -- If the attacker send large package, close the socket
    socket.limit(fd, 8192)

    local header = ""
    while true do
        local bytes = readbytes(fd)
        if not bytes then
            socket.close(fd)
            error("ws handshake socket error.")
        end

        header = header .. bytes

        local _, to = header:find("\r\n\r\n", -#bytes-3, true)
        if to then
            header = header:sub(1, to)
            break
        end
    end
    
    local response, protocol = handshake.accept_upgrade(header)
    if not response then
        socket.close(fd)
        error('ws handshake failed, response:', response)
    end

    socket.write(fd, response)
end

function websocket.write(fd, message, opcode)
    local encoded = frame.encode(message, opcode)
    writebytes(fd, encoded)
end

function websocket.read(fd)
    local last
    local frames = {}
    local first_opcode

    while true do
        local encoded = readbytes(fd)
        if not encoded then
            break
        end

        if last then
            encoded = last .. encoded
            last = nil
        end

        repeat
            local decoded, fin, opcode, rest = frame.decode(encoded)
            if decoded then
                if not first_opcode then
                    first_opcode = opcode
                end
                table.insert(frames, decoded)
                encoded = rest
                if fin then
                    return table.concat(frames), first_opcode
                end
            end
        until (not decoded)
        
        if #encoded > 0 then
            last = encoded
        end
    end

    return false
end

function websocket.close(fd, code, reason)
    local encoded = frame.encode_close(code or 1000, reason or '')
    encoded = frame.encode(encoded, frame.CLOSE)
    writebytes(fd, encoded)
end

return websocket