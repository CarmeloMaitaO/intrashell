when defined(testA): ##########################################
  # Plain module
  import intrashell/module
  proc someProc(input: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
    return input
  dispatchBoilerplate(someProc)
elif defined(testB1): #########################################
  # Stateless 1
  import intrashell
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    return parameters
  dispatchBoilerplate(entryPoint)
elif defined(testB2): #########################################
  # Stateless 2
  import intrashell
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    return (parameters & parameters)
  dispatchBoilerplate(entryPoint)
elif defined(testC1): #########################################
  # Stateful 1
  import intrashell
  import std/strutils
  var
    ushell: IntrashellPtr
    state: int
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = @[]
    var
      command: string = parameters[0]
      arguments = 1..high(parameters)
    case command
    of "INIT":
      try:
        ushell = castStringToIntrashellPtr(parameters[1])
      except Exception:
        discard
      state = 0
    of "SHUTDOWN":
      ushell = nil
      state = 0
    of "set":
      try:
        state = parameters[1].parseInt()
      except Exception:
        state = 0
    of "get":
      result = @[$state]
    of "call":
      result = ushell.shell(parameters[arguments])
  dispatchBoilerplate(entryPoint)
elif defined(testC2): #########################################
  # Stateful 2
  import intrashell
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = @[]
    var
      command: string = parameters[0]
      arguments = 1..high(parameters)
    case command
    of "reflect":
      result = parameters[arguments]
  dispatchBoilerplate(entryPoint)
