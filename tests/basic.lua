
local ffi = require "ffi"
local Thread = require "jitthreads.thread"

local function testThread(c, f, ...)
	local thread = Thread(f, ...)
	local ok, err = thread:join()
	if ok then
		print("Thread "..c.." ran successfully")
	else
		print("Thread "..c.." terminated with error: "..tostring(err))
	end
	thread:destroy()
end
	
print("Basic hello world thread")
testThread(1, function()
	print("\tThread 1 says hi!")
end)

print("\nThread error test")
testThread(2, function()
	error("Thread 2 has errors.")
end)

print("\nArguments test")
testThread(3, function(...)
	print("\tGot values:",...)
end, nil, 2, "c", true)

print("\nCdata test")
local vec = ffi.new("struct {int x, y, z;}", 100,200,300)
testThread(4, function(v)
	local ffi = require "ffi"
	v = ffi.cast("struct {int x,y,z;}*", v)
	print("",v.x, v.y, v.z)
end, vec)
