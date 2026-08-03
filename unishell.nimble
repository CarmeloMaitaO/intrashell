# Package

version       = "1.0.0"
author        = "Carmelo Augusto Maita Orlando"
description   = "A library for dynamically loaded, nested, concurrent state-machines"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

proc run(args: varargs[string, `$`]) =
  var
    processedArgs: string = args[0]
  for arg in args[1..high(args)]:
    processedArgs = processedArgs & " " & arg
  exec(processedArgs)

proc compileSampleModules() =
  var
    modules: seq[seq[string]] = @[
      @["sampleA", "testA"],
      @["sampleB1", "testB1"],
      @["sampleB2", "testB2"],
      @["sampleC1", "testC1"],
      @["sampleC2", "testC2"]
    ]
    cmd: string = "nim c -d:useMalloc --app:lib "
  withDir("tests"):
    for module in modules:
      run(
        cmd,
        "--out:" & module[0] & ".so",
        "-d:" & module[1],
        "samples.nim"
      )

before test:
  compileSampleModules()
