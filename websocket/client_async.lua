local socket = require'socket.socket'
local sync = require'websocket.sync'
local tools = require'websocket.tools'

local coxpcall = require "websocket.coxpcall"

local VANILLA_LUA51 = _VERSION == "Lua 5.1" and not jit
local pcall = VANILLA_LUA51 and pcall or coxpcall.pcall
local corunning = VANILLA_LUA51 and coroutine.running or coxpcall.running

local new = function()
	local self = {}

	local emscripten = sys.get_sys_info().system_name == "HTML5"

	local on_connected_fn
	local on_disconnected_fn
	local on_message_fn

	local function pcall_and_print(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			print(err)
		end
	end

	local function on_connected(ok, err)
		if on_connected_fn then
			if ok then err = nil end
			pcall_and_print(on_connected_fn, ok, err)
		end
	end

	local function on_message(message, err)
		if on_message_fn then
			if message then err = nil end
			pcall_and_print(on_message_fn, message, err)
		end
	end

	local function on_disconnected()
		if on_disconnected_fn then
			pcall_and_print(on_disconnected_fn)
		end
	end

	-- this must be defined before calling sync.extend()
	self.sock_connect = function(self, host, port)
		assert(corunning(), "You must call the connect function from a coroutine")
		local addrinfo = socket.dns.getaddrinfo(host)
		for _,info in pairs(addrinfo) do
			if info.family == "inet6" then
				self.sock = socket.tcp6()
			else
				self.sock = socket.tcp()
			end
			self.sock:settimeout(0)
			self.sock:connect(host,port)

			local sendt = { self.sock }
			-- start polling for successful connection or error
			while true do
				local receive_ready, send_ready, err = socket.select(nil, sendt, 0)
				if err == "timeout" then
					coroutine.yield()
				elseif err then
					break
				elseif #send_ready == 1 then
					return true
				end
			end
		end
		self.sock = nil
		return nil, "Unable to connect"
	end

	-- this must be defined before calling sync.extend()
	self.sock_send = function(self, data, i, j)
		assert(corunning(), "You must call the send function from a coroutine")
		local sent = 0
		i = i or 1
		j = j or #data
		while i < j do
			self.sock:settimeout(0)
			local bytes_sent, err = self.sock:send(data, i, j)
			if err == "timeout" or err == "wantwrite" then
				coroutine.yield()
			elseif err then
				return nil, err
			else
				coroutine.yield()
			end
			i = i + bytes_sent
			sent = sent + bytes_sent
		end
		return sent
	end

	-- this must be defined before calling sync.extend()
	self.sock_receive = function(self, pattern, prefix)
		assert(corunning(), "You must call the receive function from a coroutine")
		prefix = prefix or ""
		local data, err
		repeat
			self.sock:settimeout(0)
			data, err, prefix = self.sock:receive(pattern, prefix)
			local timeout = (err == "timeout") or (err == "wantread")
			if timeout then
				coroutine.yield()
			end
		until data or (err and not timeout)
		return data, err, prefix
	end

	-- this must be defined before calling sync.extend()
	self.sock_close = function(self)
		-- doing a call to shutdown in HTML5 will result in
		-- "unsupported socketcall syscall 13"
		-- https://github.com/britzl/defold-websocket/issues/7
		-- to be honest not really sure shutdown is needed at all since the
		-- socket is closed...
		-- removed here: https://github.com/lipp/lua-websockets/blob/master/src/websocket/client_sync.lua#L30
		-- but not here: https://github.com/lipp/lua-websockets/blob/master/src/websocket/client_copas.lua#L32
		if not emscripten then
			self.sock:shutdown()
		end
		self.sock:close()
	end

	-- this is an optional callback function used by sync.lua
	self.on_close = function(self)
		on_disconnected()
	end

	self = sync.extend(self)

	local coroutines = {}

	local sync_connect = self.connect
	local sync_send = self.send
	local sync_receive = self.receive
	local sync_close = self.close

	local function start_on_message_loop()
		local co = coroutine.create(function()
			while self.sock and self.state == "OPEN" do
				if emscripten then
					-- I haven't figured out how to know the length of the received data
					-- receiving with a pattern of "*a" or "*l" will block indefinitely
					-- A message is read as chunks of data at a time, concatenating it as
					-- it is received and repeated until an error
					local chunk_size = 1024
					local data, err, partial
					repeat
						self.sock:settimeout(0)
						local bytes_to_read = data and (#data + chunk_size) or chunk_size
						data, err, partial = self.sock:receive(bytes_to_read, data)
						if partial and partial ~= "" then
							data = partial
						end
						coroutine.yield()
					until err
					if data then
						on_message(data)
					end
					if err == "closed" then
						self.state = 'CLOSED'
						self:sock_close()
						on_disconnected()
					end
				else
					local message, opcode, was_clean, code, reason = sync_receive(self)
					if message then
						on_message(message)
					end
				end
			end
			coroutine.yield()
		end)
		coroutines[co] = "on_message"
	end

	-- monkeypatch self.connect
	self.connect = function(...)
		local co = coroutine.create(function(self, ws_url, ws_protocol, ssl_params)
			if emscripten then
				local protocol, host, port, uri = tools.parse_url(ws_url)
				local ok, err = self:sock_connect(host .. uri, port)
				if ok then
					self.state = "OPEN"
				end
				on_connected(ok, err)
			else
				local ok, err_or_protocol, headers = pcall(function()
					return sync_connect(self, ws_url, ws_protocol, ssl_params)
				end)
				on_connected(ok, err_or_protocol)
			end
			start_on_message_loop()
		end)
		coroutines[co] = "connect"
		coroutine.resume(co, ...)
	end

	-- monkeypatch self.send
	self.send = function(self,data,opcode)
		local co = coroutine.create(function(self,data,opcode)
			if emscripten then
				local bytes, err = self.sock_send(self,data)
				if err or #data ~= bytes then
					print(err or "Didn't send all bytes")
					self.state = 'CLOSED'
					self:sock_close()
					on_disconnected()
				end
			else
				local ok,was_clean,code,reason = sync_send(self,data,opcode)
				if not ok then
					print(reason)
				end
			end
		end)
		coroutines[co] = "send"
		coroutine.resume(co, self,data,opcode)
	end

	-- monkeypatch self.receive
	self.receive = function(...)
		local co = coroutine.create(function(...)
			if emscripten then
				local data, err = self.sock_receive(...)
				if not data or err then
					self.state = 'CLOSED'
					self:sock_close()
					on_disconnected()
				else
					on_message(data)
				end
			else
				local message, opcode, was_clean, code, reason = sync_receive(...)
				if message then
					on_message(message)
				end
			end
		end)
		coroutines[co] = "receive"
		coroutine.resume(co, ...)
	end

	-- monkeypatch self.close
	self.close = function(...)
		local co = coroutine.create(function(...)
			if emscripten then
				self.sock_close(...)
				self.state = "CLOSED"
				self:on_close()
			else
				sync_close(...)
			end
		end)
		coroutines[co] = "close"
		coroutine.resume(co, ...)
	end



	self.step = function(self)
		for co,action in pairs(coroutines) do
			local status = coroutine.status(co)
			if status == "suspended" then
				coroutine.resume(co)
			elseif status == "dead" then
				coroutines[co] = nil
			end
		end
	end

	self.on_message = function(self, fn)
		on_message_fn = fn
	end

	self.on_connected = function(self, fn)
		on_connected_fn = fn
	end

	self.on_disconnected = function(self, fn)
		on_disconnected_fn = fn
	end

	return self
end

return new
