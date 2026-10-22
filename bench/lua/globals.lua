-- Twin of programs/globals.noka.
i = 0
sum = 0
while i < 2000000 do
  sum = sum + i
  i = i + 1
end
print(sum)
