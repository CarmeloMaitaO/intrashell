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
  ExitCodes*  {.size: S16.} = enum
    ##[
      The exit code of any dispatch call. It can either be `OK`, which means no
      errors, or any of the other specific error types provided. This
      enumeration exists to make binding to other languages easier, as they
      won't share the same exception handling mechanism, and therefore should
      handle this matter as they see fit based on the returned value.
    ]##
    OK                = 0,
    UnknownCommand    = 1,
    UnknownSubCommand = 2,
    WrongParameters   = 3,
    CommandFailed     = 4,
    IncompatibleState = 5, # Only used for liveness hook
    BadShape          = 6
  BufferDataTypes* {.size: S32.} = enum
    ##[
      The data type of the `BufferBuilderDataElement` and the `BufferElement`.
      It is meant to tell what kind of data is contained within it so it can be
      properly extracted and parsed.
    ]##
    BOOL     =  0,
    UINT8    =  1,
    UINT16   =  2,
    UINT32   =  3,
    UINT64   =  4,
    INT8     =  5,
    INT16    =  6,
    INT32    =  7,
    INT64    =  8,
    FLOAT32  =  9,
    FLOAT64  = 10,
    STRING   = 19,
    BLOB     = 20,
    OBJECT   = 21

# =============================================================================
# BUFFER BUILDER
# =============================================================================

type
  BufferBuilderMetadata* = tuple
    ##[
      This is the first part of the `BufferBuilder` object, and contains:

      1. exitCode: a 16bit enum that contains the exit code of the dispatch
         call. It can either be `OK` or any of the possible error values.
         bindings should use their own language exception mechanism to raise
         errors based on this value.
      2. version: the version of the buffer/"ISBF" specification being used.
      3. capacity: number of `BufferBuilderDataElement` that can be currently
         stored.
      4. length: number of `BufferBuilderDataElement` currently stored.
      5. size: sum of all the sizes reported by each `BufferBuilderDataElement`.
         Anything beyond what can be indexed by an 32 bit unsigned integer will
         force this field to wrap around, so it will be silently ignored.
    ]##
    exitCode: ExitCodes
    version: uint16
    capacity: uint32
    length: uint32
    size: uint32
  BufferBuilderDataElement* = tuple
    ##[
      This structure doubles as a container for scalar types and a fat pointer
      for composite types.
    ]##
    kind: BufferDataTypes
    length: uint32  ## If type is equal to STRING/BLOB/OBJECT, then it's its length.
    payloadLow: uint32
    payloadHigh: uint32 ## Can be either the plain value, or a pointer to the data.
  BufferBuilderData* = ptr UncheckedArray[BufferBuilderDataElement]
    ## Represents an array of `BufferBuilderDataElement` objects.
 
type BufferBuilder* = pointer
  ##[
    Simulates a `seq[objectVariant]` in an opaque pointer, where each contained
    object is either an scalar type or a fat pointer to a flat structure.

    Each programming language have it's own way of storing the metadata of its
    memory allocations, along with different ways of managing it through traced
    or untraced references (GC or manual with different allocators), so in order
    to create a composite flat object that can be passed across memory
    boundaries without causing a segmentation fault, it is necessary to first
    collect the metadata of the values before actually building this object.

    Which lead to the creation of this structure (`BufferBuilder`), which is
    composed by a `BufferBuilderMetadata` and a `BufferBuilderData` structures.
    This structure will store all the scalar data, and the metadata of the flat
    structures so then it can be processed into a `Buffer` object. It's
    memory layout is the following:

    |     **Field**     | BufferBuilderMetadata |      BufferBuilderData     |
    | ----------------- | --------------------- |--------------------------- |
    | **Size in bytes** |          16           |         16 * length        |

    **This structure/object is meant to be used for low-level bindings to
    create higher-level ones**, therefore, it doesn't have safety checks and
    only provides procedures to create it, populate it and deallocate it;
    modification beyond appending won't be supported.
  ]##

const
  BufferBuilderMetadataSize*: uint32 = cast[uint32](sizeOf(BufferBuilderMetadata))
  BufferBuilderDataElementSize*: uint32 = cast[uint32](sizeOf(BufferBuilderDataElement))

proc getBufferBuilderSize(cap: uint32): uint32 =
  BufferBuilderMetadataSize + BufferBuilderDataElementSize * cap

proc reallocBufferBuilder*(bb: BufferBuilder, step: uint32): BufferBuilder {.raises: [].} =
  var
    aux: ptr BufferBuilderMetadata = cast[ptr BufferBuilderMetadata](bb)
    tcap: uint32 = aux.capacity + step
  result = bb.allocator(REALLOC, getBufferBuilderSize(tcap))

proc allocBufferBuilder*(cap: uint32 = 19): BufferBuilder {.raises: [].} =
  ##[
    Allocates a new `BufferBuilder` of `cap` capacity. To achieve better
    performance and RAM usage efficiency, fine-tune the `cap` value so it
    matches the size of your biggest request, otherwise:

    - If it too small: it will reallocate the data over and over again to fit,
      which requires more CPU cycles and doubles the RAM consumption at the
      time.
    - If it is too big: it will consume more RAM than necessary per request,
      bloating your system.
  ]##
  s

proc deallocBufferBuilder*(bb: var BufferBuilder) {.raises: [].} =
  discard

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
