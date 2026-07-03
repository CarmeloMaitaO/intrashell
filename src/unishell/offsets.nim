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
