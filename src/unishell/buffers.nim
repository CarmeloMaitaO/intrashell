type
  Buffer* = object
    data: pointer       # Single block of raw concatenated string data
    cap: uint           # Length of the `data` field
    offsets: ptr UncheckedArray[uint] # Starting offset of each string
    sizes: ptr UncheckedArray[uint]   # Length of each string
    len: int            # Number of strings packed inside

# =============================================================================
# LIFETIME MANAGEMENT (Automatic Destructors)
# =============================================================================

proc freeBuffer*(buf: var Buffer) =
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
  # Handle self-assignment
  if dest.data == src.data: return
  dest.freeBuffer()
  dest.len = src.len
  dest.cap = src.cap
  if src.len > 0:
    dest.sizes = cast[ptr UncheckedArray[uint]](alloc(uint(src.len * sizeof(uint))))
    dest.offsets = cast[ptr UncheckedArray[uint]](alloc(uint(src.len * sizeof(uint))))
    copyMem(dest.sizes, src.sizes, src.len * sizeof(uint))
    copyMem(dest.offsets, src.offsets, src.len * sizeof(uint))
  if src.cap > 0'u:
    dest.data = alloc(src.cap)
    copyMem(dest.data, src.data, src.cap.int)

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
  if index < 0 or index >= buf.len or buf.data == nil:
    outPtr = nil
    outLen = 0'u
    return
  outLen = buf.sizes[index]
  if outLen > 0'u:
    outPtr = cast[pointer](cast[uint](buf.data) + buf.offsets[index])
  else:
    outPtr = nil

proc getStringCopy(buf: Buffer, index: int): string {.inline.} =
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

proc `==`(s: string, oa: openArray[char]): bool =
  if s.len != oa.len: return false
  if s.len == 0: return true
  return equalMem(cast[pointer](unsafeAddr s[0]), cast[pointer](unsafeAddr oa[0]), s.len)

proc `==`(oa: openArray[char], s: string): bool {.inline.} =
  # Reuses your logic regardless of argument order
  s == oa 

proc `!=`(oa: openArray[char], s: string): bool {.inline.} =
  not (oa == s)

proc `!=`(s: string; oa: openArray[char]): bool {.inline.} =
  not (s == oa)

proc len*(buf: Buffer): int {.inline.} = buf.len

proc createBuffer*(strings: seq[string]): Buffer =
  result.len = strings.len()
  if result.len == 0: return

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

iterator copies*(buf: Buffer): string =
  ## Yields actual string copies (slower, but gives isolated standard strings)
  for i in 0 ..< buf.len:
    yield buf.getStringCopy(i)

proc find*(buf: Buffer, item: string): int {.inline.} =
  result = 0
  for view in buf:
    if view == item:
      return result
    inc(result)
  return -1

proc contains*(buf: Buffer, item: string): bool {.inline.} =
  find(buf, item) >= 0

proc `[]`*(buf: Buffer, index: int): string =
  if (index < 0) or (index >= buf.len):
    raise newException(IndexDefect, "Index out of bounds: " & $index)
  buf.getStringCopy(index)
