##[
  This module provides a `Buffer` object that packs a variable number of strings
  of different sizes inside a single, contiguous chunk of memory; simulating
  a sequence of strings (`seq[string]`), with the associated procedures and
  iterators, while being easy to pass between the main executable and it's
  shared/dynamic/runtime-loaded libraries.

  It uses Nim's native strings because they behave like buffers of their own,
  and are capable of holding binary data, such as files and pointers, within
  them; which enables the `Buffer` object to be a buffer of buffers. This also
  means that the type `cstring` is avoided on purpose to prevent truncation
  on null bytes (`\0`), which are frequent in binary data.

  *THIS OBJECT IS INTENDED TO BE READ-ONLY*, if you need to modify it;
  convert it to a `seq[string]` and use it to create a new object.

  *THIS OBJECT IS INTENDED TO BE USED IN A SINGLE-THREADED ENVIRONMENT*, if
  you are working in a multi-threaded environment, make sure that the logic
  that handles the object is single-threaded or is wrapped inside a lock/mutex.

  *THIS OBJECT IS MEANT TO BE LANGUAGE INDEPENDENT*. That way, No matter the
  language the modules or the main binary are written in, they will be able to
  communicate without problems, as long as the string are encoded in UTF-8.

  Operators, iterators and procedures are provided to give the user the
  necessary calls to be able to handle the `Buffer` and `DataView` as
  if they were a simple `seq[string]`. The following procedures enable the use
  of:

  ```nim
  var x: BufferView = newBufferView(
    newBuffer(@["These", "are", "some", "strings"])
  )

  # Use of `in` and `$` operators
  for i in x:
    echo $i

  # Use of the `[]` operator and comparison to `string` types
  if x[0] == "These":
    echo $x[0], $x[3], $x[1], $x[3] # "These strings are strings"

  # Conversion to `seq[string]`
  var y: seq[string] = toSeq(x)
  for i in y:
    echo i
  ```
]##

# =============================================================================
# EXTERNAL ALLOCATOR
# =============================================================================
#[
 This is the allocator procedure; its function is to make the host's allocator
 available to modules, so the memory used by the module is allocated and freed
 in the host.
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
      7. `COPYMEM0`: copies one block of memory into another after initializing
         the last one to `0`.
                     
    ]##
    ALLOC    = 0,
    DEALLOC  = 1,
    REALLOC  = 2,
    ZEROMEM  = 3,
    COPYMEM  = 4,
    ALLOC0   = 5,
    REALLOC0 = 6,
    COPYMEM0 = 7
  allocator* = proc(
    fromAddress: pointer,
    fromSize: Natural,
    action: AllocatorAction,
    toAddress: pointer,
    toSize: Natural
  ): pointer {.cdecl, raises: [].}
    ##[
      The signature for the allocator. Rather than a tuple containing pointers
      to the individual allocator functions, it is a single procedure for the
      sake of simplifying the binding process. It also helps with performance,
      as it is a single pointer that must be followed for the procedure instead
      of two.
    ]##

