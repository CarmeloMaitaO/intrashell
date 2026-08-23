import intrashell/module
import std/paths

when hostOS == "windows":
  var ext: string = ".dll"
elif hostOS == "macosx":
  var ext: string = ".dylib"
else:
  var ext: string = ".so"

var
  file: Path = getCurrentDir() / Path("tests") / Path("sampleA" & ext)

proc someProc(input: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
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
