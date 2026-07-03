##[
 The `Data` object is meant to be an abstraction over the
 `ptr UncheckedArray[char]` type.
]##

import unishell/allocator

type
  Data* = ptr UncheckedArray[char]
  DataView* = object
    data: Data
    len: Natural

proc allocator(dest: var Data, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Data](hostAllocator(dest, size, action))
proc allocator(customAllocator: HostAllocator, dest: var Data, size: Natural, action: HostAllocatorAction) {.raises: [].} =
  dest = cast[Data](customAllocator(dest, size, action))

proc toDataView*(data: Data, len: Natural): DataView {.inline, raises: [].} =
  result.data = data
  result.len = len
proc toDataView*(str: string): DataView {.inline, raises: [].} =
  result.data = (try: cast[Data](addr str[0]) except Exception: nil)
  result.len = str.len()

proc overwriteWith*(dest: var DataView, src: DataView) {.inline, raises: [].} =
  allocator(dest.data, dest.len, ZEROMEM)
  if (src.len != 0) and (src.data != nil):
    if (src.len >= dest.len):
      copyMem(dest.data, src.data, dest.len) # Silently truncates the string to fit
    else:
      copyMem(dest.data, src.data, src.len)
proc overwriteWith*(customAllocator: HostAllocator, dest: var DataView, src: DataView) {.inline, raises: [].} =
  discard customAllocator(dest.data, dest.len, ZEROMEM)
  if (src.len != 0) and (src.data != nil):
    if (src.len >= dest.len):
      copyMem(dest.data, src.data, dest.len) # Silently truncates the string to fit
    else:
      copyMem(dest.data, src.data, src.len)
proc overwriteWith*(dest: var DataView, src: string) {.inline, raises: [].} =
  dest.overwriteWith(src.toDataView())
proc overwriteWith*(customAllocator: HostAllocator, dest: var DataView, src: string) {.inline, raises: [].} =
  overwriteWith(customAllocator, dest, src.toDataView())

proc newData*(len: Natural): Data {.raises: [].} =
  allocator(result, len, ALLOC)
proc newData*(customAllocator: HostAllocator, len: Natural): Data {.raises: [].} =
  allocator(customAllocator, result, len, ALLOC)
proc newData*(str: string): Data {.raises: [].} =
  var aux: DataView = str.toDataView()
  if (aux.len == 0) or (aux.data == nil):
    result = nil
  else:
    allocator(result, aux.len, ALLOC)
    copyMem(result, aux.data, aux.len)
proc newData*(customAllocator: HostAllocator, str: string): Data {.raises: [].} =
  var aux: DataView = str.toDataView()
  if (aux.len == 0) or (aux.data == nil):
    result = nil
  else:
    allocator(customAllocator, result, aux.len, ALLOC)
    copyMem(result, aux.data, aux.len)

proc destroyData*(data: var Data) {.raises: [].} =
  allocator(data, 0, DEALLOC)
proc destroyData*(customAllocator: HostAllocator, data: var Data) {.raises: [].} =
  allocator(customAllocator, data, 0, DEALLOC)

proc `$`*(view: DataView): string {.inline, raises: [].} =
  if (view.len == 0) or (view.data == nil):
    result = ""
  else:
    result = newString(view.len)
    copyMem(addr result[0], addr view.data[0], view.len)

proc `==`*(a: DataView, b: Data): bool {.inline, raises: [].} =
  return a.data == b
proc `==`*(a: Data, b: DataView): bool {.inline, raises: [].} =
  return a == b.data
proc `==`*(a, b: DataView): bool {.inline, raises: [].} =
  if a.len == b.len:
    return equalMem(a.data, b.data, a.len)
  else:
    return false
proc `==`*(a: DataView, b: string): bool {.inline, raises: [].} =
  return (a == b.toDataView())
proc `==`*(a: string, b: DataView): bool {.inline, raises: [].} =
  return (a.toDataView() == b)

proc `[]`*(view: DataView, index: Natural): char {.raises: [].} =
  return view.data[index]

iterator items*(view: Dataview): char {.raises: [].} =
  for i in 0 ..< view.len:
    yield view.data[i]

proc find*(view: Dataview, item: char): int {.raises: [].} =
  result = 0
  for i in view:
    if i == item:
      return result
    inc(result)
  return -1

proc contains*(view: DataView, item: char): bool {.raises: [].} =
  find(view, item) >= 0

proc len*(view: DataView): int {.raises: [].} =
  result = view.len
