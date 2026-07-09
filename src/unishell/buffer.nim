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

# =============================================================================
# BUFFER OBJECT
# =============================================================================

#[
 The `Buffer` object is meant to simulate a `seq[string]` type of Nim inside a
 single, flat structure
]#

type
  Buffer* = ptr UncheckedArray[char]
    ##[
      Simulates a `seq[string]` in a flat structure. It is structured in the following way:

      Starting index

      0                        \ Length (number of contained strings)
      sizeOf(int)              \ Offsets (indexes that mark the end of the string).
                               \ And additional offset is put at the start to mark the
                               \ first index for the data part
      sizeOf(int)*(Length + 1) \ Data. Starts after the length and offsets fields
    ]##
  BufferView* = object
    ##[
      A unified view for all the strings contained within the Buffer. It uses
      a sequence of character views to point to the actual strings.
    ]##
    strings: seq[View[char]]
    len: Natural
    cap: Natural

proc deallocBuffer*(buffer: var Buffer, allocator: HostAllocator) {.raises: [].} =
  discard allocator(buffer, 0, DEALLOC)

proc deallocToAllocBuffer*(buffer: var Buffer, allocator: HostAllocator, size: Natural) {.raises: [].} =
  discard allocator(buffer, size, DEALLOCTOALLOC)

proc newView*[T](address: pointer, kind: T, len: Natural): View[T] {.raises: [].} =
  result.view = cast[ptr UncheckedArray[kind]](address)
  result.len = len

proc newView*[T](buffer: var Buffer, kind: T, startIndex: Natural, endIndex: Natural): View[T] {.raises: [].} =
  result = newView(
    addr buffer[startIndex], # Address of the starting index
    kind,
    (endIndex-startIndex)+1  # Length = difference between indexes + starting index
  )

proc newBufferView*(buffer: var Buffer): BufferView {.raises: [].} =
  var
    auxViewNumeric: View[int]
    auxViewChar: View[char]
  if buffer != nil:
    auxViewNumeric = buffer.newView[int](0, 0)
    auxViewNumeric[0]
  else:
    result.len = 0
    result.cap = 0

proc getOffsetsSize*(len: Natural): Natural {.raise: [].} =
  # ((length field + Start offset) + number of strings/offsets) * size of an integer
  result = (2 + len)*(sizeOf(int))

proc getDataSize*(strings: seq[string]): Natural {.raises: [].} =
  result = 0
  for i in strings:
    result += i.len()

proc getBufferSize*(offsetsSize: Natural, dataSize: Natural): Natural {.raises: [].} =
  result = 0
  result += offsetsSize # The offsets field
  result += dataSize    # The data field

proc getOffsetsView*(buffer: var Buffer, len: Natural): OffsetsView {.raises: [].} =
  # This one is used to populate the fields on creation
  result.offsets = cast[ptr UncheckedArray[Natural]](buffer)
  result.len = len+2 # len + (length field + start offset)

proc getOffsetsView*(buffer: var Buffer): OffsetsView {.raises: [].} =
  # This one is used to get only the offsets of the buffer
  result.offsets = cast[ptr UncheckedArray[Natural]](buffer)
  if result.offsets != nil:
    result.len = result.offsets[0]
  else:
    result.len = 0
  if result.len > 0:
    result.offsets = cast[ptr UncheckedArray[Natural]](
      addr result.offsets[1]
    )
  else:
    result.offsets = nil

proc getDataView*(buffer: var Buffer, view: OffsetsView, index: Natural): DataView {.raises: [].} =
  let trueIndex: int = index+1
  result.data = cast[ptr UncheckedArray[char]](addr buffer[view.offsets[index]])
  result.len = view.offsets[trueIndex] + 1 - view.offsets[index]

proc getDataViews*(buffer: var Buffer): seq[DataView] {.raises: [].} =
  var auxOffsetsView: OffsetsView = buffer.getOffsetsView()

proc populateOffsets*(view: var OffsetsView, len: Natural, start: Natural, strings: seq[string]) {.raises: [].} =
  view.offsets[0] = len
  var aux: Natural = start
  for index, item in strings:
    view.offsets[index+1] = aux
    aux += item.len()

proc newBuffer*(buffer: var Buffer, allocator: HostAllocator, strings: seq[strings]) {.raises: [].} =
  let
    len: Natural = strings.len()
    sizeOfOffsets: Natural = getOffsetsSize(len)
    sizeOfData: Natural = getDataSize(strings)
    sizeOfBuffer: Natural = getBufferSize(sizeOfOffsets, sizeOfData)
  buffer.deallocToAllocBuffer(allocator, sizeOfBuffer)
  var auxOffsetsView: OffsetsView
  if len > 0:
    auxOffsetsView = buffer.getOffsetsView(len)
    auxOffsetsView.populateOffsets(len, sizeOfOffsets, strings)
    
