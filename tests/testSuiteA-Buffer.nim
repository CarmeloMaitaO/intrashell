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

var
  buffer1: Buffer = createBuffer(testSeq1)
  buffer2: Buffer = createBuffer(testSeq2)
  buffer3: Buffer = createBuffer(testSeq3)
  buffer4: Buffer = createBuffer(testSeq4)
  buffer5: Buffer = createBuffer(testSeq5)
  buffer6: Buffer = createBuffer(testSeq6)
  buffer7: Buffer = createBuffer(testSeq7)
  buffer8: Buffer = createBuffer(testSeq8)
  buffer9: Buffer = createBuffer(testSeq9)
  buffer10: Buffer = createBuffer(testSeq10)
  buffer11: Buffer = createBuffer(testSeq11)
  buffer12: Buffer = createBuffer(testSeq12)
  buffer13: Buffer = createBuffer(testSeq13)
  buffer14: Buffer = createBuffer(testSeq14)
  buffer15: Buffer = createBuffer(testSeq15)

assert buffer1.toSeq() == testSeq1
