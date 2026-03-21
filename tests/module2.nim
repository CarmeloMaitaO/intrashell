import unishell

unishellBoilerplate(
  "subcommand2",
  (1, 0, 0),
  proc () = discard
):
  var
    command1: seq[string] = @["subcommand1", "inc"]
    command2: seq[string] = @["subcommand1", "dec"]
    command3: seq[string] = @["subcommand1", "get"]
  var aux: seq[string]
  case parameters[0]
  of "inc":
    command1.add(parameters[1])
    aux = shell(command1)
  of "dec":
    command2.add(parameters[1])
    aux = shell(command2)
  of "get":
    aux = shell(command3)
  else:
    aux.add "Subcommand not found"
  return aux
