-- Thread objects

local ffi = require "ffi"
local C = ffi.C
local int_b = ffi.typeof("int[1]")

local abstractions
if ffi.os == "Windows" then
	abstractions = require "jitthreads._win"
else
	abstractions = require "jitthreads._pthreads"
end

-- -----------------------------------------------------------------------------
-- Lua API & Helper functions

ffi.cdef[[
	static const int LUA_REGISTRYINDEX  = -10000;
	static const int LUA_ENVIRONINDEX   = -10001;
	static const int LUA_GLOBALSINDEX   = -10002;
	
	static const int LUA_TNONE         = -1;
	static const int LUA_TNIL          =  0;
	static const int LUA_TBOOLEAN      =  1;
	static const int LUA_TLIGHTUSERDAT =  2;
	static const int LUA_TNUMBER       =  3;
	static const int LUA_TSTRING       =  4;
	static const int LUA_TTABLE        =  5;
	static const int LUA_TFUNCTION     =  6;
	static const int LUA_TUSERDATA     =  7;
	static const int LUA_TTHREAD       =  8;
	
	typedef struct lua_State lua_State;
	typedef double lua_Number;
	typedef ptrdiff_t lua_Integer;
	
	lua_State* luaL_newstate(void);
	void luaL_openlibs(lua_State *L);
	void lua_close (lua_State *L);
	void lua_call(lua_State *L, int nargs, int nresults);
	void lua_checkstack (lua_State *L, int sz);
	void lua_settop (lua_State *L, int index);
	int lua_type (lua_State *L, int index);
	
	void  lua_pushnil (lua_State *L);
	void  lua_pushnumber (lua_State *L, lua_Number n);
	void  lua_pushinteger (lua_State *L, lua_Integer n);
	void  lua_pushlstring (lua_State *L, const char *s, size_t l);
	void  lua_pushstring (lua_State *L, const char *s);
	void  lua_pushboolean (lua_State *L, int b);
	void  lua_pushlightuserdata (lua_State *L, void *p);
	
	void lua_gettable (lua_State *L, int idx);
	void lua_getfield (lua_State *L, int idx, const char *k);
	void lua_rawget (lua_State *L, int idx);
	void lua_rawgeti (lua_State *L, int idx, int n);
	lua_Integer lua_tointeger (lua_State *L, int index);
	const char *lua_tolstring (lua_State *L, int index, size_t *len);
]]

local xpcall_debug_hook_dump = string.dump(function(err)
	return debug.traceback(tostring(err) or "<nonstring error>")
end)

local moveValues_typeconverters = {
	["number"]  = function(L,v) C.lua_pushnumber(L,v) end,
	["string"]  = function(L,v) C.lua_pushlstring(L,v,#v) end,
	["nil"]     = function(L,v) C.lua_pushnil(L) end,
	["boolean"] = function(L,v) C.lua_pushboolean(L,v) end,
	["cdata"]   = function(L,v) C.lua_pushlightuserdata(L,v) end,
}

-- Copies values into a lua state
local function moveValues(L, ...)
	local n = select("#", ...)
	
	if C.lua_checkstack(L, n) == 0 then
		error("out of memory")
	end
	
	for i=1,n do
		local v = select(i, ...)
		local conv = moveValues_typeconverters[type(v)]
		if not conv then
			error("Cannot pass argument "..i.." into thread: type "..type(v).." not supported")
		end
		conv(L, v)
	end
end

-- -----------------------------------------------------------------------------

local Thread = {}
Thread.__index = Thread
local thread_t = ffi.typeof([[struct {
	lua_State* state;
	$ thread;
}]], abstractions.thread_t)

--- Creates a new thread and starts it.
-- @param func Function to run. This will be serialized with string.dump.
-- @param ... Values to pass to func when the thread starts. Acceptable types
-- are nil, number, string, boolean, and cdata (which are converted into void*
-- lightuserdata which you must cast in the thread function)
function Thread:__new(func, ...)
	local funcd = string.dump(func)
	
	local t = ffi.new(self)
	local L = C.luaL_newstate()
	if L == nil then
		error("Could not allocate new state",2)
	end
	t.state = L
	
	C.luaL_openlibs(L)
	C.lua_settop(L,0)
	
	if C.lua_checkstack(L, 3) == 0 then
		error("out of memory")
	end
	
	-- Load pcall hook
	C.lua_getfield(L, C.LUA_GLOBALSINDEX, "loadstring")
	C.lua_pushlstring(L, xpcall_debug_hook_dump, #xpcall_debug_hook_dump)
	C.lua_call(L,1,1)
	
	-- Load main function
	C.lua_getfield(L, C.LUA_GLOBALSINDEX, "loadstring")
	C.lua_pushlstring(L, funcd, #funcd)
	C.lua_call(L,1,1)
	
	-- Copy arguments
	moveValues(L,...)
	
	t.thread = abstractions.thread_create(L)
	return t
end

--- Terminates the thread if it hasn't exited already and destroys it.
-- Note that terminating threads is dangerous (Google around for more info)
-- and it is preferred to just return from the threads main method.
function Thread:destroy()
	if self.thread ~= nil then
		abstractions.thread_destroy(self.thread)
		self.thread = nil
	end
	
	if self.state ~= nil then
		C.lua_close(self.state)
		self.state = nil
	end
end
Thread.__gc = Thread.destroy

--- Waits for the thread to terminate, or after the timeout has passed
-- @param timeout Number of seconds to wait. nil = no timeout
-- @return True if the thread exited successfully, false and nil
--         if the function returned due to timeout, or
--         false and a string error message if the thread terminated
--         due to an error.
function Thread:join(timeout)
	if self.thread == nil then error("invalid thread",2) end
	if abstractions.thread_join(self.thread, timeout) then
		local r = C.lua_tointeger(self.state, -1)
		if r ~= 0 then
			local len_b = int_b()
			local str = C.lua_tolstring(self.state, -2, len_b)
			return false, ffi.string(str, len_b[0])
		end
		return true
	else
		return false
	end
end

thread_t = ffi.metatype(thread_t, Thread)
return thread_t
