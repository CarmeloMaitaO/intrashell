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

import std/strutils

type
  BufferError* = object of CatchableError # The error type of this module

# =============================================================================
# BUFFER OBJECT
# =============================================================================

#[
 The `Buffer` object is meant to simulate a `seq[string]` type of Nim inside a
 single, flat structure
]#

type
  Buffer* = object
    data: Data       ## Single block of raw concatenated string data
    offsets: Offsets ## Offsets to the end of each string. Last one also indicates capacity
    len: Natural     ## Number of strings packed inside

 iterator items*(buffer: Buffer): DataView {.raises: [].} =
   ##[
     Iterates over a `Buffer` and returns a view for each contained string.
 
     It is necessary for the `find` procedure and the `in` operator.
   ]##
   for i in 0 ..< buffer.len:
     yield buffer.toDataView(i)
 
 proc find*(buffer: Buffer, item: string): int {.inline, raises: [].} =
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
 
 proc contains*(buffer: Buffer, item: string): bool {.inline, raises: [].} =
   ##[
     Iterates over a `Buffer` object and returns `true` if the provided
     string is inside said `Buffer`.
     
     It is necessary for the `in` operator.
   ]##
   find(buffer, item) >= 0
 
 proc len*(buf: Buffer): int {.inline, raises: [].} =
   ##[
     Returns the number of strings contained within the buffer. Example:
 
     ```nim
     var x: Buffer = createBuffer(@["1", "2", "3"])
     echo $x.len() # "3"
     ```
   ]##
   result = buf.len
 
 proc `[]`*(buffer: Buffer, index: int): DataView {.raises: [].} =
   ##[
     Returns a view to the string contained within the provided index. Example:
 
     ```nim
     var x: Buffer = createBuffer(@["I am a string!"])
     echo $x[0] # "I am a string"
     ```
   ]##
   result = buffer.toDataView(index)
 
 proc toSeq*(buffer: Buffer): seq[string] {.raises: [].} =
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
 
