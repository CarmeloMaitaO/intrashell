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
