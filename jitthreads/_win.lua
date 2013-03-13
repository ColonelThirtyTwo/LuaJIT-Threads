-- Windows threading abstractions

local ffi = require "ffi"
local bit = require "bit"
local C = ffi.C
local str_b = ffi.typeof("char[?]")
local uint32_b = ffi.typeof("uint32_t[1]")

assert(ffi.os == "Windows")

local Windows = {}

-- -----------------------------------------------------------------------------

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
	uint32_t FormatMessageA(
		uint32_t dwFlags,
		const void* lpSource,
		uint32_t dwMessageId,
		uint32_t dwLanguageId,
		char* lpBuffer,
		uint32_t nSize,
		va_list *Arguments
	);
]]

-- Raw, OS-specific types
Windows.thread_t = ffi.typeof("void*")
Windows.mutex_t = ffi.typeof("void*")

-- Some helper functions
local function error_win(lvl)
	local errcode = C.GetLastError()
	local str = str_b(1024)
	local numout = C.FormatMessageA(bit.bor(C.FORMAT_MESSAGE_FROM_SYSTEM,
		C.FORMAT_MESSAGE_IGNORE_INSERTS), nil, errcode, 0, str, 1023, nil)
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

do
	local ok, lib = pcall(ffi.load, "luajitthreads")
	if ok then
		ffi.cdef[[int luajitthreads_win(void* ud);]]
		Windows._Callback = lib.luajitthreads_win
	end
end

-- -----------------------------------------------------------------------------
-- Thread

function Windows.thread_create(userdata)
	assert(Windows._Callback,
		"luajitthreads.dll couldn't be loaded and Windows._Callback not specified manually")
	local t = C.CreateThread(nil, 0, Windows._Callback, userdata, 0, nil)
	if t == nil then
		error_win(3)
	end
	return t
end

function Windows.thread_destroy(thread)
	if Windows.thread_running(thread) then
		error_check(C.TerminateThread(thread, 0))
	end
	error_check(C.CloseHandle(thread))
end

function Windows.thread_running(thread)
	local rt = uint32_b()
	error_check(C.GetExitCodeThread(thread, rt))
	return rt[0] == C.STILL_ACTIVE
end

function Windows.thread_join(thread, timeout)
	if timeout then
		timeout = timeout*1000
	else
		timeout = C.INFINITE
	end
	
	local r = C.WaitForSingleObject(thread, timeout)
	if r == C.WAIT_OBJECT_0 or r == C.WAIT_ABANDONED then
		return true
	elseif r == C.WAIT_TIMEOUT then
		return false
	else
		error_win(3)
	end
end

-- -----------------------------------------------------------------------------
-- Mutex

function Windows.mutex_create()
	return C.CreateMutexA(nil, false, nil)
end

function Windows.mutex_destroy(mutex)
	if mutex ~= nil then
		error_check(C.CloseHandle(mutex))
		mutex = nil
	end
end

function Windows.mutex_get(mutex, timeout)
	if timeout then
		timeout = timeout*1000
	else
		timeout = C.INFINITE
	end
	
	local r = C.WaitForSingleObject(mutex, timeout)
	if r == C.WAIT_OBJECT_0 or r == C.WAIT_ABANDONED then
		return true
	elseif r == C.WAIT_TIMEOUT then
		return false
	else
		error_win(3)
	end
end

function Windows.mutex_release(mutex)
	error_check(C.ReleaseMutex(mutex))
end

-- -----------------------------------------------------------------------------
return Windows
