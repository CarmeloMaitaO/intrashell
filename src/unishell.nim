##[ Unishell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "Unishell requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

import unishell/[
  rcutable,
  module
]
export module.Version, module.UserSuppliedDispatch, module.unishellQuit, module.dispatchBoilerplate
import std/[
  paths
]

type
  UnishellObj* = object
    registry*: RcuTableRef[string, Module]
    pointerToItself*: ptr UnishellObj
  Unishell* = ref UnishellObj

proc newUnishell*(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = cast[ptr UnishellObj](result)

proc shell*(unishell: Unishell, parameters: varargs[string, `$`]): seq[string] {.cdecl.} =
  return unishell.registry[parameters[0]].shell(parameters[1..high(parameters)])

type
  UnishellOperation* = ref object of RootObj
  UnishellLoadOperation* = ref object of UnishellOperation
    description: ModuleDescription
  UnishellUnloadOperation* = ref object of UnishellOperation
    identity: string
  UnishellUpdateOperation* = ref object of UnishellOperation
    description: ModuleDescription
  UnishellRollbackOperation* = ref object of UnishellOperation
    description: ModuleDescription
  UnishellOperations* = seq[UnishellOperation]

proc newLoadOperation*(
  identity: string,
  version: Version,
  dispatch: UserSuppliedDispatch
): UnishellLoadOperation =
  ##[
    Creates a new `UnishellLoadOperation`. Example:

    ```nim
    var operation = newLoadOperation(
      "someIdentity",
      Version(1, 0, 0),
      someUserSuppliedDispatch
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, dispatch)

proc newLoadOperation*(
  identity: string,
  version: Version,
  path: Path
): UnishellLoadOperation =
  ##[
    Creates a new `UnishellLoadOperation`. Example:

    ```nim
    var operation = newLoadOperation(
      "someIdentity",
      Version(1, 0, 0),
      somePath
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, path)
  
proc newUnloadOperation*(identity: string): UnishellUnloadOperation =
  ##[
    Creates a new `UnishellUnloadOperation`. Example:

    ```nim
    var operation = newUnloadOperation("someIdentity")
    ```
  ]##
  new(result)
  result.identity = identity

proc newUpdateOperation*(
  identity: string,
  version: Version,
  dispatch: UserSuppliedDispatch
): UnishellUpdateOperation =
  ##[
    Creates a new `UnishellUpdateOperation`. Example:

    ```nim
    var operation = newUpdateOperation(
      "someIdentity",
      Version(1, 0, 0),
      someUserSuppliedDispatch
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, dispatch)

proc newUpdateOperation*(
  identity: string,
  version: Version,
  path: Path
): UnishellUpdateOperation =
  ##[
    Creates a new `UnishellUpdateOperation`. Example:

    ```nim
    var operation = newUpdateOperation(
      "someIdentity",
      Version(1, 0, 0),
      somePath
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, path)

proc newRollbackOperation*(
  identity: string,
  version: Version,
  dispatch: UserSuppliedDispatch
): UnishellRollbackOperation =
  ##[
    Creates a new `UnishellRollbackOperation`. Example:

    ```nim
    var operation = newRollbackOperation(
      "someIdentity",
      Version(1, 0, 0),
      someUserSuppliedDispatch
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, dispatch)

proc newRollbackOperation*(
  identity: string,
  version: Version,
  path: Path
): UnishellRollbackOperation =
  ##[
    Creates a new `UnishellRollbackOperation`. Example:

    ```nim
    var operation = newRollbackOperation(
      "someIdentity",
      Version(1, 0, 0),
      somePath
    )
    ```
  ]##
  new(result)
  result.description = newModuleDescription(identity, version, path)

method execute(operation: UnishellOperation, unishell: Unishell, slot: int) {.base.} =
  quit "Execute called on base UnishellOperation!"

method execute(operation: UnishellLoadOperation, unishell: Unishell, slot: int) =
  var
    identity = operation.description.identity
  unishell.registry[slot, identity] = loadModule(operation.description)

method execute(operation: UnishellUnloadOperation, unishell: Unishell, slot: int) =
  var
    identity = operation.identity
  unishell.registry.del(slot, identity)

method execute(operation: UnishellUpdateOperation, unishell: Unishell, slot: int) =
  var
    identity = operation.description.identity
    versionRegistry = unishell.registry[identity].version
    versionOperation = operation.description.version
  if versionRegistry < versionOperation:
    unishell.registry[slot, identity] = loadModule(operation.description)

method execute(operation: UnishellRollbackOperation, unishell: Unishell, slot: int) =
  var
    identity = operation.description.identity
    versionRegistry = unishell.registry[identity].version
    versionOperation = operation.description.version
  if versionRegistry > versionOperation:
    unishell.registry[slot, identity] = loadModule(operation.description)

proc processOperations*(unishell: Unishell, operations: UnishellOperations): seq[string] =
  var errors: seq[string]
  unishell.registry.modify:
    for operation in operations:
      try:
        operation.execute(unishell, slot)
      except CatchableError as e:
        errors.add(e.msg)
  return errors