proc allocator*(
  fromAddress: pointer,
  fromSize: Natural,
  action: AllocatorAction,
  toAddress: pointer,
  toSize: Natural
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

    0. ALLOC (`fromAddress`, `fromSize`): allocates a block of the `fromSize` size. If:
       - `fromAddress` **is** `nil`: simply allocates the block
       - `fromAddress` **is not** `nil`: deallocates the address and returns the
          new block
    1. DEALLOC (`fromAddress`): deallocates the given block (if not `nil`).
    2. REALLOC (`fromAddress`, `fromSize`, `toSize`): moves one block of memory
       into a new one. if...
       - `fromAddress` is `nil`: simply allocates based on `toSize`
       - `fromSize` is less or equal to `0`: deallocates and the creates a new
         block without copying the data from the previous one.
       - `toSize` is less or equal to `0`: simply deallocates the block.
    3. ZEROMEM (`fromAddress`, `fromSize`): zeroes the given memory block.
    4. COPYMEM (all): copies one block of memory into another. if...:
       - `fromAddress` is 
    5. `ALLOC0` (same as `ALLOC`): same as `ALLOC`, but initializes the block to
       `0`.
    6. `REALLOC0` (same as `REALLOC`): same as `REALLOC`, but initializes the
       new memory block to `0` before performing the copy of the data.
    7. `COPYMEM0` (same as `COPYMEM`): same as `COPYMEM`, but zeroes the target
       memory block before performing the copy.
  ]##
  result = fromAddress
  case action
  of ALLOC:
    if fromAddress == nil:
      if fromSize > 0:
        result = alloc(fromSize)
    else:
      dealloc(fromAddress)
      result = alloc(fromSize)
  of DEALLOC:
    if fromAddress != nil:
      dealloc(fromAddress)
      result = nil
  of REALLOC: # Uses fromAddress, fromSize, toSize
    if fromAddress == nil: # Will allocate
      if toSize > 0:
        result = alloc(toSize)
    elif fromSize <= 0:    # Will deallocate and then allocate
      dealloc(fromAddress)
      if toSize > 0:
        result = alloc(toSize)
      else:
        result = nil
    elif toSize <= 0:      # Will deallocate
      dealloc(fromAddress)
      result = nil
    else:                  # Will reallocate
      result = alloc(toSize)
      if toSize > fromSize:
        copyMem(result, fromAddress, fromSize)
      else:
        copyMem(result, fromAddress, toSize)
      dealloc(fromAddress)
  of ZEROMEM:
    if (fromAddress != nil) and (fromSize > 0):
      zeroMem(fromAddress, fromSize)
    result = fromAddress
  of COPYMEM: # Uses fromAddress, fromSize, toAddress, toSize
    if (fromAddress != nil) and (toAddress != nil):
      if toSize >= fromSize:
        copyMem(toAddress, fromAddress, fromSize)
      else:
        copyMem(toAddress, fromAddress, toSize)
    else:
      result = nil
  of ALLOC0:
    discard
  of REALLOC0:
    discard
  of COPYMEM0:
    discard

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
    OK                = 0,
    UnknownCommand    = 1,
    UnknownSubCommand = 2,
    WrongParameters   = 3,
    CommandFailed     = 4,
    IncompatibleState = 5, # Only used for liveness hook
    BadShape          = 6
  BufferDataTypes* {.size: S32.} = enum
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
    FLOAT64  = 10
    STRING   = 19,
    BLOB     = 20,
    OBJECT   = 21

# =============================================================================
# BUFFER BUILDER
# =============================================================================

type
  BufferBuilderMetadata* = tuple
    exitCode: ExitCodes
    capacity: uint32
    length: uint32
    size: uint32
  BufferBuilderDataElement* = tuple
    type: BufferDataTypes
    length: uint32  ## If type is equal to STRING/BLOB/OBJECT, then it's its length.
    payloadLow: uint32
    payloadHigh: uint32 ## Can be either the plain value, or a pointer to the data.
  BufferBuilderData* = ptr UncheckedArray[BufferBuilderDataElement]
 
type BufferBuilder* = pointer
  ##[
    Simulates a `seq[(pointer, int)]` in order to simplify the process of
    writing bindings to other languages.

    C, other languages, and different `malloc()` implementations have
    different ways of storing the metadata of a memory allocation, so in order
    to be able to read the data from Nim in a completely agnostic way, a
    custom object is provided in the form of a flat memory structure, with the
    following layout:

    |   Capacity  |    Length    |   Size   |        Data        |
    | ----------- | ------------ |--------- | ------------------ |
    |   UINTSIZE  |    UINTSIZE  | UINTSIZE |  UPSIZE * Length   |

    - UINTSIZE: size in bytes of a single unsigned integer
    - UPSIZE: size in bytes of a UINTSIZE pair

    This layout allows us to store a collection of custom fat pointers to the
    actual data, which avoids unnecessary copies and null byte truncations
    while providing enough information to build a new buffer object from it.
    Said information would be:

    - Capacity: how many fat pointers it can store
    - Length: how many fat pointers are stored
    - Size: the sum of all the sizes declared by each fat pointer
    - Data: the collection of fat pointers

    **This structure/object is meant to be used for low-level bindings to
    create higher-level ones**, therefore, it doesn't have safety checks and
    only provides procedures to create it, populate it and deallocate it;
    modification beyond appending is/will not be supported.
  ]##

