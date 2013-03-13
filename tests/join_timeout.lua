
local ThreadF = function()
	local ffi = require "ffi"
	if ffi.os == "Windows" then
		ffi.cdef[[void Sleep(uint32_t);]]
		ffi.C.Sleep(5000)
	else
		ffi.cdef[[unsigned int sleep(unsigned int);]]
		ffi.C.sleep(5)
	end
end

local Thread = require "jitthreads.thread"
local Mutex = require "jitthreads.mutex"

local t = Thread(ThreadF)
print("Thread will run for 5 seconds. Joining with 1 second timeouts.")
while true do
	local ok, err = t:join(1)
	if ok then
		print("  Joined")
		break
	elseif not err then
		print("  Timed out")
	else
		print("  Error:")
		print(err)
		break
	end
end
t:destroy()
