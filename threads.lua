
local bit = require "bit"
local ffi = require "ffi"
local C = ffi.C
local threadslib = ffi.load("luajitthreads")
local uint32_b = ffi.typeof("uint32_t[1]")
local int_b = ffi.typeof("int[1]")
local str_b = ffi.typeof("char[?]")

local Threading = {}

-- Unique value representing a function timed out
Threading.TIMEOUT = setmetatable({}, {__tostring=function() return "Threading.TIMEOUT" end})

-- -----------------------------------------------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------------------------------------------
-- Thread structures and abstractions

local Thread = {}
Thread.__index = Thread
local thread_t
local raw_thread_create
local raw_thread_destroy
local raw_thread_running
local raw_thread_join

local Mutex = {}
Mutex.__index = Mutex
local mutex_t
local raw_mutex_create
local raw_mutex_destroy
local raw_mutex_get
local raw_mutex_release

-- -----------------------------------------------------------------------------------------------------------------
-- Windows Threads
if ffi.os == "Windows" then
	do
		local ok, lib = pcall(ffi.load, "luajitthreads")
		ffi.cdef[[int luajitthreads_win(void* ud);]]
		if ok then
			Threading._Callback = lib.luajitthreads_win
		end
	end
	
	ffi.cdef[[
		static const int STILL_ACTIVE = 259;
		static const int FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000;
		static const int FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200;
		static const int WAIT_ABANDONED = 0x00000080;
		static const int WAIT_OBJECT_0 = 0x00000000;
		static const int WAIT_TIMEOUT = 0x00000102;
		static const int WAIT_FAILED = 0xFFFFFFFF;
		static const int INFINITE = 0xFFFFFFFF;
		
		int CloseHandle(void*);
		int GetExitCodeThread(void*,uint32_t*);
		uint32_t WaitForSingleObject(void*, uint32_t);
		
		typedef uint32_t (__stdcall *ThreadProc)(void*);
		void* CreateThread(
			void* lpThreadAttributes,
			size_t dwStackSize,
			ThreadProc lpStartAddress,
			void* lpParameter,
			uint32_t dwCreationFlags,
			uint64_t* lpThreadId
		);
		int TerminateThread(void*, uint32_t);
		
		void* CreateMutexA(void*, int, const char*);
		int ReleaseMutex(void*);
		
		uint32_t GetLastError();
		uint32_t FormatMessage(
			uint32_t dwFlags,
			const void* lpSource,
			uint32_t dwMessageId,
			uint32_t dwLanguageId,
			char* lpBuffer,
			uint32_t nSize,
			va_list *Arguments
		);
	]]
	
	thread_t = ffi.typeof[[struct {
		lua_State* state;
		void* thread;
	}]]
	
	mutex_t = ffi.typeof[[struct {
		void* mutex;
	}]]
	
	local function error_win(lvl)
		local errcode = C.GetLastError()
		local str = str_b(1024)
		local numout = C.FormatMessage(bit.bor(C.FORMAT_MESSAGE_FROM_SYSTEM,C.FORMAT_MESSAGE_IGNORE_INSERTS), nil, errcode, 0, str, 1023)
		if numout == 0 then
			error("Windows Error: (Error calling FormatMessage)", lvl)
		else
			error("Windows Error: "..ffi.string(str, numout), lvl)
		end
	end
	
	local function error_check(result)
		if result == 0 then
			error_win(4)
		end
	end
	
	raw_thread_create = function(ud)
		assert(Threading._Callback, "No Thread._Callback! Is the luajitthreads library available?")
		local t = C.CreateThread(nil, 0, Threading._Callback, ud, 0, nil)
		if t == nil then
			error_win(3)
		end
		return t
	end
	
	raw_thread_running = function(t)
		local rt = uint32_b()
		error_check(C.GetExitCodeThread(t, rt))
		
		return rt[0] == C.STILL_ACTIVE
	end
	
	raw_thread_destroy = function(t)
		if raw_thread_running(t) then
			error_check(C.TerminateThread(t, 0))
		end
		error_check(C.CloseHandle(t))
	end
	
	raw_thread_join = function(t, timeout)
		if timeout then
			timeout = timeout*1000
		else
			timeout = C.INFINITE
		end
		
		local r = C.WaitForSingleObject(t, timeout)
		if r == C.WAIT_OBJECT_0 or r == C.WAIT_ABANDONED then
			return true
		elseif r == C.WAIT_TIMEOUT then
			return false
		else
			error_win(3)
		end
	end
	
	raw_mutex_create = function()
		return ffi.new(mutex_t, C.CreateMutexA(nil, false, nil))
	end
	
	raw_mutex_destroy = function(m)
		if m.mutex ~= nil then
			error_check(C.CloseHandle(m.mutex))
			m.mutex = nil
		end
	end
	
	raw_mutex_get = function(m, timeout)
		assert(m ~= nil)
		if m.mutex == nil then error("invalid mutex",3) end
		if timeout then
			timeout = timeout*1000
		else
			timeout = C.INFINITE
		end
		
		local r = C.WaitForSingleObject(m.mutex, timeout)
		if r == C.WAIT_OBJECT_0 or r == C.WAIT_ABANDONED then
			return true
		elseif r == C.WAIT_TIMEOUT then
			return false
		else
			error_win(3)
		end
	end
	
	raw_mutex_release = function(m)
		assert(m ~= nil)
		if m.mutex == nil then error("invalid mutex",3) end
		error_check(C.ReleaseMutex(m.mutex))
	end
