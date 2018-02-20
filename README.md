# Defold-WebSocket
This project aims to provide a cross platform asynchronous implementation of the WebSockets protocol for Defold projects. Defold-WebSocket is based on the [lua-websocket](https://github.com/lipp/lua-websockets) project with additional code to handle WebSocket connections for HTML5 builds. The additional code is required since Emscripten (which is used for Defold HTML5 builds) will automatically upgrade normal TCP sockets connections to WebSocket connections. Emscripten will also take care of encoding and decoding the WebSocket frames. The WebSocket implementation in this project will bypass the handshake and frame encode/decode of lua-websocket when running in HTML5 builds.


# Installation
You can use the modules from this project in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the `dependencies` field under `project` add:

	https://github.com/britzl/defold-websocket/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/defold-websocket/releases).

## Dependencies
This project depends on the LuaSocket and LuaSec projects:

* [defold-luasocket](https://github.com/britzl/defold-luasocket/archive/0.11.zip)
* [defold-luasec](https://github.com/sonountaleban/defold-luasec/archive/master.zip)

You need to add these as dependencies in your game.project file, along with the dependency to this project itself.


# Usage

	local client_async = require "websocket.client_async"

	function init(self)
		self.ws = client_async()

		self.ws:on_connected(function(ok, err)
			if ok then
				print("Connected")
				msg.post("#", "acquire_input_focus")
			else
				print("Unable to connect", err)
			end
		end)

		self.ws:on_message(function(message)
			print("Received message", message)
		end)

		self.ws:connect("ws://localhost:9999")
	end

	function update(self, dt)
		self.ws:step()
	end

	function on_input(self, action_id, action)
		if action_id == hash("fire") and action.released then
			self.ws:send("Some data")
		end
	end


# Important note on Sec-WebSocket-Protocol and Chrome
Emscripten will create WebSockets with the Sec-WebSocket-Protocol header set to "binary" during the handshake. Google Chrome expects the response header to include the same Sec-WebSocket-Protocol header. Some WebSocket examples and the commonly used [Echo Test service](https://www.websocket.org/echo.html) does not respect this and omits the response header. This will cause WebSocket connections to fail during the handshake phase in Chrome. Firefox does impose the same restriction. I'm not sure about other browsers.


# Testing using a Python based echo server
There's a Python based WebSocket echo server in the tools folder. The echo server is built using the [simple-websocket-server](https://github.com/dpallot/simple-websocket-server) library. Start it by running `python websocketserver.py` from a terminal. Connect to it from `localhost:9999`. The library has been modified to return the Sec-WebSocket-Protocol response header, as described above.
