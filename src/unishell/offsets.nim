# =============================================================================
# OFFSETS FIELD
# =============================================================================

#[
 The `Offsets` object is meant to be an abstraction over the
 `ptr UncheckedArray[int]` type.
]#

import unishell/allocator

const INTSIZE: int = sizeof(int)

type
  Offsets* = ptr UncheckedArray[int]
  OffsetsView* = object
    offsets: Offsets
    len: Natural

proc allocator(dest: var Offsets, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Offsets](hostAllocator(dest, size*INTSIZE, action))
proc allocator(customAllocator: HostAllocator, dest: var Offsets, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Offsets](customAllocator(dest, size*INTSIZE, action))

proc toOffsetsView*(offsets: Offsets, len: Natural): OffsetsView {.inline, raises: [].} =
  result.offsets = offsets
  result.len = len

proc overwriteWith*(dest: var OffsetsView, src: OffsetsView) {.raises: [].} =
  allocator(dest.offsets, dest.len, ZEROMEM)
  if (src.len != 0) and (src.offsets != nil):
    if (src.len >= dest.len):
      copyMem(dest.offsets, src.offsets, dest.len) # Silently truncates the array to fit
    else:
      copyMem(dest.offsets, src.offsets, src.len)
proc overwriteWith*(customAllocator: HostAllocator, dest: var OffsetsView, src: OffsetsView) {.raises: [].} =
  allocator(customAllocator, dest.offsets, dest.len, ZEROMEM)
  if (src.len != 0) and (src.offsets != nil):
    if (src.len >= dest.len):
      copyMem(dest.offsets, src.offsets, dest.len) # Silently truncates the array to fit
    else:
      copyMem(dest.offsets, src.offsets, src.len)

proc newOffsets*(len: Natural): Offsets {.raises: [].} =
  allocator(result, len, ALLOC)
proc newOffsets*(customAllocator: HostAllocator, len: Natural): Offsets {.raises: [].} =
  allocator(customAllocator, result, len, ALLOC)
proc newOffsets*(offsets: varargs[Natural, Natural]): Offsets {.raises: [].} =
  allocator(result, offsets.len(), ALLOC)
  for index, offset in offsets:
    result[index] = offset
proc newOffsets*(customAllocator: HostAllocator, offsets: varargs[Natural, Natural]): Offsets {.raises: [].} =
  allocator(customAllocator, result, offsets.len(), ALLOC)
  for index, offset in offsets:
    result[index] = offset

proc destroyOffsets*(offsets: var Offsets) {.raises: [].} =
  allocator(offsets, 0, DEALLOC)
proc destroyOffsets*(customAllocator: HostAllocator, offsets: var Offsets) {.raises: [].} =
  allocator(customAllocator, offsets, 0, DEALLOC)

proc `==`*(a, b: OffsetsView): bool {.inline, raises: [].} =
  if a.len == b.len:
    return equalMem(a.offsets, b.offsets, a.len)
  else:
    return false
  
proc `[]`*(view: OffsetsView, index: Natural): int {.raises: [].} =
  return view.offsets[index]

proc `[]=`*(view: OffsetsView, index: Natural, value: Natural) {.raises: [].} =
  view.offsets[index] = value

iterator items*(view: OffsetsView): int {.raises: [].} =
  for i in 0 ..< view.len:
    yield view.offsets[i]

proc find*(view: OffsetsView, item: int): int {.raises: [].} =
  result = 0
  for i in view:
    if i == item:
      return result
    inc(result)
  return -1

proc contains*(view: OffsetsView, item: int): bool {.raises: [].} =
  find(view, item) >= 0

proc len*(view: OffsetsView): int {.raises: [].} =
  result = view.len
