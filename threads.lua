
local bit = require "bit"
local ffi = require "ffi"
local C = ffi.C
local threadslib = ffi.load("luajitthreads")
local uint32_b = ffi.typeof("uint32_t[1]")
local str_b = ffi.typeof("char[?]")

local Threading = {}

-- -----------------------------------------------------------------------------------------------------------------
-- Lua API
ffi.cdef[[
	static const int LUA_REGISTRYINDEX  = -10000;
	static const int LUA_ENVIRONINDEX   = -10001;
	static const int LUA_GLOBALSINDEX   = -10002;

	typedef struct lua_State lua_State;
	typedef double lua_Number;
	typedef ptrdiff_t lua_Integer;
	typedef int (*lua_CFunction) (lua_State *L);
	
	lua_State *(luaL_newstate) (void);
	void luaL_openlibs(lua_State *L);
	void lua_close (lua_State *L);
	void  (lua_call) (lua_State *L, int nargs, int nresults);
	
	void  (lua_pushnil) (lua_State *L);
	void  (lua_pushnumber) (lua_State *L, lua_Number n);
	void  (lua_pushinteger) (lua_State *L, lua_Integer n);
	void  (lua_pushlstring) (lua_State *L, const char *s, size_t l);
	void  (lua_pushstring) (lua_State *L, const char *s);
	//const char *(lua_pushvfstring) (lua_State *L, const char *fmt, va_list argp);
	//const char *(lua_pushfstring) (lua_State *L, const char *fmt, ...);
	void  (lua_pushcclosure) (lua_State *L, lua_CFunction fn, int n);
	void  (lua_pushboolean) (lua_State *L, int b);
	void  (lua_pushlightuserdata) (lua_State *L, void *p);
	int   (lua_pushthread) (lua_State *L);

	void  (lua_gettable) (lua_State *L, int idx);
	void  (lua_getfield) (lua_State *L, int idx, const char *k);
	void  (lua_rawget) (lua_State *L, int idx);
	void  (lua_rawgeti) (lua_State *L, int idx, int n);
	void  (lua_createtable) (lua_State *L, int narr, int nrec);
	void *(lua_newuserdata) (lua_State *L, size_t sz);
	int   (lua_getmetatable) (lua_State *L, int objindex);
	void  (lua_getfenv) (lua_State *L, int idx);
	
	void luaL_checkstack (lua_State *L, int sz, const char *msg);
]]

-- -----------------------------------------------------------------------------------------------------------------
-- Thread structures and abstractions

local raw_thread_create
local raw_thread_destroy
local raw_thread_running
local raw_thread_join

local Thread = {}
Thread.__index = Thread
local thread_t = ffi.typeof[[struct {
	lua_State* state;
	void* thread;
}]]

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
		int CloseHandle(void*);
		int GetExitCodeThread(void*,uint32_t*);
		uint32_t WaitForSingleObject(void*, uint32_t);
		
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
		
		local r = C.WaitForSingleObject(t, timeout*1000)
		if r == C.WAIT_OBJECT_0 or r == C.WAIT_ABANDONED then
			return true
		elseif r == C.WAIT_TIMEOUT then
			return false
		else
			error_win(3)
		end
	end
end

-- -----------------------------------------------------------------------------------------------------------------
-- pthreads

if ffi.os ~= "Windows" then
	error("pthreads coming soon")
end

-- -----------------------------------------------------------------------------------------------------------------
-- Thread API

local xpcall_debug_hook_dump = string.dump(function(err)
	return debug.traceback(tostring(err) or "<nonstring error>", 3)
end)

--- Creates a new thread and starts it.
-- @param func Function to run. This will be serialized with string.dump, so all upvalues will be set to nil.
function Thread:__new(func)
	local t = ffi.new(self)
	t.state = C.luaL_newstate()
	if t.state == nil then
		error("Could not allocate new state",2)
	end
	
	C.luaL_openlibs(t.state)
	
	local funcd = string.dump(func)
	C.luaL_checkstack(t.state, 3, "out of memory")
	
	C.lua_getfield(t.state, C.LUA_GLOBALSINDEX, "loadstring")
	C.lua_pushlstring(t.state, xpcall_debug_hook_dump, #xpcall_debug_hook_dump)
	C.lua_call(t.state,1,1)
	
	C.lua_getfield(t.state, C.LUA_GLOBALSINDEX, "loadstring")
	C.lua_pushlstring(t.state, funcd, #funcd)
	C.lua_call(t.state,1,1)
	
	t.thread = raw_thread_create(t.state)
	return t
end

--- Terminates and destroys the thread.
-- Note that terminating the thread is pretty dangerous.
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
-- @return True if the thread has terminated, false if timed out
function Thread:join(timeout)
	if self.thread == nil then error("invalid thread",2) end
	return raw_thread_join(self.thread, timeout)
end

--- Returns true if the thread is running, false if not
function Thread:running()
	if self.thread == nil then return false end
	return raw_thread_running(self.thread)
end

thread_t = ffi.metatype(thread_t, Thread)

-- -----------------------------------------------------------------------------------------------------------------
-- Mutex API

-- -----------------------------------------------------------------------------------------------------------------

Threading.Thread = thread_t

return Threading
