
local ffi = require "ffi"
local Threading = require "threads"

local function threadMain(threadid, m)
	local ffi = require "ffi"
	local Threading = require "threads"
	m = ffi.cast(Threading.MutexP, m)
	
	for i=1,20 do
		m:lock()
		print("Thread "..threadid.." got mutex, i="..i)
		m:unlock()
	end
end

local mutex = Threading.Mutex()
local threads = {}
for i=1,3 do
	threads[i] = Threading.Thread(threadMain, i, mutex)
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
