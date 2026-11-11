-- Twin of programs/churn.noka. Top-level variables are globals in both languages.
i = 0
s = ""
while i < 1000000 do
  s = "abcdefghijklmnopqrstuvwxyz" .. "abcdefghijklmnopqrstuvwxyz"
  i = i + 1
end
print(s)
