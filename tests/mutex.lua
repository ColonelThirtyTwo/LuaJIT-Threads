
local ffi = require "ffi"
local Thread = require "jitthreads.thread"
local Mutex = require "jitthreads.mutex"

local function threadMain(threadid, m)
	local ffi = require "ffi"
	local Mutex = require "jitthreads.mutex"
	m = ffi.cast(ffi.typeof("$*",Mutex), m)
	
	for i=1,20 do
		m:lock()
		print("Thread "..threadid.." got mutex, i="..i)
		m:unlock()
	end
end

print("Each thread will try to aquire the mutex 20 times.")

local mutex = Mutex()
local threads = {}
for i=1,3 do
	threads[i] = Thread(threadMain, i, mutex)
end

for i=#threads,1,-1 do
	local ok, err = threads[i]:join()
	if ok then
		print("Thread "..i.." ran successfully")
	else
		print("Thread "..i.." terminated with error: "..tostring(err))
	end
	threads[i]:destroy()
	threads[i] = nil
end

mutex:destroy()
mutex = nil
