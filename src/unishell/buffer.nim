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
  communicate without problems.

  Operators, iterators and procedures are provided to give the user the
  necessary calls to be able to handle the `Buffer` and `DataView` as
  if they were a simple `seq[string]`. The following procedures enable the use
  of:

  ```nim
  var x: Buffer = createBuffer(@["These", "are", "some", "strings"])

  # Use of `in` and `$` operators
  for i in x:
    echo $i

  # Use of the `[]` operator and comparison to `string` types
  if x[0] == "This":
    echo $x[0], $x[3], $x[1], $x[3] # "These strings are strings"

  # Conversion to `seq[string]`
  var y: seq[string] = toSeq(x)
  assert x == y # True
  ```
]##

import std/strutils

type
  BufferError* = object of CatchableError # The error type of this module

# =============================================================================
# EXTERNAL ALLOCATOR
# =============================================================================

#[
 Currently, it is implemented as a case statement in order to make it easier
 to export to other languages. It might be turned into a VTable with pointer
 to the respective memory management procedures later on.
]#

type
  HostAllocatorAction* = enum
    ALLOC = 0,
    DEALLOC = 1,
    DEALLOCTOALLOC = 2,
    ZEROMEM = 3
  HostAllocator* = proc(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl, raises: [].}

proc hostAllocator*(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl, raises: [].} =
  case action
  of ALLOC:
    if newsize > 0:
      return alloc0(newsize)
    else:
      return nil
  of DEALLOC:
    if address != nil:
      dealloc(address)
    return nil
  of DEALLOCTOALLOC:
    if address != nil:
      dealloc(address)
    if newsize > 0:
      return alloc0(newsize)
    else:
      return nil
  of ZEROMEM:
    if (address != nil) and (newsize != 0):
      zeroMem(address, newsize)
    return address

# =============================================================================
# DATA FIELD
# =============================================================================

#[
 The `Data` object is meant to be an abstraction over the
 `ptr UncheckedArray[char]` type.
]#

type
  DataObj = UncheckedArray[char]
  Data = ptr DataObj
  DataView* = object
    data: Data
    len: Natural

proc toDataView(data: Data, len: Natural): DataView {.inline, raises: [].} =
  result.data = data
  result.len = len

proc toString(view: DataView): string {.inline, raises: [].} =
  result = newString(view.len)
  copyMem(addr result[0], addr view.data[0], view.len)

proc writeTo(allocator: HostAllocator, dest: var DataView, src: string) {.inline, raises: [ValueError].} =
  copy(allocator, dest.data, dest.len, cast[Data](addr src[0]), src.len(), false)

proc copy(allocator: HostAllocator, dest: var Data, destlen: Natural, src: Data, srclen: Natural, destructive: bool) {.inline, raises: [ValueError].} =
  var
    destIsEmpty: bool = (dest == nil) or (destlen == 0)
    srcIsEmpty: bool = (src == nil) or (srclen == 0)
    canOperate: bool = (not destIsEmpty) or destructive
  if canOperate:
    if srcIsEmpty:
      dest = cast[Data](allocator(dest, destlen, ZEROMEM))
    elif (destlen >= srclen):
      dest = cast[Data](allocator(dest, destlen, ZEROMEM))
      copyMem(dest, src, srclen)
    elif destructive:
      dest = cast[Data](allocator(dest, destlen, DEALLOCTOALLOC))
      copyMem(dest, src, srclen)
    else:
      raise newException(ValueError, "Error: copy: input is bigger than the target container")
  else:
    raise newException(ValueError, "Error: copy: Can\'t manipulate data that doesn\'t exists and won\'t be created")

# =============================================================================
# OFFSETS FIELD
# =============================================================================

#[
 The `Offsets` object is meant to be an abstraction over the
 `ptr UncheckedArray[int]` type.
]#

type
  OffsetsObj = UncheckedArray[int]
  Offsets = ptr OffsetsObj
  OffsetView* = object
    offset: Offsets
    index: Natural

# =============================================================================
# BUFFER OBJECT
# =============================================================================

#[
 The `Buffer` object is meant to simulate a `seq[string]` type of Nim inside a
 single, flat structure
]#

