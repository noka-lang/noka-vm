-- Twin of programs/machine.noka. Lua can't make a fresh state from a script, so each round
-- compiles and runs the short program from source, the closest Lua-side equivalent. Noka prints
-- once per machine and this prints once in total, which favours Lua by one write per round.
local src = "local x = 6 return x * 7"
local result
for _ = 1, 10000 do
  result = load(src)()
end
print(result)
