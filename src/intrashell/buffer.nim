##[
  This module provides both a `BufferBuilder` and a `Buffer` objects that
  emulates the different parameters of a procedure call in a single flat memory
  structure, so they can be passed across memory boundaries between the main
  executable and it's shared/dynamic/runtime-loaded libraries; without worrying
  about matching the memory allocator, garbage collector or language.

  It uses a two-step build process, where the data is first borrowed by the
  `BufferBuilder` and then processed into a single chunk of memory that will be
  the `Buffer` object. For this, the `BufferBuilder` behaves as a collection of
  fat pointers under a single chunk of memory, which will be then read by a
  `BuildBuffer` procedure that will allocate the sum of the given sizes and
  perform a copy of all the data pointed at by the `BufferBuilder`.

  **THESE OBJECTS ARE MEANT TO BE:**
  - OPAQUE POINTERS
  - MODIFIED ONLY BY THEIR METHODS
  - MANAGED BY THE ALLOCATOR PROVIDED IN THIS LIBRARY
  - USED IN A SYNCHRONOUS MANNER
  - COMPATIBLE WITH C99
  **WITH THE GOAL OF BEING:**
  - LANGUAGE INDEPENDENT (IMPORTABLE BY ANY LANGUAGE WITH SUPPORT FOR C FFI)
  - PLATFORM INDEPENDENT (ONLY REQUIRE A CPU THAT SUPPORTS A 32 BIT INTEGER
    SIZE)

  ```nim
  # EXAMPLE:
  ```
]##

# =============================================================================
# EXTERNAL ALLOCATOR
# =============================================================================
#[
 This is the allocator procedure; its function is to make Intrashell's allocator
 available to both the modules and the host.
]#

type
  AllocatorAction* = enum
    ##[
      Enumeration for the possible actions that the allocator can perform:

      0. `ALLOC`: allocates a new block of memory.
      1. `DEALLOC`: deallocates a block of memory.
      2. `REALLOC`: reallocates the memory from one block to another.
      3. `ZEROMEM`: zeroes a given block of memory.
      4. `COPYMEM`: copies one block of memory into another.
      5. `ALLOC0`: allocates a new block of memory and initializes it to `0`.
      6. `REALLOC0`: reallocates the memory from one block to another after
         initializing the new block to `0`.
    ]##
    ALLOC    = 0,
    DEALLOC  = 1,
    REALLOC  = 2,
    ZEROMEM  = 3,
    COPYMEM  = 4,
    ALLOC0   = 5,
    REALLOC0 = 6
  allocator* = proc(
    dest: pointer,
    action: AllocatorAction,
    size: uint32 = 0,
    src: pointer = nil
  ): pointer {.cdecl, raises: [].}
    ##[
      The signature for the allocator. Rather than a tuple containing pointers
      to the individual allocator functions, it is a single procedure for the
      sake of simplifying the binding process. It also helps with performance,
      as it is a single pointer that must be followed for the procedure instead
      of two.
    ]##

proc allocator*(
  dest: pointer,
  action: AllocatorAction,
  size: uint32 = 0,
  src: pointer = nil
): pointer {.cdecl, raises: [].} =
  ##[
    The allocator procedure of Intrashell. It should be used for managing the
    lifecycle of any created `Buffer` types, as this allows modules and hosts
    alike to manage them without worrying about where are the `Buffer` types
    allocated; they are always allocated in the address space of Intrashell.
    This also allows both hosts and modules to benefit from the performance
    improvements that Nim provides with it's internal allocator, as the memory
    is not returned inmediately to the host OS, but rather kept by the process
    until it either reuses it or deems it unnecesary and performs the actual
    system call to free it.

    The supported actions, their behaviour and their accepted parameters are:

    0. ALLOC(size): allocates a new memory block of `size` bytes.
    1. DEALLOC(dest): deallocates a given memory block.
    2. REALLOC(dest, size): creates a new memory block of the given `size` and
       copies the previous block into it. Deallocates the previous block after.
    3. ZEROMEM(dest, size): zeroes a block of memory
    4. COPYMEM(dest, size, src): copies `size` bytes from a memory block into
       another.
    5. ALLOC0(size): same as `ALLOC` but zeroes the memory block.
    6. REALLOC0(dest, size): same as `REALLOC` but zeroes any memory that is not
       overwritten.
  ]##
  result = dest
  case action
  of ALLOC, ALLOC0:
    if (action == ALLOC):
      result = alloc(size)
    else:
      result = alloc0(size)
  of DEALLOC:
    dealloc(dest)
    result = nil
  of REALLOC, REALLOC0:
    if (action == REALLOC):
      result = realloc(dest, size)
    else:
      result = realloc0(dest, size)
  of ZEROMEM:
    zeroMem(dest, size)
    result = dest
  of COPYMEM:
    copyMem(dest, src, size)
    result = dest

# =============================================================================
# CONSTANTS
# =============================================================================

const
  S8*: Natural = sizeOf(uint8)     ## Size of a single uint8. It is 1 byte.
  S16*: Natural = sizeOf(uint16)   ## Size of a single uint16. It is 2 bytes.
  S32*: Natural = sizeOf(uint32)   ## Size of a single uint32. It is 4 bytes.
  SPTR*: Natural = sizeOf(pointer) ## Size of a pointer. Platform dependent.

type
  ExitCodes*  {.size: S8.} = enum
    ##[
      The exit code of any dispatch call. It can either be `OK`, which means no
      errors, or any of the other specific error types provided. This
      enumeration exists to make binding to other languages easier, as they
      won't share the same exception handling mechanism, and therefore should
      handle this matter as they see fit based on the returned value.
    ]##
    OK                = 0,
    UnknownCommand    = 1,
    WrongParameters   = 2,
    CommandFailed     = 3

# =============================================================================
# BUFFER OBJECT
# =============================================================================

type Buffer* = pointer
  ##[
    Simulates a `seq[string]` in a flat structure. It's structured like this:

    |    Length    |      Metadata    |       Data      |
    | ------------ | ---------------- | --------------- |
    |    UINTSIZE     |  UPSIZE * Length |   Sum of sizes  |

    - UINTSIZE: size in bytes of a single unsigned integer
    - UPSIZE: size in bytes of a UINTSIZE pair

    This layout is supposed to be a fully flat version of the BufferBuilder,
    with all the strings/BLOBs copied into it, with each section containing:

    - Length: indicates the number of contained strings.
    - Metadata: Pair of offset and size of each string.
    - Data: The contained strings.
  ]##
