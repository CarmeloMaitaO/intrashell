##[ Unishell
A lightweight framework for dynamically loading and managing nested, concurrent state-machines.
]##
import unishell/[
  rcutable,
  buffer
]
export unishell/buffer
import std/[
  os,
  dynlib,
  paths
]

type
  UnishellObj* = object
    registry*: RcuTableRef[string, Module]
    pointerToItself*: ptr UnishellObj
  Unishell* = ref UnishellObj
  UnishellOperations* = enum
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  UnishellOperation* = object
    case kind: UnishellOperation

proc newUnishell(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = cast[ptr UnishellObj](result)

proc loadModule(unishell: UnishellObj, modules: varargs[StaticModule]) =
  modify(unishell.registry):
    for module in modules:
      unishell.registry[slot, module.identity] = module

proc loadModule(unishell: UnishellObj, modules: varargs[Path]) =
  modify(unishell.registry):
    for module in modules:
      unishell.registry[slot, module.identity] = module
