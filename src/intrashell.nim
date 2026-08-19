##[ Intrashell
A lightweight library for using shared libraries as dynamic modules in Nim.

**To use procedures that accept `Path` types, you must import `std/paths`**
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
    ## Base Intrashell object. DON'T USE IT DIRECTLY
    registry: RcuTableRef[string, Module]
    pointerToItself: string
  IntrashellPtr* = ptr IntrashellObj
    ##[
    Pointer to the base Intrashell object. Only use it within modules to
    communicate with other modules or relay operations (`IntrashellOperation`)
    to it. Should be populated once loaded into an Intrashell instance. Example:

    ```nim
    # module.nim -> module.so / module.dll / module.dylib
    import intrashell
    var registry: IntrashellPtr

    proc yourProc(input: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
      if input[0] == INITCOMMAND:
        registry = castStringToIntrashellPtr(input[1])
    ```
    ]##
  Intrashell* = ref IntrashellObj
    ##[
      The main Intrashell object. The one you should use within the main binary
      of your application. Example use:

      ```nim
      var registry: Intrashell = newIntrashell()

      discard registry.processOperations(
        newOperation(
          LOAD,
          "yourModuleName",
          Version(major: 1, minor: 0, patch: 0),
          Path("path/to/your/module")
        ),
        newOperation(
          UPDATE,
          "yourModuleName",
          Version(major: 2, minor: 0, patch: 0),
          Path("path/to/your/module")
        ),
        newOperation(
          ROLLBACK,
          "yourModuleName",
          Version(major: 1, minor: 0, patch: 0),
          Path("path/to/your/module")
        ),
      )

      echo registry.shell("yourModuleName", "subcommand", "parameter[1]")
      ```

      **It needs to be a global variable to work with multiple threads**
    ]##

proc newIntrashell*(): Intrashell =
  ## Creates a new Intrashell object.
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
  ##[
  Calls a module within the registry and passes the parameters. Returns the
  output of said module. Example:

  ```nim
  echo intrashellObject.shell("someModule", "Param 1", "Param 2")
  ```
  ]##
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
    ##[
    The type of operation to execute.

    - LOAD: loads the given modules
    - UNLOAD: unloads the module
    - UPDATE: replaces an existing module if the version of the new one is higher
    - ROLLBACK: replaces an existing module if the version of the new one is lower

    You can use `UPDATE` and `ROLLBACK` for modules that has no previous version
    on the registry, just like `LOAD`.

    You can use `LOAD` to replace a module no matter the version differences.
    ]##
    LOAD,
    UNLOAD,
    UPDATE,
    ROLLBACK
  IntrashellOperation* = ref object
  ## An operation to execute in the registry
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
  ##[
  Creates a new Intrashell registry operation. Supported ones in this form:

  - `UNLOAD`.
  ]##
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
  ##[
  Creates a new Intrashell registry operation. Supported ones in this form:

  - `UNLOAD`
  - `LOAD`
  - `UPDATE`
  - `ROLLBACK`
  ]##
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
  ##[
  Creates a new Intrashell registry operation. Supported ones in this form:

  - `UNLOAD`
  - `LOAD`
  - `UPDATE`
  - `ROLLBACK`
  ]##
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
  ##[
  Process all the the given Intrashell registry operations and returns
  a sequence of strings containing any encountered erros. Example:

  ```nim
  echo intrashellRegistry.processOperations(
    newOperation(
      LOAD,
      "moduleName",
      Version(major: 1, minor: 0, patch: 0),
      Path("path/to/module.so")
    )
  )
  ```

  **Operations are only executed when they are passed to this procedure**
  ]##
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
