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
  language the modules or the main binary are written in, they will
  communicate without problems.

  Operators, iterators and procedures are provided to give the user the
  necessary calls to be able to handle the `Buffer` and `BufferElementView` as
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
  Offsets = ptr UncheckedArray[uint]
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

proc allocateSizes(dest: Sizes, size: Natural) {.inline.} =
  dest = cast[Sizes](hostAllocator(size, ALLOC))

proc allocateSizes(dest: Sizes, allocator: HostAllocator, size: Natural) {.inline.} =
  dest = cast[Sizes](allocator(size, ALLOC))

proc deallocSizes(dest: Sizes) {.inline.} =
  hostAllocator(dest, DEALLOC)

proc deallocSizes(dest: Sizes, allocator: HostAllocator) {.inline.} =
  allocator(dest, DEALLOC)

proc copySizes(dest: Sizes, src: Sizes, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = hostAllocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc copySizes(dest: Sizes, allocator: HostAllocator, src: Sizes, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = allocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc assignToSizes(dest: Sizes, index: Natural, value: Natural) {.inline.} =
  dest[index] = value

proc allocateOffsets(dest: Offsets, size: Natural) {.inline.} =
  dest = cast[Offsets](hostAllocator(size, ALLOC))

proc allocateOffsets(dest: Offsets, allocator: HostAllocator, size: Natural) {.inline.} =
  dest = cast[Offsets](allocator(size, ALLOC))

proc deallocOffsets(dest: Offsets) {.inline.} =
  hostAllocator(dest, DEALLOC)

proc deallocOffsets(dest: Offsets, allocator: HostAllocator) {.inline.} =
  allocator(dest, DEALLOC)

proc copyOffsets(dest: Offsets, src: Offsets, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = hostAllocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc copyOffsets(dest: Offsets, allocator: HostAllocator, src: Offsets, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = allocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc assignToOffsets(dest: Offsets, index: Natural, value: Natural) {.inline.} =
  dest[index] = value

proc allocateData(dest: Data, size: Natural) {.inline.} =
  dest = cast[Data](hostAllocator(size, ALLOC))

proc allocateData(dest: Data, allocator: HostAllocator, size: Natural) {.inline.} =
  dest = cast[Data](allocator(size, ALLOC))

proc deallocData(dest: Data) {.inline.} =
  hostAllocator(dest, DEALLOC)

proc deallocData(dest: Data, allocator: HostAllocator) {.inline.} =
  allocator(dest, DEALLOC)

proc copyData(dest: Data, src: Data, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = hostAllocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc copyData(dest: Data, allocator: HostAllocator, src: Data, size: Natural) {.inline.} =
  if (src != nil) and (size > 0) and (src != dest):
    dest = allocator(dest, size, DEALLOCTOALLOC)
    copyMem(dest, src, size)

proc getDataView(src: Data, start, end: Natural): DataView =
  return DataView(
    data: cast[Data](addr src[start]),
    len: end
  )

proc assignToDataView(dest: var DataView, src: openArray[char]) =
  if src.len() <= dest.len:
    dest.data = hostAllocator(dest.data, dest.len, ZEROMEM)
    copyData(dest.data, cast[Data](src), src.len())

proc assignToDataView(dest: var DataView, src: string) =
  assignToDataView(dest, src.toOpenArray(src.low(), src.high()))

# =============================================================================
# LIFETIME MANAGEMENT (Automatic Destructors)
# =============================================================================

proc freeBuffer(buf: var Buffer) =
  #[
    Deallocates the memory of a `Buffer` object.

    This is a helper procedure used in the custom lifetime-tracking hooks
    declared for the `Buffer` object
  ]#
  if buf.sizes != nil: dealloc(buf.sizes)
  if buf.offsets != nil: dealloc(buf.offsets)
  if buf.data != nil: dealloc(buf.data)
  buf.sizes = nil
  buf.offsets = nil
  buf.data = nil
  buf.len = 0
  buf.cap = 0

proc `=destroy`*(buf: var Buffer) =
  buf.freeBuffer()

proc `=copy`*(dest: var Buffer; src: Buffer) =
  # Auxiliary variables for the sizes to allocate and its pointers
  var
    sizeOfSizes: int = src.len * sizeof(int) # size of `sizes`
    sizeOfOffsets: int = src.len * sizeof(uint) # size of `offsets`
  if dest.data != src.data:
    #[
      This case is for performing the actual copy.
      It starts by destroying the data in the destination and
      copying the values of the primitive fields 
    ]#
    dest.freeBuffer()
    dest.len = src.len
    dest.cap = src.cap
    #[
      Then, if the source has any data (strings), a copy of it's
      content is performed
    ]#
    if src.len > 0:
      dest.sizes = cast[ptr UncheckedArray[int]](alloc(sizeOfSizes))
      dest.offsets = cast[ptr UncheckedArray[uint]](alloc(sizeOfOffsets))
      copyMem(dest.sizes, src.sizes, sizeOfSizes)
      copyMem(dest.offsets, src.offsets, sizeOfOffsets)
    #[
      While the following check may seem redundant, it covers the case in which
      the buffer only has empty strings (`""`). In such case, the copy of the
      data is not performed, and its value remains as `nil`
    ]#
    if src.cap > 0:
      dest.data = cast[ptr UncheckedArray[char]](alloc(src.cap))
      copyMem(dest.data, src.data, src.cap)
    else:
      dest.data = nil
  else:
    # This case is for self-assigments.
    # They should be ignored
    discard

proc `=wasMoved`*(buffer: var Buffer) =
  # This hook is provided to make sure that the pointers are simply set to `nil`
  buffer.sizes = nil
  buffer.offsets = nil
  buffer.data = nil
  buffer.len = 0
  buffer.cap = 0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

proc getView(buffer: Buffer, index: int): BufferElementView {.inline.} =
  #[
    Helper procedure that provides direct access to the string inside the
    buffer under the specified index.

    It achieves this by casting a pointer to the data, to a pointer to an
    UncheckedArray of characters (`ptr UncheckedArray[char]`)
  ]#
  # First checks if the index is within bounds, otherwise throws an error
  if (index >= 0) and (index < buffer.len):
    # Gets the length of the string from the `sizes` array using the index
    result.len = buffer.sizes[index]
    # Sets the data pointer to `nil` and only changes it if the string isn't
    # empty.
    result.data = nil
    if result.len > 0:
      # Gets the pointer to the UncheckedArray from the sum of the base
      # pointer of `data` and the `offset` fields
      result.data = cast[ptr UncheckedArray[char]](
        addr buffer.data[buffer.offsets[index]]
      )
  else:
    raise newException(IndexDefect, "Index out of bounds")

