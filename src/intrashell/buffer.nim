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
    ALLOC = 0,
    DEALLOC = 1,
    ZEROMEM = 2
  allocator* = proc(
    address: pointer = nil,
    action: AllocatorAction,
    newsize: Natural
  ): pointer {.cdecl, raises: [].}

proc allocator*(
  address: pointer = nil,
  action: AllocatorAction,
  newsize: Natural
): pointer {.cdecl, raises: [].} =
  result = address
  case action
  of ALLOC:
    if address == nil:
      if newsize > 0:
        result = alloc(newsize)
    else:
      dealloc(address)
      result = alloc(newsize)
  of DEALLOC:
    if address != nil:
      dealloc(address)
      result = nil
  of ZEROMEM:
    if (address != nil) and (newsize != 0):
      zeroMem(address, newsize)
    result = address

# =============================================================================
# HELPERS
# =============================================================================

##[
  This is the helper module for allocating memory using the Allocator module
  creating views to it. Given that the Buffer type only supports numbers and
  characters, this module was made to only be able to manage those types.
]##

proc calcAddress(address: pointer, offset: int = 0): pointer {.inline, raises: [].} =
  result = cast[pointer](cast[uint](address) + cast[uint](offset))

proc calcAddress(address: pointer, offset: uint = 0): pointer {.inline, raises: [].} =
  result = cast[pointer](cast[uint](address) + offset)

proc getArray(address: pointer, offset: int = 0): ptr UncheckedArray[int] {.inline, raises: [].} =
  result = cast[ptr UncheckedArray[int]](calcAddress(address, offset))

proc getArray(address: pointer, offset: uint = 0): ptr UncheckedArray[int] {.inline, raises: [].} =
  result = cast[ptr UncheckedArray[int]](calcAddress(address, offset))

# =============================================================================
# BUFFER BUILDER
# =============================================================================
 
type BufferBuilder* = pointer
  ##[
    Simulates a `seq[(pointer, int)]` in order to simplify the process of
    writing bindings to other languages.

    C, other languages, and different `malloc()` implementations have
    different ways of storing the metadata of a memory allocation, so in order
    to be able to read the data from Nim in a completely agnostic way, a
    custom object is provided in the form of a flat memory structure, with the
    following layout:

    | Capacity |    Length    | Size  |                Data               |
    | -------- | ------------ |------ | --------------------------------- |
    |   USIZE  |     USIZE    | USIZE |          UPSIZE * Length          |

    - USIZE: size in bytes of a single unsigned integer
    - UPSIZE: size in bytes of a USIZE pair

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

const
  USIZE*: Natural = sizeOf(uint) ## Size in bytes of a single unsigned integer
  UPSIZE*: Natural = USIZE*2 ## Size in bytes of a USIZE pair
  UTSIZE*: Natural = USIZE*3 ## Size in bytes of a USIZE trio

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

proc allocateFor(ma: Allocator, metadata: seq[int]): pointer {.inline, raises: [].} =
  result = result.ma(
    ALLOC,
    (
      (sizeOf(uint)*2) + # Number of elements & offset to offset list
      metadata[1] + # Total size of a packed array with all the elements
      (sizeOf(uint)*metadata[0]) # An offset for every element
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


type Buffer* = pointer
  ##[
    Simulates a `seq[string]` in a flat structure. It's structured like this:

    |    Length    | Offset to metadata |       Data      |      Metadata    |
    | ------------ | ------------------ | --------------- | ---------------- |
    |    USIZE     |       USIZE        | UTSIZE * Length |   Length * USIZE |

    - Length: indicates the number of contained strings.
    - Offset to metadata: points at the start of the metadata
    - Data: The contained strings.
    - Metadata: offsets that mark the end of each string.
  ]##

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
