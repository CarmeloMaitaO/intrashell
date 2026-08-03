import unishell
import std/paths

var
  aux: Unishell = newUnishell()
  dir: Path = getCurrentDir() / Path("tests")
  sampleA: Path = dir / Path("sampleA.so")
  sampleB1: Path = dir / Path("sampleB1.so")
  sampleB2: Path = dir / Path("sampleB2.so")
  sampleC1: Path = dir / Path("sampleC1.so")
  sampleC2: Path = dir / Path("sampleC2.so")
  v0: Version = Version(major: 0, minor: 0, patch: 0)
  v1: Version = Version(major: 1, minor: 0, patch: 0)
  v2: Version = Version(major: 2, minor: 0, patch: 0)

discard aux.processOperations(
  newOperation(LOAD, "cmd1", v0, sampleA)
)

assert aux.shell("cmd1", "hello") == @["hello"]

discard aux.processOperations(
  newOperation(LOAD, "cmd1", v0, sampleB1)
)

assert aux.shell("cmd1", "hello") == @["hello"]

discard aux.processOperations(
  newOperation(LOAD, "cmd1", v0, sampleB2)
)

assert aux.shell("cmd1", "hello") == @["hello", "hello"]

discard aux.processOperations(
  newOperation(ROLLBACK, "cmd1", v0, sampleB1)
)

assert aux.shell("cmd1", "hello") == @["hello", "hello"]

discard aux.processOperations(
  newOperation(UPDATE, "cmd1", v0, sampleB1)
)

assert aux.shell("cmd1", "hello") == @["hello", "hello"]

discard aux.processOperations(
  newOperation(UPDATE, "cmd1", v1, sampleB1)
)

assert aux.shell("cmd1", "hello") == @["hello"]

discard aux.processOperations(
  newOperation(LOAD, "cmd1", v1, sampleB1),
  newOperation(LOAD, "cmd2", v1, sampleC1),
  newOperation(LOAD, "cmd3", v1, sampleC2),
)

assert aux.shell("cmd2", "call", "cmd1", "hello") == @["hello"]
assert aux.shell("cmd1", "hello") == @["hello"]
assert aux.shell("cmd2", "get") == @["0"]
assert aux.shell("cmd2", "set", "5") == @[""]
assert aux.shell("cmd2", "get") == @["5"]
