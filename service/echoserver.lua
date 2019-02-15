local skynet = require "skynet"
local ws = require "ws.websocket"
local wsserver = require "ws.server"

local connection = {} -- fd -> { fd , client, agent, addr }

local handler = {}

function handler.connect(fd, addr)
    skynet.error("on connect:", fd, addr)
    connection[fd] = {
        fd = fd,
        addr = addr
    }
end

function handler.message(fd, msg)
    local c = connection[fd]
    if not c then
        skynet.error(string.format("Drop message from fd (%d) : %s", fd, msg))
        return
    end
    ws.write(fd, msg)
end

local function close_fd(fd)
    local c = connection[fd]
    if c then
        connection[fd] = nil
    end
end

function handler.disconnect(fd, code, reason)
    skynet.error("on close:", fd, code, reason)
    close_fd(fd)
end

function handler.error(fd, err)
    skynet.error("on error:", fd, err)
    close_fd(fd)
end

local CMD = {}

function CMD.start(conf)
    wsserver.on("connection", handler.connect)
    wsserver.on("disconnect", handler.disconnect)
    wsserver.on("message", handler.message)
    wsserver.on("error", handler.error)
    
    wsserver.listen(conf)
    skynet.error(string.format("Listen on %s:%d", conf.address, conf.port))
end

skynet.start(function()
    skynet.dispatch("lua", function (_, _, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end)