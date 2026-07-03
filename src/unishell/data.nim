##[
 The `Data` object is meant to be an abstraction over the
 `ptr UncheckedArray[char]` type.
]##

import unishell/allocator

type
  Data = ptr UncheckedArray[char]
  DataView* = object
    data: Data
    len: Natural

proc allocator(dest: var Data, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Data](
    hostAllocator(dest, size, action)
  )
proc allocator(customAllocator: HostAllocator, dest: var Data, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Data](
    customAllocator(dest, size, action)
  )

proc newData(len: Natural): Data {.raises: [].} =
  result = allocator(result, len, ALLOC)
proc newData(customAllocator: HostAllocator, len: Natural): Data {.raises: [].} =
  result = customAllocator(result, len, ALLOC)

proc destroyData(data: var Data) {.raises: [].} =
  allocator(data, 0, DEALLOC)
proc destroyData(customAllocator: HostAllocator, data: var Data) {.raises: [].} =
  customAllocator(data, 0, DEALLOC)

proc toDataView(data: Data, len: Natural): DataView {.inline, raises: [].} =
  result.data = data
  result.len = len

proc toDataView(str: string): DataView {.inline, raises: [].} =
  result.data = (try: cast[Data](addr str[0]) except Exception: nil)
  result.len = str.len()

proc `$`*(view: DataView): string {.inline, raises: [].} =
  if (view.len == 0) or (view.data == nil):
    result = ""
  else:
    result = newString(view.len)
    copyMem(addr result[0], addr view.data[0], view.len)

proc newData(str: string): Data {.raises: [].} =
  var aux: DataView = str.toDataView()
  if (aux.len == 0) or (aux.data == nil):
    result = nil
  else:
    result = cast[Data](
      hostAllocator(
        addr result,
        aux.len,
        ALLOC
      )
    )
    copyMem(result, aux.data, aux.len)

proc overwriteWith(dest: var DataView, src: string) {.inline, raises: [].} =
  var aux: DataView = src.toDataView()
  discard hostAllocator(dest.data, dest.len, ZEROMEM)
  copyMem(dest.data, aux.data, dest.len) # Silently truncates the string to fit

proc `==`*(a, b: DataView): bool {.inline, raises: [].} =
  if a.len == b.len:
    return equalMem(a.data, b.data, a.len)
  else:
    return false
  
proc `==`*(a: DataView, b: string): bool {.inline, raises: [].} =
  return (a == b.toDataView())

proc `[]`*(view: DataView, index: Natural): char {.raises: [].} =
  return view.data[index]

