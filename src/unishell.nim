##[ Unishell
A lightweight framework for dynamically loading and managing nested, concurrent state-machines.
]##
import unishell/rcutable
import std/[
  os,
  dynlib,
  paths
]

type
  Unishell* = ref object
    directory: string
    registry: newRcuTable[string, Module]
  UnishellPtr* = ptr Unishell

type
  ModuleInitProc* = proc (unishell: UnishellPtr) {.nimcall.}
    ## Procedural interface for module initialization.
  ModuleDispatchProc* = proc (parameters: varargs[string, `$`]): seq[string] {.nimcall.}
    ## Procedural interface for module command dispatching.
  ModuleShutdownProc* = proc () {.nimcall.}
    ## Procedural interface for module shutdown.

proc newUnishell(directory: string, staticModules: varargs[Module]): Unishell =
  var ushell: Unishell
  ushell.directory = directory
  for module in staticModules:
    loadModule(ushell, module)
  ushell.flagsAndCounter.store(uint(0b01))
  return ushell
