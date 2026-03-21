# Unishell

A framework for dynamically loaded, concurrent state-machines, that expose a single interface for interaction and:
- Operate over the same resources (variables, data structures, database connections, ...).
- Inject dependencies from shared libraries at runtime.
- Are deployed in:
  - Servers.
  - Desktop Applications.
  - Unikernels (that have a `dlopen()` system call implemented).

## What it does

It provides a new `Unishell` object that handles the loading, managing, and initializing of modules in the form of shared libraries (`.dll` or `.so`). This object provides:

- A `updateModules()` procedure that automatically loads the specified module from the inputted file.
- A `shell()` procedure that interprets a variable number of strings as a command (module), subcommand and its arguments, and returns a sequence of strings as output.

### Minimal Example

```nim
import unishell

# 1. Create an Unishell object

var u = newUnishell()

# 2. Load a Shared Library-based module
# Assuming "plugin.so" exports ``
u.updateModules("plugin.so")

# 3. Dispatch commands
let output = u.shell("module", "subcommand", "arg")
echo output[0] # Read the first string of the output

# 4. Unload all modules (shutdown)
discard
```

### Why

A lot of projects tend to be a composition of multiple state-machines chained together, but as they all are mutually dependent on the current API of each module, simple changes and small mistakes can break the entire project, refactoring them becomes more expensive as the codebase evolves, and adding concurrency and parallelism mixed up with access to the same resources (variables, data structures, buffers, etc) might force the developer to spend more time debugging than writing business logic. There are also codebases that require:

- Dynamic injection of dependencies and minimum downtime.
- Certain degree of confidentiality, and need to provide the programmers only the necessary information for them to work.
- Strict separation of concern.
- Fast and frequent iterations that might limit the time available for debugging, and may involve heavy use of AI.

Taking this into consideration, separating the project into smaller, external modules is a logical conclusion, but then the binding and management of said modules becomes a problem on its own; but there is a type of software that has this very same architecture without these disadvantages: Shell scripts. Unishell, inspired by shell scripts, tries to solve these problems by providing a single `shell()` interface to all modules.

Unishell simplifies writing concurrent/threaded code by allowing you to encapsulate resources (like database connections or shared buffers) behind specific modules along with their necessary guards/locks. Other modules can then access these resources safely by invoking the encapsulated procedures through the `shell()` interface, abstracting away complex lock management and reducing race conditions.

Unishell also provides automatic:

- Dependency (module) injection support at runtime by use of shared libraries or VTables
- Module versioning and safe updates
- Deterministic cleanup and resource management

### Is this a framework? 

No, Unishell is intended to be a thin wrapper over common module managing operations. This way, it can be used for any sort of applications without restrictions, and be easily replaced once the architecture of the codebase becomes stable enough for refactoring; but the structure it gives and the specific APIs it imposes makes it almost a framework

### Why/when to move from Unishell

Unishell is intended to be some form of trampoline for codebases to jump quickly into writing business logic and get a stable architecture soon without accumulating technical debt, but it is not intended to be a permanent solution given that:

- Even though the `shell()` API is really convenient and flexible, it is not the most optimized version of what your code could be, given that it suffers the same bottlenecks as shell scripts: inputting strings require additional sanitization and parsing of the received data, which quickly increases if you also pipe operations between modules
- Forcing the use, and limiting the modules to a handful of pre-stablished procedures might be too restrictive for your use case, even more if you want to create objects and not buffers of data from your modules
- The underlying logic to glue all together might be too bloated for your needs

Still, if your use case *is* what Unishell solves, or at least is very similar, you might want to either stick to Unishell or fork the project to accommodate it to your specific needs; Unishell was programmed with this in mind, and it is encouraged.

## Module creation

Modules can be implemented as **VTables** (compile-time) or **Shared Libraries** (runtime-loaded). Both require the same attributes:

### VTable-based Example (Compile-time)
```nim
# VTable modules are constructed using `newModule`.
# All attributes are required.

let myModule = newModule(
  "my_cmd",
  (1, 0, 0),
  proc(u: UnishellInstance) = echo "Initializing...",
  proc(m: ModuleInstance, p: seq[string]): seq[string] = @["Result"],
  proc() = echo "Shutting down..."
)
```

### Shared Library-based Example (Runtime)
```nim
# Shared libraries must export the `moduleFactory` symbol.
# Ensure your Nim module compiles with `--app:lib`.

proc init(u: UnishellInstance) = echo "Init"
proc dispatch(m: ModuleInstance, p: seq[string]): seq[string] = @["Plugin output"]
proc shutdown() = echo "Shutdown"

proc moduleFactory*(): ModuleInstance {.exportc: "moduleFactory", dynlib.} =
  newModule("my_plugin", (1, 0, 0), init, dispatch, shutdown)
```

## Implementation details

Unishell uses an atomic unsigned integer to hold both a counter of read
operations and two flags for the current state of the object
