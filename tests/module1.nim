import unishell
import std/strutils

var state: int = 0

template unishellBoilerplate*(identity: string, version: Version, beforeShutdown: proc (), body: untyped): untyped =
  var ushell: Unishell
  proc init(u: ptr Unishell) =
    ushell = u
  proc shutdown() =
    beforeShutdown()
  proc getUnishell(): Unishell =
    return ushell
  proc shell(parameters: varargs[string, `$`]): seq[string] =
    return ushell.shell(parameters)
  proc dispatch (parameters {.inject.}: varargs[string, `$`]): seq[string] =
    body
  proc moduleFactory*(): ModulePtr {.exportc: "moduleFactory", dynlib.} =
    result = newModule(identity, version, init, dispatch, shutdown)

unishellBoilerplate(
  "subcommand1",
  (1, 0, 0),
  proc () = discard
):
  var aux: seq[string]
  case parameters[0]
  of "inc":
    state += parseInt(parameters[1])
    aux.add $state
  of "dec":
    state -= parseInt(parameters[1])
    aux.add $state
  of "get":
    aux.add $state
  else:
    aux.add "Subcommand not found"
  return aux


