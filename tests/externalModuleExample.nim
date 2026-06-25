when defined(unishellTestStateless1):
  import unishell

  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = parameters

  dispatchBoilerplate(entryPoint)
elif defined(unishellTestStateless2):
  import unishell

  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = parameters & parameters

  dispatchBoilerplate(entryPoint)
elif defined(unishellTestStateful1):
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
    of INITCOMMAND:
      ushell = castStringToUnishellPtr(parameters[1])
      state = 0
    of SHUTDOWNCOMMAND:
      unishellQuit()
    of "set":
      if high(arguments) < 1:
        raise newException(WrongParameters, "This command needs an argument")
      state = parameters[1].parseInt()
    of "get":
      result.add(state)
    of "call":
      if high(arguments) < 1:
        raise newException(WrongParameters, "This command needs an argument")
      result = ushell.shell(parameters[arguments])

  dispatchBoilerplate(entryPoint)
elif defined(unishellTestStateful2):
  import unishell
  import std/strutils

  proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed] .} =
    result = @[]
    var
      command: string = parameters[0]
      arguments = 1..high(parameters)
    case command
    of "reflect":
      if high(arguments) < 1:
        raise newException(WrongParameters, "This command needs an argument")
      result = parameters[arguments]

  dispatchBoilerplate(entryPoint)
