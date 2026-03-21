import unishell
import std/strutils

var state: int = 2

unishellBoilerplate(
  "subcommand1",
  (1, 0, 1),
  proc () = discard
):
  var aux: seq[string]
  case parameters[0]
  of "inc":
    state *= parseInt(parameters[1])
    aux.add $state
  of "dec":
    state = int(float(state) / float(parseInt(parameters[1])))
    aux.add $state
  of "get":
    aux.add $state
  else:
    aux.add "Subcommand not found"
  return aux
