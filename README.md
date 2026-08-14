# Intrashell
```mermaid
graph LR
    Host[Host Binary] --> LibA[Shared Library A]
    Host --> LibB[Shared Library B]
    LibA --> LibB
    LibB --> LibA
```
A lightweight library for creating, loading, and orchestrating dynamic and static module state-machines in Nim.

## Table of Contents

- [Key Features](#key-features)
- [Architectural & Team Benefits](#architectural--team-benefits)
- [What it does](#what-it-does)
- [Minimal Example](#minimal-example)
- [Module creation](#module-creation)
  - [Stateless Module Example](#stateless-module-example)
  - [Stateful & Host-Calling Module Example](#stateful--host-calling-module-example)
- [Implementation details](#implementation-details)
- [Notes](#notes)
- [AI Disclaimer](#ai-disclaimer)

## Key Features

- **Zero-Downtime Updates & Rollbacks**: Inject, hot-update, or rollback dependencies at runtime using semantic versioning (`Version`).
- **Unified Interface**: Modules are built as state-machines registered under a single registry with a common interface.
- **Concurrent RCU Registry**: Read and modify the module registry safely across threads and async tasks backed by a lockless RCU hash table.
- **Shared Resource Gateways**: Encapsulate stateful resources (variables, data structures, database connections, buffers, ...) behind isolated modules.
- **Inter-Module Communication**: Enable modules to invoke each other and dispatch commands using host registry pointers.
- **Binary-Safe FFI (`Buffer`)**: Transfer binary data, UTF-8 strings, and raw pointers without null-byte (`\0`) truncation across FFI boundaries.
- **Deterministic Lifecycle Hooks**: Automated `INIT` initialization (passing host pointers) and `SHUTDOWN` cleanup signals on module load/unload.
- **Shared Library Compatibility**: Runs on any operating system or execution environment that supports shared libraries (`.so`, `.dll`, `.dylib`).
- **Language Independent (WIP)**: Built on a flat C-compatible `Buffer` memory layout and standard `cdecl` ABI, allowing modules to be authored in any language supporting standard C FFI bindings (such as C, C++, Rust, or Zig).

## Architectural & Team Benefits

- **State-Machine Design Discipline**: Simplifies overall architecture by offloading business logic into pure, self-contained state-machines in shared libraries (`.so`, `.dll`). Minimal host binaries stay clean, while strict state-machine boundaries eliminate code smells and architectural debt.
- **Self-Contained Binary Packaging**: Simplifies deployment down to standalone shared libraries (`.so`, `.dll`), which can statically link internal dependencies for zero-friction, self-contained distribution.
- **Two-Way IP Confidentiality**: Protects proprietary source code without sharing repository access. Host owners can outsource modules by providing only OS/CPU target specs, while third-party vendors can ship pre-compiled binaries without revealing module source code.
- **Decoupled Team Workflows**: Isolated module boundaries allow separate teams and contractors to develop, test, and deploy features independently without merge conflicts or tight build-time dependencies, enabling smooth, risk-free updates.
- **Lightweight Alternative to Containers & Script Runtimes**: Serves as a native structural alternative to containers and JS/WASM runtimes specifically for module hot-swapping, component isolation, and plugin dispatch—delivering container-like modularity without virtualization daemons or JS engine memory overhead.


## What it does

It provides an `Intrashell` object that handles the loading, managing, and
initializing of modules in the form of compiled shared libraries (`.dll`, `.so`,
`.dylib`) or static procedures. This object provides:

- A `processOperations()` procedure that executes batch module lifecycle operations (`LOAD`, `UNLOAD`, `UPDATE`, `ROLLBACK`) created via `newOperation()`. It returns a sequence of strings (`seq[string]`) that contains any raised errors.
- A `shell()` procedure that interprets a variable number of strings as a command (module identity), subcommand, and its arguments, returning a sequence of strings (`seq[string]`) as output.

### Minimal Example

```nim
# plugin.so
import intrashell
proc yourProc(input: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  return input

dispatchBoilerplate(yourProc)
```

```nim
# host.nim
import intrashell
import std/paths

# 1. Create an Intrashell instance
var myIntrashellInstance = newIntrashell()

# 2. Declare some variables to hold the fields of the `Module` object
let
  cmd = "my_cmd" # Declare a name (identity) for the module
  v1 = Version(major: 1, minor: 0, patch: 0) # Declare a version for the module
  file = Path("plugin.so") # Declare the path to the file

# 3. Load a Shared Library-based module dynamically
discard myIntrashellInstance.processOperations(
  newOperation(LOAD, cmd, v1, file)
)

# 4. Dispatch commands through the unified shell interface
let output = myIntrashellInstance.shell(cmd, "subcommand", "arg")
if output.len > 0:
  echo output[0] # Read the first string of the output

# 5. Declare static modules
let v2 = Version(major: 2, minor: 0, patch: 0) # New version for the module

proc yourProc(input: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  return input
dispatchBoilerplate(yourProc) # This creates a wrapper procedure called `dispatch`

# 6. Perform live hot-updates, rollbacks, or clean unloads
discard myIntrashellInstance.processOperations(
  newOperation(UPDATE, cmd, v2, dispatch),
  newOperation(ROLLBACK, cmd, v1, file),
  newOperation(UNLOAD, cmd)
)
```

## Module creation

Modules expose an entry point procedure matching `UserSuppliedDispatch`
(`proc(parameters: seq[string]): seq[string] {.raises: [WrongParameters,
CommandFailed].}`) and use the `dispatchBoilerplate` template to automatically
handle memory allocation, FFI signature export, and zero-copy data serialization
via `Buffer`.

### Stateless Module Example

```nim
import intrashell

proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  # Simply returns the input
  return parameters

# Generate FFI bindings and dispatch glue
dispatchBoilerplate(entryPoint) # creates a wrapper procedure called `dispatch`
```

### Stateful & Host-Calling Module Example

When a module is loaded or unloaded, Intrashell automatically executes
`INIT` and `SHUTDOWN` commands. During `INIT`, parameter 1 contains a
pointer to the host `Intrashell` instance, which can be deserialized using
`castStringToIntrashellPtr`:

```nim
import intrashell
import std/strutils

var
  ushell: IntrashellPtr
  state: int

proc entryPoint(parameters: seq[string]): seq[string] {.raises: [WrongParameters, CommandFailed].} =
  result = @[]
  let command = parameters[0]
  let arguments = 1..high(parameters)

  case command
  of "INIT":
    try:
      # Retrieve pointer to host Intrashell instance
      ushell = castStringToIntrashellPtr(parameters[1])
    except Exception:
      discard
    state = 0
  of "SHUTDOWN":
    ushell = nil
    state = 0
  of "set":
    try:
      state = parameters[1].parseInt()
    except Exception:
      discard
  of "get":
    result = @[$state]
  of "call":
    # Safely invoke another module registered in the host Intrashell instance
    if ushell != nil:
      result = ushell.shell(parameters[arguments])

dispatchBoilerplate(entryPoint)
```

## Implementation details

Intrashell relies on two main components to achieve thread safety and low FFI overhead:

- **RCU Table (`RcuTableRef`)**: A lockless-reader hash table. Readers acquire a reference to the active table with zero locking overhead, relying on Nim's ARC/ORC/AtomicARC reference counting to prevent premature deallocation. Writers acquire a single lock, copy the inactive table, swap the atomic index (`activeSlot`), and allow old references to be freed when readers finish.
- **Flat Buffer (`Buffer` / `Darray[char]`)**: A flat, contiguous memory structure used to pack multiple strings into a single chunk of memory for FFI. It avoids standard C strings (`cstring`) to prevent truncation on null bytes (`\0`), making it safe for binary payloads, pointers, and UTF-8 data across language boundaries.

## Notes

- Requires Nim **2.0.0** or newer.
- Compile Intrashell and modules with memory management set to `--mm:arc`, `--mm:orc`, or `--mm:atomicArc`.
- Compile dynamic modules (shared libraries) with `-d:useMalloc --app:lib`

## AI Disclaimer

AI assistance was used exclusively for drafting, refining, and formatting
documentation files (`README.md` and `CONTRIBUTING.md`). The core Intrashell
library, memory management, FFI bindings, and test suites were designed and
written entirely by human developers.
