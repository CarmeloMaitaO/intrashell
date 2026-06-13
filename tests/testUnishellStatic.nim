import unishell

var
  ushell: Unishell = newUnishell()
  ushellPtr: UnishellPtr
  v100: Version = newVersion(1, 0, 0)
  v010: Version = newVersion(0, 1, 0)
  v001: Version = newVersion(0, 0, 1)
  commonIdentity: string = "cmd"
  stateTesterIdentity: string = "state"

proc pV001(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = parameters

proc pV010(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = parameters & parameters

proc pV100(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = parameters & parameters & parameters

proc stateTester(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  case parameters[0]
  of "INIT":
    try:
      ushellPtr = castStringToUnishellPtr(parameters[1])
    except CatchableError:
      discard
    result = @[]
  else:
    result = @[]
    try:
      result = ushellPtr.shell(@[commonIdentity] & parameters)
    except CatchableError:
      discard

var
  mPV001: ModuleDescription = newModuleDescription(commonIdentity, v001, pV001)
  mPV010: ModuleDescription = newModuleDescription(commonIdentity, v010, pV010)
  mPV100: ModuleDescription = newModuleDescription(commonIdentity, v100, pV100)
  stateTesterDesc: ModuleDescription = newModuleDescription(stateTesterIdentity, v100, stateTester)

assert ushell.processOperations(
  newOperation(LOAD, mPV001)
) == @[]

assert ushell.shell(commonIdentity, "Some", "Strings") == @["Some", "Strings"]
assert ushell.shell(commonIdentity) == @[]
assert ushell.shell(commonIdentity, "") == @[""]
assert ushell.shell(commonIdentity, 1) == @["1"]
assert ushell.shell(commonIdentity, 1, 2, 3) == @["1", "2", "3"]
assert ushell.shell(commonIdentity, 1, 2'u, 3.0) == @["1", "2", "3.0"]

assert ushell.processOperations(
  newOperation(UPDATE, mPV010)
) == @[]
  
assert ushell.shell(commonIdentity, 1) == @["1", "1"]

assert ushell.processOperations(
  newOperation(UPDATE, mPV100)
) == @[]
  
assert ushell.shell(commonIdentity, 1) == @["1", "1", "1"]

assert ushell.processOperations(
  newOperation(UPDATE, mPV001)
) == @[]
  
assert ushell.shell(commonIdentity, 1) == @["1", "1", "1"]

assert ushell.processOperations(
  newOperation(ROLLBACK, mPV001)
) == @[]
  
assert ushell.shell(commonIdentity, 1) == @["1"]

assert ushell.processOperations(
  newOperation(ROLLBACK, mPV100)
) == @[]
  
assert ushell.shell(commonIdentity, 1) == @["1"]


assert ushell.processOperations(
  newOperation(LOAD, stateTesterDesc)
) == @[]

assert ushell.shell(stateTesterIdentity, 1) == @["1"]

assert ushell.processOperations(
  newOperation(UNLOAD, commonIdentity)
) == @[]

var aux: seq[string]

try:
  aux = ushell.shell(commonIdentity, 1)
except KeyError:
  aux = @["Failed"]
finally:
  discard

assert aux == @["Failed"]
