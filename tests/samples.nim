when defined(testA): ##########################################
  # Plain module
  import unishell/module
  proc someProc(input: seq[string]): seq[string] =
    return input
  dispatchBoilerplate(someProc)
elif defined(testB1): #########################################
  # Stateless 1
  import unishell
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    return parameters
  dispatchBoilerplate(entryPoint)
elif defined(testB2): #########################################
  # Stateless 2
  import unishell
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    return (parameters & parameters)
  dispatchBoilerplate(entryPoint)
elif defined(testC1): #########################################
  # Stateful 1
  import unishell
  import std/strutils
  var
    ushell: UnishellPtr
    state: int
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = @[]
    var
      command: string = parameters[0]
      arguments = 1..high(parameters)
    case command
    of "INIT":
      try:
        ushell = castStringToUnishellPtr(parameters[1])
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
  import unishell
  import std/strutils
  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = @[]
    var
      command: string = parameters[0]
      arguments = 1..high(parameters)
    case command
    of "reflect":
      result = parameters[arguments]
  dispatchBoilerplate(entryPoint)
