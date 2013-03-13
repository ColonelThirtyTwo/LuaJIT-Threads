
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
	

testThread(1, function()
	print("Thread 1 says hi!")
end)
testThread(2, function()
	error("Thread 2 has errors.")
end)
testThread(3, function(...)
	print("Got values:",...)
end, nil, 2, "c", true)

local vec = ffi.new("struct {int x, y, z;}", 100,200,300)
testThread(4, function(v)
	local ffi = require "ffi"
	v = ffi.cast("struct {int x,y,z;}*", v)
	print(v.x, v.y, v.z)
end, vec)
