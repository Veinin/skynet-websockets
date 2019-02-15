package.cpath = package.cpath .. ";luaclib/?.so"
package.path = package.path .. ";lualib/?.lua"

local socket = require "client.socket"
local wsclient = require "ws.client"

local client = wsclient.new()

client.on("open", function()
    print("on open...")
end)

client.on("close", function(code, reason)
    print("on close...", code, reason)
    os.exit(true)
end)

client.on("message", function(msg)
    print("on message...", msg)
end)

client:connect("127.0.0.1", 8888)

while true do
    client:dispatch_package()
	local cmd = socket.readstdin()
	if cmd then
        if cmd == "quit" then
            client:close()
        else
            client:send(cmd)
		end
	end
    socket.usleep(100)
end