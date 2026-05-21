##[
  This module provides a `Buffer` object that packs a variable number of strings
  of different sizes inside a single, contiguous chunk of memory; simulating
  a sequence of strings (`seq[string]`), with the associated procedures and
  iterators, while being easy to pass between the main executable and it's
  shared/dynamic/runtime-loaded libraries.

  It uses Nim's native strings because they behave like buffers of their own,
  and are capable of holding binary data, such as files, within them; which
  enables the `Buffer` object to be a buffer of buffers.
]##
type Buffer* = object
  data: pointer                     ## Single block of raw concatenated string data
  cap: uint                         ## Length of the `data` field
  offsets: ptr UncheckedArray[uint] ## Starting offset of each string
  sizes: ptr UncheckedArray[uint]   ## Length of each string
  len: int                          ## Number of strings packed inside

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
  # Self-explanatory
  buf.freeBuffer()

proc `=copy`*(dest: var Buffer; src: Buffer) =
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
      dest.sizes = cast[ptr UncheckedArray[uint]](alloc(uint(src.len * sizeof(uint))))
      dest.offsets = cast[ptr UncheckedArray[uint]](alloc(uint(src.len * sizeof(uint))))
      copyMem(dest.sizes, src.sizes, src.len * sizeof(uint))
      copyMem(dest.offsets, src.offsets, src.len * sizeof(uint))
    #[
      While the following check may seem redundant, it covers the case in which
      the buffer only has empty strings (`""`). In such case, the copy of the
      data is not performed, and its value remains as `nil`
    ]#
    if src.cap > 0'u:
      dest.data = alloc(src.cap)
      copyMem(dest.data, src.data, src.cap.int)
  else:
    # This case is for self-assigments.
    # They should be ignored
    discard

proc `=sink`(dest: var Buffer; src: Buffer) =
  dest.freeBuffer()
  dest.data = src.data
  dest.cap = src.cap
  dest.offsets = src.offsets
  dest.sizes = src.sizes
  dest.len = src.len
  # Prevent src from freeing the memory
  wasMoved(src)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

proc getStringView(buf: Buffer, index: int, outPtr: var pointer, outLen: var uint) {.inline.} =
  #[
    Helper procedure that provides direct access to the string inside the
    buffer under the specified index.

    It achieves this by modifying in-place the provided pointer and unsigned
    integer passed in the parameters; populating them with the address of the
    string and it's length.
  ]#
  # Checks if the index is within the bounds of the buffer
  if index < 0 or index >= buf.len or buf.data == nil:
    # This case is for out of bounds indexes
    outPtr = nil
    outLen = 0'u
  else:
    # This case is for indexes that are within the bounds of the buffer
    outLen = buf.sizes[index]
    if outLen > 0'u:
      outPtr = cast[pointer](cast[uint](buf.data) + buf.offsets[index])
    else:
      outPtr = nil

proc getStringCopy(buf: Buffer, index: int): string {.inline.} =
  #[
    Returns a string copy of the view from the buffer under the specified
    index.

    Uses `getStringView` to get the view.
  ]#
  var 
    strPtr: pointer
    strLen: uint
  buf.getStringView(index, strPtr, strLen)
  if strLen > 0'u and strPtr != nil:
    result = newString(strLen.int)
    copyMem(addr result[0], strPtr, strLen.int)
  else:
    result = ""

# =============================================================================
# PUBLIC API
# =============================================================================

proc len*(buf: Buffer): int {.inline.} =
  ## Returns the number of strings contained within the buffer.
  result = buf.len

proc createBuffer*(strings: seq[string]): Buffer =
  ## Creates a new `Buffer` object from the provided sequence of strings.
  result.len = strings.len()
  # Checks whether the sequence is empty or not
  if result.len != 0:
    # This is the case for a sequence that isn't empty
    let sizeOfMetadata = uint(result.len * sizeof(uint))
    result.sizes = cast[ptr UncheckedArray[uint]](alloc0(sizeOfMetadata))
    result.offsets = cast[ptr UncheckedArray[uint]](alloc0(sizeOfMetadata))

    var totalDataSize: uint = 0'u
    for index, element in pairs(strings):
      result.sizes[index] = element.len().uint
      result.offsets[index] = totalDataSize
      totalDataSize += element.len().uint

    if totalDataSize > 0'u:
      result.data = alloc0(totalDataSize)
      result.cap = totalDataSize
    
      let baseAddress = cast[uint](result.data)
      for index, element in pairs(strings):
        if element.len > 0:
          let dstPtr = cast[pointer](baseAddress + result.offsets[index])
          copyMem(dstPtr, unsafeAddr element[0], element.len)
  else:
    # This is the case for an empty sequence.
    # The buffer should be created in it's default state
    discard

iterator items*(buf: Buffer): openArray[char] =
  for i in 0 ..< buf.len:
    var 
      strPtr: pointer
      strLen: uint
    buf.getStringView(i, strPtr, strLen)
    if strLen > 0'u and strPtr != nil:
      yield toOpenArray(cast[ptr UncheckedArray[char]](strPtr), 0, strLen.int - 1)
    else:
      yield "".toOpenArray(0, -1)

proc find*(buf: Buffer, item: string): int {.inline.} =
  result = 0
  for view in buf:
    if view == item.toOpenArray(0, item.len()-1):
      return result
    inc(result)
  return -1

proc contains*(buf: Buffer, item: string): bool {.inline.} =
  find(buf, item) >= 0

proc `[]`*(buf: Buffer, index: int): string =
  if (index < 0) or (index >= buf.len):
    raise newException(IndexDefect, "Index out of bounds: " & $index)
  buf.getStringCopy(index)
