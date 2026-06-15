import unishell

proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
  result = parameters

dispatchBoilerplate(entryPoint)
