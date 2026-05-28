##[
  This module provides a `Module` base class, with it's associated subclasses
  that represent compile-time or runtime loaded modules. This classes have
  a `dispatch` interface that gets invoked by a `shell` procedure, which
  receive a sequence of strings as input and returns a sequence of strings
  as output.

  The supported types/subclasses of `Module` are:

  - Static (`StaticModule`): provided at compile-time either by the main binary or a shared
    library.
  - Dynamic (`DynamicModule`): provided at runtime by dynamic/shared libraries. These don't
    require to be linked at compile-time, as they share the same interface
    and so they can be safely searched and loaded on-demand.
  - WASM (`WasmModule` WIP): it will be released on V2.0.0 and it will use Wasm3.

  Example of use:

  ```nim
  # Declare a `UserSuppliedDispatch` called `someProc`
  proc someProc(args: seq[string]): seq[string] =
    # Returns the inputs for illustrative purposes
    result = args

  
  var x: Module = StaticModule(
    identity: "someModule",
    version: Version(major: 1, minor: 0, patch: 0),
    importedDispatch: someProc
  )
  echo x.shell("Some", "strings")
  ```
]##
import unishell/buffers
import std/[
  paths,
  strutils
]

type
  UserSuppliedDispatch* = proc (parameters: seq[string]): seq[string]
  Version* = object
    ## Represents a Semantic Version
    major*: int
    minor*: int
    patch*: int
  Module* = ref object of RootObj
    ##[
    Represents a module, holding its identity and version.
    ]##
    identity*: string
    ##[
      Holds the identity (string that will be used as key in the RCU Table)
      of the module.
    ]##
    version*: Version
    ## The SemVer of the module.

method dispatch*(module: Module, input: Buffer): Buffer {.base.} =
  ## Base dispatch method to be overridden by subclasses
  quit "Dispatch called on base Module!"

# =============================================================================
# COMMON TYPES, PROCEDURES AND TEMPLATES FOR COMPILED MODULES
# =============================================================================

type
  HostsAllocator* = proc(buffer: ptr Buffer, len: int, cap: int) {.cdecl.}
  ##[
    Signature of the procedure used to allocate the necessary memory on the host
    for the output of a dispatch operation on the
  ]##
  ImportedDispatch* = proc(input: ptr Buffer, output: ptr Buffer, hostAllocator: HostsAllocator) {.cdecl.}
  ## Dispatch procedure of a module. It is the one that gets imported by the library
proc hostsAllocator(output: ptr Buffer, len: int, cap: int) {.cdecl.} =
  ## Wraps the library-provided pre-allocation logic
  preAllocateBuffer(output, len, cap)

template dispatchBoilerplate*(userSuppliedProc: UserSuppliedDispatch) =
  ## This template is meant to be used by the modules (`.DLL`, `.SO`, `.WASM`)
  proc dispatch*(inputBuffer: ptr Buffer, outputBuffer: ptr Buffer, allocator: HostsAllocator) {.exportc, dynlib, cdecl.} =
    let
      input: seq[string] = inputBuffer[].toSeq()
      output: seq[string] = userSuppliedProc(input)
      outputLen: int = output.len()
    var outputCap: int = 0
    for element in output:
      outputCap += element.len()
    allocator(outputBuffer, outputLen, outputCap)
    # Auxiliary variables for the copy of data
    var
      dataAddress: uint = 0
      elementOffset: uint = 0
    if outputLen > 0:
      dataAddress = cast[uint](outputBuffer[].data)
      for index, element in pairs(output):
        outputBuffer.sizes[index] = element.len
        if element.len > 0:
          outputBuffer.offsets[index] = elementOffset
          copyMem(cast[pointer](dataAddress + elementOffset), addr element[0], element.len)
        elementOffset += (element.len).uint

# =============================================================================
# STATIC MODULES
# =============================================================================

type
  StaticModule = ref object of Module
    importedDispatch: UserSuppliedDispatch

method dispatch(
  module: StaticModule,
  input: Buffer
): Buffer =
  result = createBuffer(module.importedDispatch(input.toSeq()))

# =============================================================================
# DYNAMIC/SHARED LIBRARY BASED MODULES
# =============================================================================

import std/dynlib

type
  DynamicModulePayloadObj = object
    lib: LibHandle
    ##[
      Handle for the dynamic library.
    ]##
    importedDispatch: ImportedDispatch
  DynamicModulePayload = ref DynamicModulePayloadObj
  DynamicModule = ref object of Module
    path: Path
    ##[
      Absolute path to the dynamic library. It is used to identify the file
      that corresponds to the currently loaded module.
    ]##
    payload: DynamicModulePayload 

method dispatch(
  module: DynamicModule,
  input: Buffer
): Buffer =
  var output: Buffer
  if module.payload.importedDispatch != nil:
    module.payload.importedDispatch(
      addr input,
      addr output,
      hostsAllocator
    )
    result = output
  else:
    result = createBuffer(@[])

proc `=destroy`(payload: var DynamicModulePayloadObj) =
  if payload.importedDispatch != nil:
    payload.importedDispatch = nil
  if payload.lib != nil:
    unloadLib(payload.lib)

# =============================================================================
# COMMON PROCEDURES FOR ALL MODULE TYPES
# =============================================================================

proc shell*(module: Module, parameters: varargs[string, `$`]): seq[string] {.cdecl.} =
  ## Procedure used to interact with the modules.
  result = toSeq(module.dispatch(createBuffer(@parameters)))
  
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

