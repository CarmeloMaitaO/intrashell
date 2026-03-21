import std/[
  unittest,
  tables,
  paths
]
import unishell

let
  currentDirectory: Path = getCurrentDir() / Path("tests")
  module1Path: Path = currentDirectory / Path("libmodule1.so")#[
      A module that implements some procedures:
        - `inc`: takes 1 integer argument to increment the state
        - `dec`: takes 1 integer argument to decrement the state
        - `inc`: returns the state
      Both `inc` and `dec` also returns the current state.
      State starts at 0
    ]#
  module2Path: Path = currentDirectory / Path("libmodule2.so") #[
      A module that calls the procedures of `module1`:
    ]#
  module3Path: Path = currentDirectory / Path("libmodule3.so") #[
      An update for `module1`:
        - `inc`: now multiply
        - `dec`: now divides
    ]#
var
  cli: Unishell = newUnishell()
  command1 = @["subcommand1", "inc", "2"]
  command2 = @["subcommand1", "dec", "1"]
  command3 = @["subcommand1", "get"]
  command4 = @["subcommand2", "inc", "3"]
  command5 = @["subcommand2", "dec", "2"]
  command6 = @["subcommand2", "get"]
  command7 = @["subcommand1", "dec", "2"]

var counter: int = 0
template wrapper (error: typedesc, body: untyped) =
  try:
    echo counter, ": Begin"
    body
    echo counter, ": Done"
    counter += 1
  except error:
    check false

echo "TEST UNISHELL BEGINS"
cli.loadModule(module1Path)
echo "loaded module 1"
cli.loadModule(module2Path)
echo "loaded module 2"

assert (cli.shell(command3) == @["0"])
echo "Executed shell command"
assert (cli.shell(command1) == @["2"])
echo "Executed shell command"
assert (cli.shell(command2) == @["1"])
echo "Executed shell command"
cli.loadModule(module3Path)
echo "Updated module"
assert (cli.shell(command1) == @["4"])
echo "Executed shell command"
assert (cli.shell(command7) == @["2"])
echo "Executed shell command"
cli.loadModule(module1Path)
echo "Loaded module"
assert (cli.shell(command4) == @["3"])
echo "Executed shell command"
assert (cli.shell(command5) == @["1"])
echo "Executed shell command"
cli.unloadModule("subcommand1")
cli.unloadModule("subcommand2")
echo "Tests Done"
