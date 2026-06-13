##[ Unishell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "Unishell requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

import unishell/[
  rcutable,
  module
]
export
  module.WrongParameters,
  module.CommandFailed,
  module.Version,
  module.newVersion,
  module.UserSuppliedDispatch,
  module.unishellQuit,
  module.dispatchBoilerplate,
  module.ModuleDescription,
  module.newModuleDescription,
  module.castPointerToString,
  module.castStringToPointer
import std/[
  paths
]

type
  UnishellObj* = object
    registry*: RcuTableRef[string, Module]
    pointerToItself*: string
  UnishellPtr* = ptr UnishellObj
  Unishell* = ref UnishellObj

proc newUnishell*(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = castPointerToString(cast[UnishellPtr](result))

proc shell*(unishell: UnishellObj, parameters: varargs[string, `$`]): seq[string] {.cdecl.} =
  return unishell.registry[parameters[0]].shell(parameters[1..high(parameters)])

proc shell*(unishell: Unishell, parameters: varargs[string, `$`]): seq[string] {.cdecl.} =
  return unishell.registry[parameters[0]].shell(parameters[1..high(parameters)])

proc shell*(unishell: UnishellPtr, parameters: varargs[string, `$`]): seq[string] {.cdecl.} =
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
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: identity)
  else:
    raise newException(ValueError, "To LOAD, UPDATE or ROLLBACK a module, you need to give a proper ModuleDescription")

proc newOperation*(
  kind: UnishellOperationType,
  description: ModuleDescription
): UnishellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: description.identity)
  of LOAD:
    result = UnishellOperation(kind: LOAD, description: description)
  of UPDATE:
    result = UnishellOperation(kind: UPDATE, description: description)
  of ROLLBACK:
    result = UnishellOperation(kind: ROLLBACK, description: description)

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
    (unishell.registry[slot, identity]).moduleInit(unishell.pointerToItself)
  of UNLOAD:
    identity = operation.identity
    unishell.registry.del(slot, identity)
  of UPDATE:
    identity = operation.description.identity
    versionOperation = operation.description.version
    versionRegistry = unishell.registry[identity].version
    if versionRegistry < versionOperation:
      unishell.registry[slot, identity] = loadModule(operation.description)
      (unishell.registry[slot, identity]).moduleInit(unishell.pointerToItself)
  of ROLLBACK:
    identity = operation.description.identity
    versionOperation = operation.description.version
    versionRegistry = unishell.registry[identity].version
    if versionRegistry > versionOperation:
      unishell.registry[slot, identity] = loadModule(operation.description)
      (unishell.registry[slot, identity]).moduleInit(unishell.pointerToItself)

proc processOperations*(unishell: Unishell, operations: varargs[UnishellOperation]): seq[string] =
  var errors: seq[string]
  unishell.registry.modify:
    for operation in operations:
      try:
        unishell.execute(operation, slot)
      except CatchableError as e:
        errors.add(e.msg)
  return errors

proc castStringToUnishellPtr*(p: string): UnishellPtr =
  result = cast[UnishellPtr](castStringToPointer(p))
