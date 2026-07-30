##[ Unishell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "unishell.nim requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

import unishell/[
  rcutable,
  module,
  buffer
]
export
  buffer,
  module
import std/paths

type
  UnishellObj* = object
    registry: RcuTableRef[string, Module]
    pointerToItself: string
  UnishellPtr* = ptr UnishellObj
  Unishell* = ref UnishellObj

proc newUnishell*(): Unishell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = castPointerToString(cast[UnishellPtr](result))

proc shell*(unishell: UnishellObj, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = unishell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

proc shell*(unishell: Unishell, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = unishell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

proc shell*(unishell: UnishellPtr, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = unishell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

type
  UnishellOperationType* = enum
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  UnishellOperation* = ref object
    identity: string
    case kind: UnishellOperationType
    of UNLOAD:
      discard
    of LOAD, UPDATE, ROLLBACK:
      version: Version
      dispatch: ImportedDispatch
      path: Path

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
  identity: string,
  version: Version,
  path: Path
): UnishellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: identity, version: version, path: path)
  of LOAD:
    result = UnishellOperation(kind: LOAD, identity: identity, version: version, path: path)
  of UPDATE:
    result = UnishellOperation(kind: UPDATE, identity: identity, version: version, path: path)
  of ROLLBACK:
    result = UnishellOperation(kind: ROLLBACK, identity: identity, version: version, path: path)

proc newOperation*(
  kind: UnishellOperationType,
  identity: string,
  version: Version,
  dispatch: ImportedDispatch
): UnishellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: identity, version: version, dispatch: dispatch)
  of LOAD:
    result = UnishellOperation(kind: LOAD, identity: identity, version: version, dispatch: dispatch)
  of UPDATE:
    result = UnishellOperation(kind: UPDATE, identity: identity, version: version, dispatch: dispatch)
  of ROLLBACK:
    result = UnishellOperation(kind: ROLLBACK, identity: identity, version: version, dispatch: dispatch)

proc execute(unishell: Unishell, operation: UnishellOperation, slot: int) =
  var
    identity: string
    versionRegistry: Version
    versionOperation: Version
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
