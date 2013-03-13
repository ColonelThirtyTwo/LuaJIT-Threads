
local Tests = {
	"basic",
	"mutex",
	"join_timeout",
	"mutex_timeout",
}

for _,f in ipairs(Tests) do
	print("-- RUNNING TEST '"..f.."' -----------------------------------------------------")
	dofile("tests/"..f..".lua")
end