# =============================================================================
# CONSTRUCTOR (PUBLIC API)
# =============================================================================
# 
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
  # Auxiliary variables for the sizes to allocate and its pointers
  var
    sizeOfSizes: int = result.len * sizeof(int) # size of `sizes`
    sizeOfOffsets: int = result.len * sizeof(uint) # size of `offsets`
    sizeOfData: int = 0                            # size of `data`
    dataAddress: uint = 0                          # pointer to `data`
    elementOffset: uint = 0                        # offset of an element in `data`
    elementAddress: uint = 0                       # pointer to an element in `data`
  # Checks whether the sequence is empty or not
  if result.len != 0:
    # This is the case for a sequence that isn't empty
    # Allocates the memory for the metadata
    result.sizes = cast[ptr UncheckedArray[int]](alloc0(sizeOfSizes))
    result.offsets = cast[ptr UncheckedArray[uint]](alloc0(sizeOfOffsets))

    # Populates the `sizes` array and gets the `sizeOfData`
    for index, element in pairs(strings):
      result.sizes[index] = element.len()
      sizeOfData += element.len()

    # Checks that the input isn't composed of empty strings (`""`),
    # allocates the memory that will contain the data and sets the `cap` field
    # to it's size
    if sizeOfData > 0:
      result.data = alloc0(sizeOfData)
      result.cap = sizeOfData
    
      # Gets the pointer to data and populates it
      dataAddress = cast[uint](result.data) # Base pointer to the `data` field
      for index, element in pairs(strings):
        #[
          The address of the element is obtained after adding to the base
          pointer of the `data` field, the current offset of the current
          element, which starts at 0 and increments by the length (in bytes)
          of the element after each iteration of the cycle.

          The offset of empty strings is left to 0 given that on
          extraction by the `getBufferElementView` procedure, the length
          of the data will be read first, and based on that the pointer
          to it will be modified from `nil` to the actual data.
        ]#
        if element.len > 0:
          result.offsets[index] = elementOffset
          elementAddress = dataAddress + elementOffset
          copyMem(cast[pointer](elementAddress), addr element[0], element.len)
        else:
          result.offsets[index] = 0
        elementOffset += (result.sizes[index]).uint
    else:
      result.data = nil
      result.cap = 0
  else:
    # This is the case for an empty sequence.
    # The buffer should be created in it's default state
    discard

