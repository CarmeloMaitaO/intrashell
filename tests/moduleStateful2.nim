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
