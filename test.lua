
local Threading = require "threads"

local threads = {}

threads[1] = Threading.Thread(function()
	print("Thread 1 says hi!")
end)
threads[2] = Threading.Thread(function()
	error("Thread 2 has errors.")
end)

local l = #threads
for i=1,l do
	local ok, err = threads[i]:join()
	if ok then
		print("Thread "..tostring(i).." terminated successfully")
	else
		print("Thread "..tostring(i).." terminated with error: "..tostring(err))
	end
	
	threads[i]:destroy()
	threads[i] = nil
end
