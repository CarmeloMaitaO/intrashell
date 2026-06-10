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
  UnishellOperationType* = enum
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  UnishellOperation* = ref object
    case kind: UnishellOperationType
    of UNLOAD: identity: string
    of LOAD, UPDATE, ROLLBACK: description: ModuleDescription

proc newOperation*(
  kind: UnishellOperationType,
  identity: string
): UnishellOperation {.raises: [ValueError].} =
  if kind != UNLOAD:
    raise newException(ValueError, "To LOAD, UPDATE or ROLLBACK a module, you need to give a proper ModuleDescription")
  else:
    result = UnishellOperation(kind, identity)

proc newOperation*(
  kind: UnishellOperationType,
  description: ModuleDescription
): UnishellOperation {.raises: [].} =
  if kind == UNLOAD:
    result = UnishellOperation(kind, description.identity)
  else:
    result = UnishellOperation(kind, description)

proc execute(unishell: Unishell, operation: UnishellOperation, slot: int) =
  var
    identity: string
    versionRegistry: Version
    versionOperation: Version
    dispatch: UserSuppliedDispatch
    path: Path
  case operation.kind
  of LOAD:
    identity = operation.description.identity
    unishell.registry[slot, identity] = loadModule(operation.description)
  of UNLOAD:
    identity = operation.identity
    unishell.registry.del(slot, identity)
  of UPDATE:
    identity = operation.description.identity
    versionOperation = operation.description.version
    versionRegistry = unishell.registry[identity].version
    if versionRegistry < versionOperation:
      unishell.registry[slot, identity] = loadModule(operation.description)
  of ROLLBACK:
    identity = operation.description.identity
    versionOperation = operation.description.version
    versionRegistry = unishell.registry[identity].version
    if versionRegistry > versionOperation:
      unishell.registry[slot, identity] = loadModule(operation.description)

proc processOperations*(unishell: Unishell, operations: UnishellOperations): seq[string] =
  var errors: seq[string]
  unishell.registry.modify:
    for operation in operations:
      try:
        unishell.execute(operation, slot)
      except CatchableError as e:
        errors.add(e.msg)
  return errors
