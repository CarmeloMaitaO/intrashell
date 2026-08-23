import intrashell/buffer

var
  auxSeqStr1: seq[string] = @["Potato"]
  auxSeqStr2: seq[string] = @["Potato", "Apple"]
  auxSeqStr3: seq[string] = @["Potato", "Apple", "Carrot"]
  auxSeqStr4: seq[string] = @["", "Apple", "Carrot"]
  auxSeqStr5: seq[string] = @["Potato", "", "Carrot"]
  auxSeqStr6: seq[string] = @["Potato", "Apple", ""]
  auxSeqStr7: seq[string] = @[""]
  auxSeqStr8: seq[string] = @["", ""]
  auxSeqStr9: seq[string] = @["", "", ""]
  auxSeqStr10: seq[string] = @[]

var auxBuffer: Buffer

proc testOutput(strings: seq[string]): seq[string] =
  var
    auxView: BufferView
    auxSeq: seq[string]
  auxBuffer.newBuffer(strings)
  auxView = auxBuffer.newBufferView()
  auxSeq = auxView.toSeq()
  return auxSeq
  
proc testConversion(strings: seq[string]): bool =
  return testOutput(strings) == strings

assert testConversion(auxSeqStr1)
assert testConversion(auxSeqStr2)
assert testConversion(auxSeqStr3)
assert testConversion(auxSeqStr4)
assert testConversion(auxSeqStr5)
assert testConversion(auxSeqStr6)
assert testConversion(auxSeqStr7)
assert testConversion(auxSeqStr8)
assert testConversion(auxSeqStr9)
assert testConversion(auxSeqStr10)
auxBuffer.dallocDarray(0)
assert auxBuffer.isNil()
