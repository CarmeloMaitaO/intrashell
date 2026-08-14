##[ Intrashell
A lightweight library for dynamically loading and managing nested, concurrent state-machines.
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "intrashell.nim requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}

import intrashell/[
  rcutable,
  module,
  buffer
]
export
  buffer,
  module
import std/paths

type
  IntrashellObj* = object
    registry: RcuTableRef[string, Module]
    pointerToItself: string
  IntrashellPtr* = ptr IntrashellObj
  Intrashell* = ref IntrashellObj

proc newIntrashell*(): Intrashell =
  new(result)
  result.registry = newRcuTable[string, Module]()
  result.pointerToItself = castPointerToString(cast[IntrashellPtr](result))

proc shell*(intrashell: IntrashellObj, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = intrashell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

proc shell*(intrashell: Intrashell, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = intrashell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

proc shell*(intrashell: IntrashellPtr, parameters: varargs[string, `$`]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  var
    command: string
    arguments = 1..parameters.high()
  try:
    command = parameters[0]
  except KeyError:
    raise newException(WrongParameters, "You need to specify a command")
  try:
    result = intrashell.registry[command].shell(parameters[arguments])
  except KeyError:
    raise newException(WrongParameters, "You need to specify the arguments")

type
  IntrashellOperationType* = enum
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  IntrashellOperation* = ref object
    identity: string
    case kind: IntrashellOperationType
    of UNLOAD:
      discard
    of LOAD, UPDATE, ROLLBACK:
      version: Version
      # Only one of the following should have a value
      dispatch: ImportedDispatch # This one for VTables
      path: Path # This one for dynamic modules

proc newOperation*(
  kind: IntrashellOperationType,
  identity: string
): IntrashellOperation {.raises: [ValueError].} =
  case kind
  of UNLOAD:
    result = IntrashellOperation(kind: UNLOAD, identity: identity)
  else:
    raise newException(ValueError, "To LOAD, UPDATE or ROLLBACK a module, you need to also supply a path or an ImportedDispatch")

proc newOperation*(
  kind: IntrashellOperationType,
  identity: string,
  version: Version,
  path: Path
): IntrashellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = IntrashellOperation(kind: UNLOAD, identity: identity)
  of LOAD:
    result = IntrashellOperation(kind: LOAD, identity: identity, version: version, path: path)
  of UPDATE:
    result = IntrashellOperation(kind: UPDATE, identity: identity, version: version, path: path)
  of ROLLBACK:
    result = IntrashellOperation(kind: ROLLBACK, identity: identity, version: version, path: path)

proc newOperation*(
  kind: IntrashellOperationType,
  identity: string,
  version: Version,
  dispatch: ImportedDispatch
): IntrashellOperation {.raises: [].} =
  case kind
  of UNLOAD:
    result = IntrashellOperation(kind: UNLOAD, identity: identity)
  of LOAD:
    result = IntrashellOperation(kind: LOAD, identity: identity, version: version, dispatch: dispatch)
  of UPDATE:
    result = IntrashellOperation(kind: UPDATE, identity: identity, version: version, dispatch: dispatch)
  of ROLLBACK:
    result = IntrashellOperation(kind: ROLLBACK, identity: identity, version: version, dispatch: dispatch)

proc loadModule(operation: IntrashellOperation, extraArg: string): Module {.raises: [ValueError].} =
  if operation.dispatch != nil:
    return loadModule(operation.identity, operation.version, operation.dispatch, extraArg)
  else:
    return loadModule(operation.identity, operation.version, DYNAMIC, operation.path, extraArg)

proc execute(intrashell: Intrashell, operation: IntrashellOperation, slot: int) {.raises: [ValueError].} =
  case operation.kind
  of LOAD:
    intrashell.registry[slot, operation.identity] = loadModule(operation, intrashell.pointerToItself)
  of UNLOAD:
    intrashell.registry.del(slot, operation.identity)
  of UPDATE:
    if intrashell.registry[operation.identity].version < operation.version:
      intrashell.registry[slot, operation.identity] = loadModule(operation, intrashell.pointerToItself)
  of ROLLBACK:
    if intrashell.registry[operation.identity].version > operation.version:
      intrashell.registry[slot, operation.identity] = loadModule(operation, intrashell.pointerToItself)

proc processOperations*(intrashell: Intrashell, operations: varargs[IntrashellOperation]): seq[string] =
  var errors: seq[string]
  intrashell.registry.modify:
    for operation in operations:
      try:
        intrashell.execute(operation, slot)
      except CatchableError as e:
        errors.add(e.msg)
  return errors

proc castStringToIntrashellPtr*(p: string): IntrashellPtr =
  result = cast[IntrashellPtr](castStringToPointer(p))
