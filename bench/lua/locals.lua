-- Twin of programs/locals.noka.
do
  local i = 0
  local sum = 0
  while i < 2000000 do
    sum = sum + i
    i = i + 1
  end
  print(sum)
end