# =============================================================================
# OPERATORS, ITERATORS AND PROCEDURES (PUBLIC API)
# =============================================================================

proc `==`*(view: BufferElementView; str: string): bool {.inline.} =
  ##[
    Checks if the contained string inside a `BufferElementView` is equal to the
    provided string. Example:

    ```nim
    var
      x: Buffer = createBuffer(@["hello"])
      y: string = "hello"

    if x[0] == y: echo "It works!"
    ```
  ]##
  #[
    To perform this check:

    1. Checks that both strings have different sizes: if true, returns false,
       otherwise we are left to check for cases where the strings are
       equal-sized
    2. Checks that both strings are empty (`len == 0`): if true, returns true,
       otherwise we are left to check for cases where the strings are not
       empty and are equal-sized
    3. Checks that both strings are equal by comparing their raw memory
  ]#
  if view.len != str.len:
    return false
  if (view.len == 0) and (str.len == 0):
    return true
  return equalMem(view.data, addr str[0], view.len)

proc `$`*(view: BufferElementView): string =
  ##[
    Converts a `BufferElementView` into a string. Example:

    ```nim
    var x: Buffer = createBuffer(@["Hello"])

    if x[0] is BufferElementView:
      echo $x[0]
    ```
  ]##
  if view.len == 0 or view.data == nil: return ""
  result = newString(view.len)
  copyMem(addr result[0], view.data, view.len)

iterator items*(buffer: Buffer): BufferElementView =
  ##[
    Iterates over a `Buffer` and returns a view for each contained string.

    It is necessary for the `find` procedure and the `in` operator.
  ]##
  for i in 0 ..< buffer.len:
    yield buffer.getView(i)

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

proc `[]`*(buffer: Buffer, index: int): BufferElementView =
  ##[
    Returns a view to the string contained within the provided index. Example:

    ```nim
    var x: Buffer = createBuffer(@["I am a string!"])
    echo $x[0] # "I am a string"
    ```
  ]##
  result = buffer.getView(index)

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

proc preAllocateBuffer*(buffer: ptr Buffer, len: int, cap: int) =
  ## Allocates an empty buffer with the given length and capacity
  buffer.len = len
  buffer.cap = cap
  var
    sizeOfSizes: int = len * sizeof(int)
    sizeOfOffsets: int = len * sizeof(uint)
  if len > 0:
    buffer.sizes = cast[ptr UncheckedArray[int]](alloc0(sizeOfSizes))
    buffer.offsets = cast[ptr UncheckedArray[uint]](alloc0(sizeOfOffsets))
  else:
    buffer.sizes = nil
    buffer.offsets = nil
  if cap > 0:
    buffer.data = alloc0(cap)
  else:
    buffer.data = nil
