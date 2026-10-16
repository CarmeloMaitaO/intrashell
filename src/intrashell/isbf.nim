##[
  This module provides an implementation of the IntraShell Binary Format (ISBF)
]##

# =============================================================================
# TYPES
# =============================================================================

type
  FormatHeader* = tuple
    magicBytes: uint32
  BaseDataTypes* {.size: S8.} = enum
    ##[
      It is meant to tell what kind of data is contained within it so it can be
      properly extracted and parsed.
    ]##
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
    FLOAT64  = 10,
    STRING   = 19,
    BLOB     = 20,
    OBJECT   = 21
