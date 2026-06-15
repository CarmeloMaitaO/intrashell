# Package

version       = "0.1.0"
author        = "Carmelo Maita"
description   = "A framework for dynamically loaded, nested, concurrent state-machines"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.4"

# proc run(args: varargs[string, `$`]) =
#   var
#     processedArgs: string = args[0]
#   for arg in args[1..high(args)]:
#     processedArgs = processedArgs & " " & arg
#   exec(processedArgs)

# proc testModuleName(kind: string, number: int, output: bool): string =
#   var
#     name: string = "module" & kind & $number
#     ext: string = ".so"
#   case buildOS:
#   of "windows":
#     ext = ".dll"
#   of "macosx":
#     ext = ".dylib"
#   if output:
#     return name & ext
#   else:
#     return name & ".nim"

# proc compileTestModules() =
#   var
#     kind1: string = "Stateless"
#     kind2: string = "Stateful"
#     modules: seq[seq[string]] = @[
#       @[testModuleName(kind1, 1, false), testModuleName(kind1, 1, true)],
#       @[testModuleName(kind1, 2, false), testModuleName(kind1, 2, true)],
#       @[testModuleName(kind2, 1, false), testModuleName(kind2, 1, true)],
#       @[testModuleName(kind2, 2, false), testModuleName(kind2, 2, true)]
#     ]
#     inputFile: string
#     outputFile: string
#     cmd: string = "nim"
#     args: string = "c -d:useMalloc --app:lib "
#   withDir("tests"):
#     for modulePair in modules:
#       inputFile = modulePair[0]
#       outputFile = "--out:" & modulePair[1]
#       run(
#         "nim",
#         "c",
#         "-d:useMalloc",
#         "--app:lib",
#         "--mm:arc",
#         outputFile,
#         inputFile
#       )

# before test:
#   compileTestModules()
