# Skynet WebSocket 扩展支持

本项目是针对 WebSocket 在 Skynet 中使用进行高度定制了一套易用的代码，本项目深度参考了 [lua-websockets](https://github.com/lipp/lua-websockets) 的实现，并在其基础上进行改进，使之能很容易的嵌入到 skynet 框架中去。

## Examples

### 简单的 echo 服务器使用

文件 `ws/server.lua` 允许你对服务器注册相关事件，你可以调用 `server.on(event, callback)` 来注册相关事件回调，事件类型如下：

- 建立连接 `connection`。
- 断开连接 `disconnect`。
- 产生错误 `error`。
- 接受客户端消息 `message`。

``` lua
local skynet = require "skynet"
local ws = require "ws.websocket"
local wsserver = require "ws.server"

wsserver.on("connection", function(fd, addr) 
	skynet.error("on connect:", fd, addr)
end)

wsserver.on("disconnect", function(fd, code, reason) 
	skynet.error("on close:", fd, code, reason)
end)

wsserver.on("error", function(fd, err)
	skynet.error("on error:", fd, err)
end)

wsserver.on("message", function(fd, msg) 
	ws.write(fd, msg)
end)

wsserver.listen({
	address = "127.0.0.1",
	port = 8888
})
```

上面只是一个 WebSocket 服务器的简单使用方式，具体代码实现请参考：`service/echoserver.lua` 的实现。

你可以直接启动一个 `echoserver` 服务：

```
local s = skynet.newservice("echoserver")
skynet.call(s, "lua", "start", {
	address = "127.0.0.1",
	port = 8888,
})
```

### 简单的 echo 客户端使用

文件 `ws/client.lua` 是一个 WebSocket 客户端的实现，客户端可以调用 `client.new()` 产生一个客户端 socket 实例，并调用 `client.on(event, callback)` 函数来注册客户端相关事件回调，客户端支持的事件如下：

- 建立连接 `open`。
- 关闭连接 `close`。
- 接受到服务器消息 `message`。

``` lua
local wsclient = require "ws.client"

local client = wsclient.new()

client.on("open", function()
    print("on open...")
end)

client.on("close", function(code, reason)
    print("on close...", code, reason)
end)

client.on("message", function(msg)
    print("on message...", msg)
end)

client:connect("127.0.0.1", 8888)
```

注册完客户端事件处理函数后，你可以调用 `client.connect(host, port)` 连接到目标服务器。

在文件 `client/echoclient.lua` 中实现了一个简单的 WebSocket 回射客户端，你可以使用 lua 命令直接运行： `lua client/echoclient.lua` 查看效果。

## 实际使用实例

根据 skynet [gateserver](https://github.com/cloudwu/skynet/wiki/GateServer) 的网关服务器实现，本项目提供了针对于 WebSocket 实现了一个网关服务器模板，你通文件 `service/wsgateserver.lua` 、 `service/wswatchdog.lua` 来启动一个网关服务器，通过 WebSocket 连接和客户端交换数据。

```
local skynet = require "skynet"

skynet.start(function()
	local watchdog = skynet.newservice("wswatchdog")
	skynet.call(watchdog, "lua", "start", {
		host = "127.0.0.1",
		port = 8888,
	})

	skynet.exit()
end)
```