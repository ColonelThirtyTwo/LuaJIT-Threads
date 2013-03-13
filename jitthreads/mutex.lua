-- Mutex objects

local ffi = require "ffi"
local C = ffi.C

local abstractions
if ffi.os == "Windows" then
	abstractions = require "jitthreads._win"
else
	abstractions = require "jitthreads._pthreads"
end

-- -----------------------------------------------------------------------------

local Mutex = {}
Mutex.__index = Mutex
local mutex_t = ffi.typeof([[struct {
	$ mutex;
}]], abstractions.mutex_t)

--- Creates a mutex
function Mutex:__new()
	return ffi.new(self, abstractions.mutex_create())
end

--- Trys to lock the mutex. If the mutex is already locked, it blocks
-- for timeout seconds.
-- @param timeout Time to wait for the mutex to become unlocked. nil = wait forever,
-- 0 = do not block
function Mutex:lock(timeout)
	if self.mutex == nil then error("Invalid mutex",2) end
	return abstractions.mutex_get(self.mutex, timeout)
end

--- Unlocks the mutex. If the current thread is not the owner, throws an error
function Mutex:unlock()
	if self.mutex == nil then error("Invalid mutex",2) end
	abstractions.mutex_release(self.mutex)
end

--- Destroys the mutex.
function Mutex:destroy()
	if self.mutex then
		abstractions.mutex_destroy(self.mutex)
		self.mutex = nil
	end
end
Mutex.__gc = Mutex

mutex_t = ffi.metatype(mutex_t, Mutex)
return mutex_t
