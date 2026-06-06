##[ Unishell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "Unishell requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

import unishell/[
  rcutable,
  buffer,
  module
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

type
  UnishellRegistryOperation* = ref object of RootObj
  UnishellRegistryLoadOperation* = ref object of UnishellRegistryOperation
    module*: Module
  UnishellRegistryUnloadOperation* = ref object of UnishellRegistryOperation
    identity*: string
  UnishellRegistryUpdateOperation* = ref object of UnishellRegistryOperation
    module*: Module
  UnishellRegistryRollbackOperation* = ref object of UnishellRegistryOperation
    module*: Module
  UnishellRegistryOperations* = seq[UnishellRegistryOperation]

proc newUnishellRegistryLoadOperation*(module: Module): UnishellRegistryLoadOperation =
  ##[
    Creates a new `UnishellRegistryLoadOperation`. Example:

    ```nim
    var operation = newUnishellRegistryLoadOperation(
      createModule(
        "someIdentity",
        Version(1, 0, 0),
        somePathOrUserSuppliedDispatch
      )
    )
    ```
  ]##
  new(result)
  result.identity = identity
  result.version = version
  result.module = module

method execute(unishell: Unishell, operation: UnishellRegistryOperation, slot: int) {.base.} =
  quit "Execute called on base UnishellRegistryOperation!"

method execute(unishell: Unishell, operation: UnishellRegistryLoadOperation, slot: int) =
  discard

method execute(unishell: Unishell, operation: UnishellRegistryUnloadOperation, slot: int) =
  discard

method execute(unishell: Unishell, operation: UnishellRegistryUpdateOperation, slot: int) =
  discard

method execute(unishell: Unishell, operation: UnishellRegistryRollbackOperation, slot: int) =
  discard

proc processOperations*(unishell: Unishell, operations: UnishellRegistryOperations): seq[string] =
  unishell.registry.modify:
    var errors: seq[string]
    for operation in operations:
      try:
        unishell.execute(operation, slot)
      except CatchableError as e:
        errors.add(e)