end

-- -----------------------------------------------------------------------------------------------------------------
-- pthreads

if ffi.os ~= "Windows" then
	error("pthreads coming soon")
end

-- -----------------------------------------------------------------------------------------------------------------
-- Thread API

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
	
	t.thread = raw_thread_create(t.state)
	return t
end

--- Terminates the thread if it hasn't exited already and destroys it.
-- Note that terminating threads is dangerous (Google around for more info)
-- and it is preferred to just return from the threads main method.
function Thread:destroy()
	if self.thread ~= nil then
		raw_thread_destroy(self.thread)
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
-- @return True if the thread exited successfully. Otherwise it returns
-- false and the error message. If the error message is the value in
-- Threading.TIMEOUT, then the function exited because the timeout
-- was elapsed
function Thread:join(timeout)
	if self.thread == nil then error("invalid thread",2) end
	if raw_thread_join(self.thread) then
		local r = C.lua_tointeger(self.state, -1)
		if r ~= 0 then
			local len_b = int_b()
			local str = C.lua_tolstring(self.state, -2, len_b)
			return false, ffi.string(str, len_b[0])
		end
		return true
	else
		return false, Threading.TIMEOUT
	end
end

thread_t = ffi.metatype(thread_t, Thread)

-- -----------------------------------------------------------------------------------------------------------------
-- Mutex API

--- Creates a mutex
function Mutex:__new()
	return raw_mutex_create()
end

--- Trys to lock the mutex. If the mutex is already locked, it blocks
-- for timeout seconds.
-- @param timeout Time to wait for the mutex to become unlocked. nil = wait forever,
-- 0 = do not block
function Mutex:lock(timeout)
	return raw_mutex_get(self, timeout)
end

--- Unlocks the mutex. If the current thread is not the owner, throws an error
function Mutex:unlock()
	raw_mutex_release(self)
end

--- Destroys the mutex.
function Mutex:destroy()
	raw_mutex_destroy(self)
end
Mutex.__gc = Mutex

mutex_t = ffi.metatype(mutex_t, Mutex)

-- -----------------------------------------------------------------------------------------------------------------

Threading.Thread = thread_t
Threading.Mutex = mutex_t
Threading.ThreadP = ffi.typeof("$*",thread_t)
Threading.MutexP = ffi.typeof("$*",mutex_t)

return Threading