proc len*(bb: BufferBuilder): int {.raises: [].} =
  result = bb.getArray()[1]

proc setLen(bb: var BufferBuilder, len: Natural) {.raises: [].} =
  bb.getArray()[1] = len

proc cap(bb: BufferBuilder): int {.raises: []} =
  result = bb.getArray()[0]

proc setCap(bb: var BufferBuilder, cap: Natural) {.raises: [].} =
  bb.getArray()[0] = cap

proc size(bb: BufferBuilder): int {.raises: []} =
  result = bb.getArray()[2]

proc setSize(bb: var BufferBuilder, size: Natural) {.raises: [].} =
  bb.getArray()[2] = size

proc getBufferBuilderSize(length: int): int {.raises: [].} =
  result = UTSIZE + UPSIZE * length

proc getBufferBuilderSize(bb: BufferBuilder, index: int): int {.raises: [].} =
  result = UTSIZE + UPSIZE * index

proc getIndexArray(bb: BufferBuilder, index: int): ptr UncheckedArray[int] {.raises: [].} =
  result = bb.getArray(bb.getBufferBuilderSize(index))

proc newBufferBuilder*(cap: int = 0): BufferBuilder {.raises: [].} =
  result = result.allocator(ALLOC, getBufferBuilderSize(cap))
  result.setCap(cap)
  result.setLen(0)
  result.setSize(0)

proc set*(bb: var BufferBuilder, index: int, address: pointer = nil, size: int = 0) {.raises: [].} =
  var aux: ptr UncheckedArray[int]
  aux = bb.getIndexArray(index)
  aux[0] = cast[int](address)
  aux[1] = size
  # Update metadata
  bb.setLen(bb.len()+1)
  bb.setSize(bb.size()+size)

proc getAddress*(bb: BufferBuilder, index: int): pointer {.raises: [].} =
  result = cast[pointer](bb.getIndexArray()[0])

proc getSize*(bb: BufferBuilder, index: int): int {.raises: [].} =
  result = bb.getIndexArray()[1]

proc deallocBufferBuilder*(bb: var BufferBuilder) {.raises: [].} =
  bb = bb.allocator(DEALLOC, 0)

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

proc allocateFor(ma: Allocator, metadata: BufferBuilder): pointer {.inline, raises: [].} =
  result = result.ma(
    ALLOC,
    (
      UINTSIZE + # Length
      UPSIZE * metadata.len() + # Metadata
      metadata.size() # Data
    )
  )

proc writeMetadata(address: pointer, metadata: seq[int]) {.inline, raises: [].} =
  var
    auxcast: ptr UncheckedArray[int] = getArray(address) # turns into array
    auxsum: int = sizeOf(uint)*2 # Points at the start of the data
  auxcast[0] = metadata[0] # Sets length
  auxcast[1] = metadata[1] + sizeOf(uint)*2 # Sets offset to metadata
  auxcast = getArray(address + auxcast[1]) # Points at metadata
  for index in 2..metadata.high(): # from first data element size to the last
    auxsum += metadata[index] # data start + element size == offset to the end
    auxcast[index-2] = auxsum # Assign the offset to the end of the element

proc writeData(address: pointer, data: varargs[string, `$`]) {.inline, raises: [].} =
  var cursor: pointer = calcAddress(address, sizeOf(uint)*2)
  for element in data:
    cursor.copyMem(addr element[0], element.len)
    cursor = calcAddress(cursor, element.len)

proc deallocBuffer*(buffer: var Buffer, ma: Allocator = allocator) = 
  buffer = buffer.ma(DEALLOC, 0)

proc newBuffer*(ma: Allocator = allocator, data: varargs[string, `$`]): Buffer {.raises: [].} =
  var metadata: seq[int] = getMetadata(data)
  if metadata[0] != 0:
    result = allocateFor(ma, metadata)
    result.writeMetadata(metadata)
    result.writeData(data)
  else:
    result = nil

proc newBuffer*(ma: Allocator, data: BufferBuilder): Buffer {.raises: [].} =
  result = newBuffer(ma, toSeq(data))