type
  Buffer* = object
    data: Data       ## Single block of raw concatenated string data
    offsets: Offsets ## Offsets to the end of each string. Last one also indicates capacity
    len: Natural     ## Number of strings packed inside

# =============================================================================
# AUXILIARY PROCEDURES
# =============================================================================

proc toDataView(buffer: Buffer, index: Natural): DataView {.inline, raises: [ValueError].} =
  if index >= buffer.len:
    raise newException(ValueError, "Index out of bounds")
  elif index == 0:
    result = toDataView(
      buffer.data,
      buffer.offsets[0]
    )
  else:
    result = toDataView(
      cast[Data](addr buffer.data[buffer.offsets[index-1]]),
      buffer.offsets[index]
    )

proc toOffsetView(buffer: Buffer, index: Natural): OffsetView {.inline, raises: [ValueError].} =
  if index >= buffer.len:
    raise newException(ValueError, "Index out of bounds")
  else:
    result = OffsetView(
      offset: buffer.offsets,
      index: index
    )

proc toString(buffer: Buffer, index: Natural): string {.inline, raises: [ValueError].} =
  return toString(toDataView(buffer, index))

proc copy(allocator: HostAllocator, dest: var Offsets, destlen: Natural, src: Offsets, srclen: Natural, destructive: bool) {.inline, raises: [ValueError].} =
  var
    destIsEmpty: bool = (dest == nil) or (destlen == 0)
    srcIsEmpty: bool = (src == nil) or (srclen == 0)
    canOperate: bool = (not destIsEmpty) or destructive
    totalDestlen: int = destlen * sizeof(int)
    totalSrclen: int = srclen * sizeof(int)
  if canOperate:
    if srcIsEmpty:
      dest = cast[Offsets](allocator(dest, totalDestlen, ZEROMEM))
    elif (totalDestlen >= totalSrclen):
      dest = cast[Offsets](allocator(dest, totalDestlen, ZEROMEM))
      copyMem(dest, src, totalSrclen)
    elif destructive:
      dest = cast[Offsets](allocator(dest, totalDestlen, DEALLOCTOALLOC))
      copyMem(dest, src, totalSrclen)
    else:
      raise newException(ValueError, "Error: copy: input is bigger than the target container")
  else:
    raise newException(ValueError, "Error: copy: Can\'t manipulate data that doesn\'t exists and won\'t be created")

proc writeTo(dest: var OffsetView, value: Natural) {.inline, raises: [ValueError].} =
  dest.offset[dest.index] = value

# =============================================================================
# LIFETIME MANAGEMENT (Automatic Destructors)
# =============================================================================

proc `=destroy`*(buffer: var Buffer) =
  buffer.data = hostAllocator(
    buffer.data,
    buffer.offsets[buffer.len-1],
    DEALLOC
  )
  buffer.offsets = hostAllocator(
    buffer.offsets,
    buffer.len * sizeof(int),
    DEALLOC
  )
  buffer.len = 0

proc `=copy`*(dest: var Buffer; src: Buffer) =
  copy(
    dest.data,
    dest.offsets[dest.len-1],
    src.data,
    src.offsets[src.len-1],
    true
  )
  copy(
    dest.offsets,
    dest.len * sizeof(int),
    src.offsets,
    src.len * sizeof(int),
    true
  )
  dest.len = src.len

proc `=wasMoved`*(buffer: var Buffer) =
  # This hook is provided to make sure that the pointers are simply set to `nil`
  buffer.offsets = nil
  buffer.data = nil
  buffer.len = 0

# =============================================================================
# CONSTRUCTOR (PUBLIC API)
# =============================================================================
 
proc createBuffer*(strings: seq[string]): Buffer {.raises: [BufferError].} =
  ##[
    Creates a new `Buffer` object from the provided sequence of strings. Example:

    ```nim
    var
      x: seq[string] = @["some", "strings"]
      y: Buffer = createBuffer(x)
    ```
  ]##
  var
    offset: int = 0
    dataView: DataView
    offsetView: offsetView
  try:
    result.len = strings.len()
    hostAllocator(result.offsets, result.len * sizeof(int), ALLOC)
    for index, element in pairs(strings):
      offset += element.len()
      offsetView = toOffsetView(result, index)
      writeTo(offsetView, offset)
    hostAllocator(result.data, offsets, ALLOC)
    for index, element in pairs(strings):
      dataView = getDataView(result, index)
      writeTo(hostAllocator, dataView, element)
  except ValueError:
    raise newException(BufferError, "Couldn\'t create buffer")
 
