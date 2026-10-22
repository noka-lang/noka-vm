-- Twin of programs/case_loop.noka: Lua has no `case`, so an if chain that tests the same
-- conditions in the same order.
i = 0
n = 0
while i < 2000000 do
  local v
  if i % 3 == 0 then v = 1 elseif i % 3 == 1 then v = 2 else v = 3 end
  n = n + v
  i = i + 1
end
print(n)
