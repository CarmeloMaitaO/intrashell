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
# BUFFER OBJECT
# =============================================================================

import intrashell/view
export allocator, view

type
  Buffer* = Darray[char]
    ##[
      Simulates a `seq[string]` in a flat structure. It is structured in the following way:

      |     Length   |          Offsets           |               Data         |
      | ------------ | -------------------------- | -------------------------- |
      | sizeOf(int)  | sizeOf(int) * (Length + 1) | max(Offsets) - min(Offsets)

      - Length: indicates the number of contained strings.
      - Offsets: indexes that mark the end of each string.
      - Data: The contained strings.
    ]##
  BufferView* = object
    ##[
      A unified view for all the strings contained within the Buffer. It uses
      a sequence of character views to point to the actual strings.
    ]##
    len: Natural
    offsets: View[Natural]
    cap: Natural
    strings: seq[View[char]]

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

proc newBufferView*(buffer: Buffer): BufferView {.raises: [].} =
  if not (buffer.isNil()):
    result.offsets = buffer.newAlternateView(1)
    result.len = result.offsets[0]
    if result.len > 0:
      result.offsets = buffer.newAlternateView(sizeOf(int), result.len)
      result.cap = result.offsets[result.len-1]-1
  for i in 0 ..< result.offsets.len():
    result.strings.add(
      buffer.newView(
        result.offsets[i],
        result.offsets[i+1] - result.offsets[i]
      )
    )

proc `[]`*(view: BufferView, index: Natural): View[char] {.raises: [].} =
  return view.strings[index]

iterator items*(view: BufferView): View[char] {.raises: [].} =
  for i in view.strings:
    yield i

proc find*(view: BufferView, item: View[char]): int {.raises: [].} =
  result = 0
  for i in view:
    if i == item:
      return result
    inc(result)
  return -1

proc find*(view: BufferView, item: string): int {.raises: [].} =
  result = 0
  for i in view:
    if $i == item:
      return result
    inc(result)
  return -1

proc contains*(view: BufferView, item: View[char]): bool {.raises: []} =
  find(view, item) >= 0

proc contains*(view: BufferView, item: string): bool {.raises: []} =
  find(view, item) >= 0

proc toSeq*(view: BufferView): seq[string] {.raises: [].} =
  result = @[]
  for i in view:
    result.add($i)