proc createBuffer*(allocator: HostAllocator, buffer: ptr Buffer, strings: seq[string]) {.raises: [BufferError].} =
  var
    offset: int = 0
    dataView: DataView
    offsetView: offsetView
  try:
    buffer.len = strings.len()
    allocator(buffer.offsets, buffer.len * sizeof(int), ALLOC)
    for index, element in pairs(strings):
      offset += element.len()
      offsetView = toOffsetView(buffer, index)
      writeTo(offsetView, offset)
    allocator(buffer.data, offsets, ALLOC)
    for index, element in pairs(strings):
      dataView = getDataView(buffer, index)
      writeTo(allocator, dataView, element)
  except ValueError:
    raise newException(BufferError, "Couldn\'t create buffer")

# =============================================================================
# OPERATORS, ITERATORS AND PROCEDURES (PUBLIC API)
# =============================================================================

proc `==`*(a, b: DataView): bool {.inline, raises: [].} =
  if a.len == b.len:
    return equalMem(a.data, b.data, a.len)
  else:
    return false
  
proc `==`*(a: DataView, b: string): bool {.inline, raises: [].} =
  ##[
    Checks if the contained string inside a `DataView` is equal to the
    provided string. Example:

    ```nim
    var
      x: Buffer = createBuffer(@["hello"])
      y: string = "hello"

    if x[0] == y: echo "It works!"
    ```
  ]##
  return (a.toString() == b)

proc `[]`*(view: DataView, index: Natural): char {.raises: [ValueError].} =
  if index > view.len:
    raise newException(ValueError, "Error: []: index out of bounds")
  else:
    return view.data[index]

proc `$`*(view: DataView): string =
  ##[
    Converts a `DataView` into a string. Example:

    ```nim
    var x: Buffer = createBuffer(@["Hello"])

    if x[0] is BufferElementView:
      echo $x[0]
    ```
  ]##
  return view.toString()

iterator items*(buffer: Buffer): DataView {.raises: [].} =
  ##[
    Iterates over a `Buffer` and returns a view for each contained string.

    It is necessary for the `find` procedure and the `in` operator.
  ]##
  for i in 0 ..< buffer.len:
    yield buffer.toDataView(i)

proc find*(buffer: Buffer, item: string): int {.inline, raises: [].} =
  ##[
    Iterates over a `Buffer` object and returns the first index that contains
    the provided string.

    It is necessary for the `contains` procedure and the `in` operator.
  ]##
  result = 0
  for view in buffer:
    if view == item:
      return result
    inc(result)
  return -1

proc contains*(buffer: Buffer, item: string): bool {.inline, raises: [].} =
  ##[
    Iterates over a `Buffer` object and returns `true` if the provided
    string is inside said `Buffer`.
    
    It is necessary for the `in` operator.
  ]##
  find(buffer, item) >= 0

proc len*(buf: Buffer): int {.inline, raises: [].} =
  ##[
    Returns the number of strings contained within the buffer. Example:

    ```nim
    var x: Buffer = createBuffer(@["1", "2", "3"])
    echo $x.len() # "3"
    ```
  ]##
  result = buf.len

proc `[]`*(buffer: Buffer, index: int): DataView {.raises: [].} =
  ##[
    Returns a view to the string contained within the provided index. Example:

    ```nim
    var x: Buffer = createBuffer(@["I am a string!"])
    echo $x[0] # "I am a string"
    ```
  ]##
  result = buffer.toDataView(index)

proc toSeq*(buffer: Buffer): seq[string] {.raises: [].} =
  ##[
    Creates a new `seq[string]` out of the provided `Buffer`. Example:

    ```nim
    var
      x: Buffer = createBuffer(@["Hello", "world"])
      y: seq[string] = x.toSeq()
    ```
  ]##
  result = newSeqOfCap[string](buffer.len)
  for element in buffer:
    result.add($element)
