# Defold-WebSocket
This project aims to provide a cross platform implementation of the WebSockets protocol for Defold projects. Defold-WebSocket is based on the [lua-websocket](https://github.com/lipp/lua-websockets) project with additional code to perform asynchronous web socket communication on all platforms (see notes on emscripten and WebSockets below).

## Installation
You can use the modules from this project in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the `dependencies` field under `project` add:

	https://github.com/britzl/defold-websocket/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/defold-websocket/releases).

## Dependencies
This project depends on the LuaSocket and LuaSec projects:

* [defold-luasocket](https://github.com/britzl/defold-luasocket/archive/0.11.zip)
* [defold-luasec](https://github.com/sonountaleban/defold-luasec/archive/master.zip)

# Some very important notes and gotchas
## 1. Emscripten and WebSockets
Emscripten will automatically create WebSocket connections when creating normal TCP sockets connections. Emscripten will also take care of the WebSocket handshake and encode/decode of the frames. The solution provided by lua-websocket will always attempt to perform handshake and encode/decode which means that the solution will fail on HTML5. This project provides an asynchronous client that seamlessly bypasses the WebSocket code on HTML5 and interacts with the socket directly.

## 2. Sec-WebSocket-Protocol and Chrome
Emscripten will create WebSockets with the Sec-WebSocket-Protocol header set to "binary" during the handshake. Google Chrome expects the response header to include the same Sec-WebSocket-Protocol header. Some WebSocket examples and the commonly used [Echo Test service](https://www.websocket.org/echo.html) does not respect this and omits the response header. This will cause WebSocket connections to fail during the handshake phase in Chrome. Firefox does impose the same restriction. I'm not sure about other browsers.

# Testing using a Python based echo server
There's a Python based WebSocket echo server in the tools folder. The echo server is built using the [simple-websocket-server](https://github.com/dpallot/simple-websocket-server) library. Start it by running `python websocketserver.py` from a terminal. Connect to it from `localhost:9999`. The library has been modified to return the Sec-WebSocket-Protocol response header, as described above.
