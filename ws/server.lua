local skynet = require "skynet"
local socket = require "skynet.socket"
local frame = require "ws.frame"
local websocket = require "ws.websocket"

local wsserver = {}

local listener
local client_number = 0
local maxclient

local handler = {
    on_connection   = function(fd, addr) end,
    on_disconnect   = function(fd, reason) end,
    on_message      = function(fd, msg, opcode) end,
    on_error        = function(fd, err) end
}

local function dispatch(fd, msg, opcode)
    if opcode == frame.TEXT or opcode == frame.BINARY then
        handler.on_message(fd, msg, opcode)
    elseif opcode == frame.CLOSE then
        local code, reason = frame.decode_close(message)

        local encoded = frame.encode_close(code)
        encoded = frame.encode(encoded, frame.CLOSE)
        socket.write(fd, encoded)

        client_number = client_number - 1
        handler.on_disconnect(fd, reason)
    else
        skynet.error("unknow opcode:", opcode)
    end
end

local function receive_loop(fd)
    while true do
        local msg, opcode = websocket.read(fd)
        if not msg then
            break
        end
        dispatch(fd, msg, opcode)
    end
end

local function accept(fd, addr)
    if client_number >= maxclient then
        socket.close(fd)
        skynet.error("Reach the maximum number of clients.", client_number)
        return
    end

    local ok, err = pcall(websocket.start_handshake, fd)
    if not ok then
        handler.on_error(fd, err)
        return
    end
    
    client_number = client_number + 1
    skynet.fork(receive_loop, fd)
    handler.on_connection(fd, addr)
end

function wsserver.listen(conf)
    local address = conf.address or "0.0.0.0"
    local port = assert(conf.port)
    maxclient = conf.maxclient or 1024
    
    listener = socket.listen(address, port)
    socket.start(listener, function(fd, addr)
        pcall(accept, fd, addr)
    end)
end

function wsserver.close()
    assert(listener)
    socket.close(listener)
end

function wsserver.close_client(fd, code, reason)
    websocket.close(fd, code, reason)
end

function wsserver.on(event, callback)
    local full_name = string.format("on_%s", event)
    assert(handler[full_name], "ws event parameter error")
    handler[full_name] = callback
end

return wsserver