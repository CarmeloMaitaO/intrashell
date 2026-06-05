##[ Unishell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "Unishell requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

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

proc newUnishell(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = cast[ptr UnishellObj](result)

# To refactor: start
type
  UnishellOperations* = enum
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  UnishellOperation* = object
    kind: UnishellOperations
    key: string
    version: Version
    path: Path
    module: StaticModule

proc newOperation*(
  kind: UnishellOperations,
  key: string,
  path: Path,
  module: StaticModule
): UnishellOperation =
  result.kind = kind
  result.key = key
  result.path = path
  result.module = module

proc processOperation*(unishell: Unishell, operation: UnishellOperation) =
  case operation.kind
  of LOAD:
    discard
  of UNLOAD:
    discard
  of UPDATE:
    discard
  of ROLLBACK:
    discard
# To refactor: end
