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
      # Only one of the following should have a value
      dispatch: ImportedDispatch # This one for VTables
      path: Path # This one for dynamic modules

proc newOperation*(
  kind: UnishellOperationType,
  identity: string
): UnishellOperation {.raises: [ValueError].} =
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: identity)
  else:
    raise newException(ValueError, "To LOAD, UPDATE or ROLLBACK a module, you need to also supply a path or an ImportedDispatch")

proc newOperation*(
  kind: UnishellOperationType,
  identity: string,
  version: Version,
  path: Path
): UnishellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = UnishellOperation(kind: UNLOAD, identity: identity)
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
    result = UnishellOperation(kind: UNLOAD, identity: identity)
  of LOAD:
    result = UnishellOperation(kind: LOAD, identity: identity, version: version, dispatch: dispatch)
  of UPDATE:
    result = UnishellOperation(kind: UPDATE, identity: identity, version: version, dispatch: dispatch)
  of ROLLBACK:
    result = UnishellOperation(kind: ROLLBACK, identity: identity, version: version, dispatch: dispatch)

proc loadModule(operation: UnishellOperation, extraArg: string): Module {.raises: [ValueError].} =
  if operation.dispatch != nil:
    return loadModule(operation.identity, operation.version, operation.dispatch, extraArg)
  else:
    return loadModule(operation.identity, operation.version, DYNAMIC, operation.path, extraArg)

proc execute(unishell: Unishell, operation: UnishellOperation, slot: int) {.raises: [ValueError].} =
  case operation.kind
  of LOAD:
    unishell.registry[slot, operation.identity] = loadModule(operation, unishell.pointerToItself)
  of UNLOAD:
    unishell.registry.del(slot, operation.identity)
  of UPDATE:
    if unishell.registry[operation.identity].version < operation.version:
      unishell.registry[slot, operation.identity] = loadModule(operation, unishell.pointerToItself)
  of ROLLBACK:
    if unishell.registry[operation.identity].version > operation.version:
      unishell.registry[slot, operation.identity] = loadModule(operation, unishell.pointerToItself)

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
