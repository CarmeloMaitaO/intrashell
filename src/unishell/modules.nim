import std/[
  dynlib,
  paths,
  strutils
]

type
  SetCallback* = proc(val: cstring) {.cdecl.}
  GetCallback* = proc(i: cint): cstring {.cdecl.}
  ModuleDispatch* = proc(argc: cint, gc: GetCallback, sc: SetCallback) {.cdecl.}
  UserSuppliedDispatch* = proc (parameters: seq[string]): seq[string]
  Version* = object
    major: int
    minor: int
    patch: int
  ModuleKind* = enum
    static,
    dynamic
  Module* = ref object
    ##[
    Represents a module, holding its identity, version, status and interface.
    ]##
    dispatch: ModuleDispatch
    identity: string
    ##[
      Holds the identity (string that will be used as key in the RCU Table)
      of the module.
    ]##
    version: Version
    ## The SemVer of the module.
    case kind: ModuleKind
    of static:
      discard
    of dynamic:
      lib: LibHandle
      ##[
        Handle for the dynamic library. If its value is `nil`, it is then assumed
        that the module is a VTable coming from either the main binary or a
        static library.
      ]##
      path: Path
      ##[
        Absolute path to the dynamic library. It is used to identity the file
        that corresponds to the currently loaded module. If it's value is Nil,
        then it is assumed that is a VTable coming from either the main binary or
        a static library.
      ]##

proc shell*(m: Module, parameters: varargs[string, `$`]): seq[string] =
  result = @[]
  proc setCallback(value: cstring) {.cdecl.} =
    result.add($value)
  var
    castedParameters: seq[cstring] = @[]
    castedParametersLen: cint
  for parameter in parameters:
    castedParameters.add(parameter.cstring)
  castedParametersLen = cint(castedParameters.len())
  proc getCallback(i: cint): cstring {.cdecl.} =
    return castedParameters[i]
  if m.dispatch != nil:
    try:
      m.dispatch(
        castedParametersLen,
        getCallback,
        setCallback
      )
    except:
      let e = getCurrentException()
      raise NewException(DispatchError, "")
  else:
    discard
  
proc `>`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` is a newer version than `b`.
  if a.version.major != b.version.major:
    return a.version.major > b.version.major
  if a.version.minor != b.version.minor:
    return a.version.minor > b.version.minor
  return a.version.patch > b.version.patch
  
proc `<`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` is an older version than `b`.
  if a.version.major != b.version.major:
    return a.version.major < b.version.major
  if a.version.minor != b.version.minor:
    return a.version.minor < b.version.minor
  return a.version.patch < b.version.patch
  
proc `==`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` and `b` versions are equal.
  if a.version.major != b.version.major:
    return false
  if a.version.minor != b.version.minor:
    return false
  if a.version.patch != b.version.patch:
    return false
  return true

proc `!=`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` and `b` have different versions.
  if a.version.major != b.version.major:
    return true
  if a.version.minor != b.version.minor:
    return true
  if a.version.patch != b.version.patch:
    return true
  return false

proc `>=`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` is an equal or newer version than `b`.
  if (a > b) or (a == b):
    return true
  return false

proc `<=`(a, b: Module): bool =
  ## Compares two modules based on their semantic version. Returns true if `a` is an equal or older version than `b`.
  if (a < b) or (a == b):
    return true
  return false

proc castPointerToString*(p: pointer): string =
  ## Used to send through the `shell` procedure a pointer to some data structure
  return $(cast[int](p))

proc castStringToPointer*(p: string): pointer =
  ## Used to receive through the `dispatch` procedure a pointer to some data structure
  return cast[pointer](p.parseUInt)

template dispatchBoilerplate*(userSuppliedProc: UserSuppliedDispatch) =
  proc dispatch*(argc: cint, gc: GetCallback, sc: SetCallback) {.exportc, dynlib, cdecl.} =
    var
      inputs: seq[string] = @[]
      outputs: seq[string] = @[]
    for i in 0 ..< argc:
      inputs.add($gc(i))
    outputs = userSuppliedProc(inputs)
    for response in outputs:
      sc(response.cstring)
