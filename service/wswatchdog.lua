local skynet = require "skynet"

local CMD = {}
local SOCKET = {}

function SOCKET.close(fd)
	skynet.error("socket close", fd)
end

function SOCKET.error(fd, msg)
	skynet.error("socket error", fd, msg)
end

function SOCKET.data(fd, msg)
	skynet.error("socket msg", fd, msg)
end

function CMD.start(conf)
	skynet.call(gate, "lua", "open" , conf)
	skynet.error("Watchdog listen on %d", conf.port)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...) -- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	gate = skynet.newservice("wsgateserver")
end)