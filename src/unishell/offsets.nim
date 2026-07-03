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
    index: Natural

proc allocator(dest: var Offsets, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Offsets](hostAllocator(dest, size*INTSIZE, action))
proc allocator(customAllocator: HostAllocator, dest: var Offsets, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Offsets](customAllocator(dest, size*INTSIZE, action))

proc toOffsetsView*(offsets: Offsets, len: Natural): OffsetsView {.inline, raises: [].} =
  result.offsets = offsets
  result.len = len

proc overwriteWith*(dest: var Offsets)
