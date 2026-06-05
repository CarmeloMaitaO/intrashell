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
    kind: UnishellOperations
    key: string
    path: Path
    module: StaticModule

proc newUnishell(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = cast[ptr UnishellObj](result)

proc newOperation*(
  kind: UnishellOperations,
  key: string,
  path: Path,
  module: StaticModule
): UnishellOperation =
  result.kind = kind
  result.path = path
  result.module = module
  result.key = key

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
