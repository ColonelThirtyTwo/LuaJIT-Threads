
local ThreadF = function(m)
	local ffi = require "ffi"
	local Mutex = require "jitthreads.Mutex"
	
	m = ffi.cast(ffi.typeof("$*",Mutex),m)
	for i=1,5 do
		assert(not m:lock(1), "Thread locked the mutex, somehow.")
		print("Timed out, i=",i)
	end
end

local Thread = require "jitthreads.thread"
local Mutex = require "jitthreads.mutex"

local m = Mutex()
assert(m:lock(), "Couldn't lock a new mutex")

print("Thread will try to aquire locked mutex 5 times with 1 second timeout")
local t = Thread(ThreadF, m)
t:join()
t:destroy()
m:unlock()
m:destroy()
