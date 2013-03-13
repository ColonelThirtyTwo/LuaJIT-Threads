
local Tests = {
	"basic",
	"mutex",
}

for _,f in ipairs(Tests) do
	print("-- RUNNING TEST '"..f.."' -----------------------------------------------------")
	dofile("tests/"..f..".lua")
end
