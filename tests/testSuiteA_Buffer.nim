import unishell/buffer

var
  testSeq1: seq[string] = @[]
  testSeq2: seq[string] = @[""]
  testSeq3: seq[string] = @["text"]
  testSeq4: seq[string] = @["", ""]
  testSeq5: seq[string] = @["text", ""]
  testSeq6: seq[string] = @["", "text"]
  testSeq7: seq[string] = @["text", "text"]
  testSeq8: seq[string] = @["", "", ""]
  testSeq9: seq[string] = @["text", "", ""]
  testSeq10: seq[string] = @["", "text", ""]
  testSeq11: seq[string] = @["", "", "text"]
  testSeq12: seq[string] = @["text", "text", ""]
  testSeq13: seq[string] = @["", "text", "text"]
  testSeq14: seq[string] = @["text", "", "text"]
  testSeq15: seq[string] = @["text", "text", "text"]

assert createBuffer(testSeq1) == testSeq1
assert createBuffer(testSeq2) == testSeq2
assert createBuffer(testSeq3) == testSeq3
assert createBuffer(testSeq4) == testSeq4
assert createBuffer(testSeq5) == testS5q5
assert createBuffer(testSeq6) == testSeq6
assert createBuffer(testSeq7) == testSeq7
assert createBuffer(testSeq8) == testSeq8
assert createBuffer(testSeq9) == testSeq9
assert createBuffer(testSeq10) == testSeq10
assert createBuffer(testSeq11) == testSeq11
assert createBuffer(testSeq12) == testSeq12
assert createBuffer(testSeq13) == testSeq13
assert createBuffer(testSeq14) == testSeq14
assert createBuffer(testSeq15) == testSeq15
