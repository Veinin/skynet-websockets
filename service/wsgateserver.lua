local skynet = require "skynet"
local wsserver = require "ws.server"

local watchdog
local connection = {} -- fd -> { fd , client, agent, addr }

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local handler = {}

function handler.connect(fd, addr)
    skynet.error("on connect:", fd, addr)
    connection[fd] = {
        fd = fd,
        addr = addr
    }
end

function handler.message(fd, msg, opcode)
    local c = connection[fd]
    if not c then
        skynet.error(string.format("Drop message from fd (%d) : %s", fd, msg))
        return
    end

    local agent = c.agent
    if agent then
        skynet.redirect(agent, c.client, "client", fd, msg)
    else
        skynet.send(watchdog, "lua", "socket", "data", fd, msg, opcode)
    end
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
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, err)
    skynet.error("on error:", fd, err)
    close_fd(fd)
    skynet.send(watchdog, "lua", "socket", "error", fd, err)
end

local CMD = {}

function CMD.open(source, conf)
    watchdog = conf.watchdog or source

    wsserver.on("connection", handler.connect)
    wsserver.on("disconnect", handler.disconnect)
    wsserver.on("message", handler.message)
    wsserver.on("error", handler.error)
    wsserver.listen(conf)
end

function CMD.close()
	wsserver.close()
end

function CMD.forward(source, fd, client, address)
	local c = assert(connection[fd])
	c.client = client or 0
	c.agent = address or source
end

function CMD.kick(source, fd, code)
    wsserver.close_client(fd, code, "kick")
end

skynet.start(function()
	skynet.dispatch("lua", function (_, address, cmd, ...)
		local f = CMD[cmd]
		if f then
			skynet.ret(skynet.pack(f(address, ...)))
		end
	end)
end)