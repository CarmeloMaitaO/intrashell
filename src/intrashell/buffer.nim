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
    REALLOC = 2,
    ZEROMEM = 3
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
  of REALLOC:
    if (address != nil):
      if newsize > 0:
        realloc(address, newsize)
      else:
        dealloc(address)
        result = nil
    else:
      result = alloc(newsize)
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

template getNumbers(data: varargs[string, `$`]): seq[int] =
  #[
    Each number represents:
    0. Total number of elements within the structure
    1. Sum of the sizes in bytes of each element within the structure
    [2, n]. Total size in bytes of each element 
  ]#
  result = @[0, 0]
  for index, element in data:
    result[0] += 1
    result[1] += element.len()
    result.add(element.len())

template allocateFor(ma: allocator, data: seq[int]): pointer =
  if data[0] == 0:
    result = nil
  else:
    result = result.ma(
      ALLOC,
      (
        (sizeOf(int)*2) + # Number of elements & offset to offset list
        data[1] + # Total size of a packed array with all the elements
        (sizeOf(int)*data[0]) # An offset for every element
      )
    )

template copyData(
  address: pointer,
  data: varargs[string, `$`],
  metadata: seq[int]
) =
  var aux: ptr UncheckedArray[int]
  if address != nil:
    aux = cast[ptr UncheckedArray[int]](address)
    aux[0] = metadata[0]
    aux[1] = metadata[1] + sizeOf(int)*2
    aux = cast[ptr UncheckedArray[int]](address + aux[1])
    for index in 2..metadata.high():
      aux[index-2] = metadata[index] # check and fix. This holds bytesize of elements, not offsets
# =============================================================================
# BUFFER OBJECT
# =============================================================================

import intrashell/view
export allocator, view

type
  Buffer* = pointer
    ##[
      Simulates a `seq[string]` in a flat structure. It is structured in the following way:

      |     Length   |          Offsets           |               Data         |
      | ------------ | -------------------------- | -------------------------- |
      | sizeOf(int)  | sizeOf(int) * (Length + 1) | max(Offsets) - min(Offsets)

      - Length: indicates the number of contained strings.
      - Offsets: indexes that mark the end of each string.
      - Data: The contained strings.
    ]##

proc newBuffer*(buffer: var Buffer, strings: seq[string], allocator: HostAllocator = hostAllocator) {.raises: [].} =
  var
    len: Natural = strings.len()
    sizeOfOffsets: Natural = (2 + len) * sizeOf(int) # Includes lenght field and start offset
    sizeOfData: Natural = 0
    sizeOfBuffer: Natural = 0
    counter1: Natural = 0
    counter2: Natural = 0
    auxView1: View[Natural]
    auxView2: View[char]
  for i in strings:
    sizeOfData += i.len()
  sizeOfBuffer = sizeOfOffsets + sizeOfData
  buffer.dallocDarray(sizeOfBuffer, allocator)
  if len > 0:
    auxView1 = buffer.newAlternateView(0, sizeOfOffsets)
    auxView1[0] = len # Number of strings within the buffer
    auxView1[1] = sizeOfOffsets # Offset to the first character byte in the buffer
    counter1 = sizeOfOffsets # Current offset
    counter2 = 2 # Current index
    for i in strings:
      counter1 += i.len()
      auxView1[counter2] = counter1
      counter2.inc()
    auxView1 = auxView1.newView(1, len)
    for i in 0 ..< auxView1.len(): # TO FIX
      auxView2 = buffer.newView(auxView1[i], auxView1[i+1] - auxView1[i])
      auxView2.overwriteWith(strings[i], allocator)

