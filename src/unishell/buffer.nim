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
type
  HostAllocatorAction* = enum
    ALLOC,
    DEALLOC,
    DEALLOCTOALLOC,
    ZEROMEM
  HostAllocator* = proc(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl.}

proc hostAllocator*(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl.} =
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

type
  Data = ptr UncheckedArray[char]
  DataView* = object
    data: Data
    len: Natural
  Offsets = ptr UncheckedArray[int]
  Sizes = ptr UncheckedArray[int]
  Buffer* = object
    data: Data       ## Single block of raw concatenated string data
    cap: Natural     ## Length of the `data` field
    offsets: Offsets ## Offsets to each string
    sizes: Sizes     ## Length of each string
    len: Natural     ## Number of strings packed inside


# =============================================================================
# AUXILIARY PROCEDURES
# =============================================================================

proc allocate[T: Data|Offsets|Sizes](dest: T, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  dest = cast[T](hostAllocator(totalLen, ALLOC))

proc allocate[T: Data|Offsets|Sizes](dest: T, allocator: HostAllocator, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  dest = cast[T](allocator(totalLen, ALLOC))

proc deallocate[T: Data|Offsets|Sizes](dest: T) {.inline.} =
  dest = hostAllocator(dest, DEALLOC)

proc deallocate[T: Data|Offsets|Sizes](dest: T, allocator: HostAllocator) {.inline.} =
  dest = allocator(dest, DEALLOC)

proc overwrite[T: Data|Offsets|Sizes](dest: T, src: T, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  if (src != dest):
    if (src != nil) and (len > 0):
      dest = hostAllocator(dest, totalLen, DEALLOCTOALLOC)
      copyMem(dest, src, totalLen)
    else:
      deallocate(dest)

proc overwrite[T: Data|Offsets|Sizes](dest: T, allocator: HostAllocator, src: T, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  if (src != dest):
    if (src != nil) and (len > 0):
      dest = allocator(dest, totalLen, DEALLOCTOALLOC)
      copyMem(dest, src, totalLen)
    else:
      deallocate(dest, allocator)

proc copy[T: Data|Offsets|Sizes](dest: T, src: T, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  if (src != nil) and (len > 0):
    dest = hostAllocator(dest, totalLen, ZEROMEM)
    copyMem(dest, src, totalLen)

proc copy[T: Data|Offsets|Sizes](dest: T, allocator: HostAllocator, src: T, len: Natural) {.inline.} =
  when not (T is Data):
    var totalLen: int = len * sizeof(int)
  else:
    var totalLen: int = len
  if (src != nil) and (len > 0):
    dest = allocator(dest, totalLen, ZEROMEM)
    copyMem(dest, src, totalLen)

proc getDataView(src: Data, start, end: Natural): DataView =
  return DataView(
    data: cast[Data](addr src[start]),
    len: end
  )

proc getDataView(src: Buffer, index: Natural): DataView =
  return getDataView(
    src.data,
    src.offsets[index],
    src.sizes[index] - 1
  )

proc toDataView(arr: openArray[char]): DataView =
  return DataView(
    data: cast[Data](addr arr),
    len: arr.len()
  )

proc toDataView(str: string): DataView =
  return toDataview(
    str.toOpenArray(
      str.low(),
      str.high()
    )
  )

proc assignTo[T: DataView|Offsets|Sizes; V: Natural|openArray[char]|string](dest: T, value: V, index: Natural = 0) {.inline, raises: [ValueError].} =
  when (not (T is DataView)) and (V is Natural):
    dest[index] = value
  elif (T is DataView) and (V is openArray[char]):
    if src.len() <= dest.len:
      copy(dest.data, (value.toDataView()).data, value.len())
    else:
      raise newException(ValueError, "Value is bigger than container")
  elif (T is DataView) and (V is string):
    if src.len() <= dest.len:
      copy(dest.data, (value.toDataView()).data, value.len())
    else:
      raise newException(ValueError, "Value is bigger than container")
  else:
    raise newException(ValueError, "The combination of type and value is not valid")

proc assignTo[T: DataView|Offsets|Sizes; V: Natural|openArray[char]|string](dest: T, allocator: HostAllocator, value: V, index: Natural = 0) {.inline, raises: [ValueError].} =
  when (not (T is DataView)) and (V is Natural):
    dest[index] = value
  elif (T is DataView) and (V is openArray[char]):
    if src.len() <= dest.len:
      copy(dest.data, allocator, (value.toDataView()).data, value.len())
    else:
      raise newException(ValueError, "Value is bigger than container")
  elif (T is DataView) and (V is string):
    if src.len() <= dest.len:
      copy(dest.data, allocator, (value.toDataView()).data, value.len())
    else:
      raise newException(ValueError, "Value is bigger than container")
  else:
    raise newException(ValueError, "The combination of type and value is not valid")

# =============================================================================
# LIFETIME MANAGEMENT (Automatic Destructors)
# =============================================================================

proc `=destroy`*(buf: var Buffer) =
  deallocate(buf.data)
  deallocate(buf.sizes)
  deallocate(buf.offsets)
  buf.len = 0
  buf.cap = 0

proc `=copy`*(dest: var Buffer; src: Buffer) =
  dest.cap = src.cap
  dest.len = src.len
  overwrite(dest.sizes, src.sizes, src.len)
  overwrite(dest.offsets, src.offsets, src.len)
  overwrite(dest.data, src.data, src.cap)

proc `=wasMoved`*(buffer: var Buffer) =
  # This hook is provided to make sure that the pointers are simply set to `nil`
  buffer.sizes = nil
  buffer.offsets = nil
  buffer.data = nil
  buffer.len = 0
  buffer.cap = 0

# =============================================================================
# CONSTRUCTOR (PUBLIC API)
# =============================================================================
 
proc createBuffer*(strings: seq[string]): Buffer =
  ##[
    Creates a new `Buffer` object from the provided sequence of strings. Example:

    ```nim
    var
      x: seq[string] = @["some", "strings"]
      y: Buffer = createBuffer(x)
    ```
  ]##
  result.len = strings.len()
  allocate(result.sizes, result.len)
  allocate(result.offsets, result.len)
  var cap: int = 0
  var offset: int = 0
  for index, element in pairs(strings):
    assignTo(result.sizes, element.len(), index)
    assignTo(result.offsets, offset, index)
    cap += element.len()
    offset += element.len()
  allocate(result.data, result.cap)
  for index, element in pairs(strings):
    assignTo(
      getDataView(result.data, result.offset[index], result.sizes[index] - 1),
      element
    )
 
proc createBufferInPlace*(buffer: ptr Buffer, allocator: HostAllocator, strings: seq[string]) =
  buffer.len = strings.len()
  allocate(buffer.sizes, allocator, buffer.len)
  allocate(buffer.offsets, allocator, buffer.len)
  var cap: int = 0
  var offset: int = 0
  for index, element in pairs(strings):
    assignTo(buffer.sizes, allocator, element.len(), index)
    assignTo(buffer.offsets, allocator, offset, index)
    cap += element.len()
    offset += element.len()
  allocate(buffer.data, allocator, buffer.cap)
  for index, element in pairs(strings):
    assignTo(
      getDataView(buffer.data, buffer.offset[index], buffer.sizes[index] - 1),
      allocator,
      element
    )

# =============================================================================
# OPERATORS, ITERATORS AND PROCEDURES (PUBLIC API)
# =============================================================================

proc `==`*(a, b: DataView): bool {.inline.} =
  if a.len == b.len:
    return equalMem(a.data, b.data, a.len)
  else:
    return false
  
proc `==`*(a: DataView, b: openArray[char]): bool {.inline.} =
  return (a == b.toDataView())

proc `==`*(a: DataView, b: string): bool {.inline.} =
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
  return (a == b.toDataView())

proc `$`*(view: DataView): string =
  ##[
    Converts a `BufferElementView` into a string. Example:

    ```nim
    var x: Buffer = createBuffer(@["Hello"])

    if x[0] is BufferElementView:
      echo $x[0]
    ```
  ]##
  return (
    $(view.toOpenArray(view[0], view[view.len-1]))
  )

iterator items*(buffer: Buffer): DataView =
  ##[
    Iterates over a `Buffer` and returns a view for each contained string.

    It is necessary for the `find` procedure and the `in` operator.
  ]##
  for i in 0 ..< buffer.len:
    yield buffer.getDataView(i)

proc find*(buffer: Buffer, item: string): int {.inline.} =
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

proc contains*(buffer: Buffer, item: string): bool {.inline.} =
  ##[
    Iterates over a `Buffer` object and returns `true` if the provided
    string is inside said `Buffer`.
    
    It is necessary for the `in` operator.
  ]##
  find(buffer, item) >= 0

proc len*(buf: Buffer): int {.inline.} =
  ##[
    Returns the number of strings contained within the buffer. Example:

    ```nim
    var x: Buffer = createBuffer(@["1", "2", "3"])
    echo $x.len() # "3"
    ```
  ]##
  result = buf.len

proc `[]`*(buffer: Buffer, index: int): DataView =
  ##[
    Returns a view to the string contained within the provided index. Example:

    ```nim
    var x: Buffer = createBuffer(@["I am a string!"])
    echo $x[0] # "I am a string"
    ```
  ]##
  result = buffer.getDataView(index)

proc toSeq*(buffer: Buffer): seq[string] =
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
