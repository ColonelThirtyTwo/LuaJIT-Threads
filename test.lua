
local Threading = require "threads"

local function f()
	print("Thread says hi!")
end

local threads = {}
local nthreads = 3
for i=1,nthreads do
	table.insert(threads, Threading.Thread(f))
end
for i=1,nthreads do
	threads[i]:join()
	threads[i]:destroy()
	threads[i] = nil
end
