local socket = require "client.socket"
local crypt = require "client.crypt"
local frame = require "ws.frame"
local handshake = require "ws.handshake"

local CONNECT_TIME_OUT = 1000 * 1000 * 3 -- us
local RECV_WAIT_TIME = 1000 -- us

local ws_client = {}
local ws_client_mt = {__index = ws_client}

local handler = {
    on_open = function() end,
    on_close = function(code, reason) end,
    on_message = function(message) end,
    on_error = function(err) error(err) end,
}

function ws_client.new()
    local obj = setmetatable({}, ws_client_mt)
    obj.fd = -1
    obj.connected = false
    return obj
end

function ws_client:connect(host, port)
    assert(not self.connected)
    self:connect_by_url(string.format("ws://%s:%d", host, port))
end

local function parse_url(url)
    local protocol, address, uri = url:match('^(%w+)://([^/]+)(.*)$')
    if not protocol then 
        error('Invalid URL:'..url) 
    end
    if not uri or uri == '' then 
        uri = '/' 
    end
    protocol = protocol:lower()

    local host, port = address:match("^(.+):(%d+)$")
    if not host then
        host = address
        port = DEFAULT_PORTS[protocol]
    end

    return protocol, host, tonumber(port), uri
end

local function generate_key()
    local r1 = math.random(0, 0xfffffff)
    local r2 = math.random(0, 0xfffffff)
    local r3 = math.random(0, 0xfffffff)
    local r4 = math.random(0, 0xfffffff)
    local key = string.pack(">I16", r1, r2, r3, r4)
    return crypt.base64encode(key)
end

local function read(fd)
    local last
    local frames = {}
    local first_opcode

    while true do
        local encoded = socket.recv(fd)
	    if not encoded then
	    	return false
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

local function dispatch(fd, msg, opcode)
    if opcode == frame.TEXT or opcode == frame.BINARY then
        handler.on_message(msg)
    elseif opcode == frame.CLOSE then
        handler.on_close(code, reason)
    else
        print("unknow opcode:", opcode)
    end
end

function ws_client:dispatch_package()
    local msg, opcode = read(self.fd)
    if not msg then
        return
    end
    dispatch(self.fd, msg, opcode)
end

function ws_client:connect_by_url(url)
    assert(not self.connected)

    local protocol, host, port, uri = parse_url(url)
    if protocol ~= 'ws' then
        handler.on_error('bad protocol')
        return
    end

    self.fd = assert(socket.connect(host, port))

    local key = generate_key()
    local req = handshake.upgrade_request {
        key = key,
        host = host,
        port = port,
        protocols = {''}, -- TODO add protocol support
        origin = "http://example.com",
        uri = uri
    }
    socket.send(self.fd, req)

    self.connected = true

    local timeout = 0
    local response = ''
    repeat
        local bytes = socket.recv(self.fd)
        if bytes then
            response = response .. bytes
        else
            socket.usleep(RECV_WAIT_TIME)
            timeout = timeout + RECV_WAIT_TIME
            if timeout >= CONNECT_TIME_OUT then
                self:close()
                handler.on_error('accept timeout')
                return
            end
        end
    until response:sub(#response-3) == '\r\n\r\n'

    local headers = handshake.http_headers(response)
    local expected_accept = handshake.sec_websocket_accept(key)
    if headers['sec-websocket-accept'] ~= expected_accept then
        self:close()
        handler.on_error('accept failed')
        return
    end
    
    handler.on_open()
end

function ws_client:send(message, opcode)
    local encoded = frame.encode(message, opcode, true)
    socket.send(self.fd, encoded)
end

function ws_client:close(code, reason)
    assert(self.connected)
    self.connected = false
    local encoded = frame.encode_close(code or 1000, reason)
    self:send(encoded, frame.CLOSE)
end

function ws_client.on(event, callback)
    local full_name = string.format("on_%s", event)
    assert(handler[full_name], "ws event parameter error")
    handler[full_name] = callback
end

return ws_client