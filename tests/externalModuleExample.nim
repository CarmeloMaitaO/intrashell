import unishell/module

proc someProc(input: seq[string]): seq[string] =
  return input

dispatchBoilerplate(someProc)
