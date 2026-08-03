import unishell/module
import std/paths

var
  file: Path = getCurrentDir() / Path("tests") / Path("sampleA.so")

proc someProc(input: seq[string]): seq[string] =
  return input

dispatchBoilerplate(someProc)

var aux: Module

aux = loadModule(
    "someProc",
    Version(major: 1, minor: 0, patch: 0),
    dispatch
  )

assert aux.shell("something") == @["something"]

aux = loadModule(
    "someProc",
    Version(major: 1, minor: 0, patch: 0),
    DYNAMIC,
    file
  )

assert aux.shell("something") == @["something"]
