import intrashell/allocator
export allocator

##[
  This is the helper module for allocating memory using the Allocator module
  creating views to it. Given that the Buffer type only supports numbers and
  characters, this module was made to only be able to manage those types.
]##

type
  AllowedTypes* = (char or Natural)
  Darray*[T: AllowedTypes] = ptr UncheckedArray[T]
  View*[T: AllowedTypes] = object
    ##[
      A view of the data inside dynamic array structure. It avoids copying or
      moving the data inside so any changes made are directly applied to
      the specific segment of the array structure.
    ]##
    view: Darray[T]
    len: Natural

proc isNil*[T: AllowedTypes](view: View[T]): bool {.raises: [].} =
  return view.view == true

proc dallocDarray*[T: AllowedTypes](dest: var Darray[T], size: Natural, allocator: HostAllocator = hostAllocator) {.raises: [].} =
  when T is Natural:
    let totalSize: Natural = size*sizeOf(int)
  when T is char:
    let totalSize: Natural = size
  if size > 0:
    dest = cast[Darray[T]](allocator(dest, totalSize, DEALLOCTOALLOC))
  else:
    dest = cast[Darray[T]](allocator(dest, totalSize, DEALLOC))

proc newView*[T: AllowedTypes](src: Darray[T], len: Natural): View[T] {.raises: [].} =
  result.view = src
  result.len = len

proc newView*[T: AllowedTypes](src: View[T], len: Natural): View[T] {.raises: [].} =
  result.view = src.view
  result.len = len

proc newView*[T: AllowedTypes](src: Darray[T], startIndex: Natural, len: Natural): View[T] {.raises: [].} =
  result.view = cast[Darray[T]](addr src[startIndex])
  result.len = len

proc newView*[T: AllowedTypes](src: View[T], startIndex: Natural, len: Natural): View[T] {.raises: [].} =
  result.view = cast[Darray[T]](addr src.view[startIndex])
  result.len = len


proc newAlternateView*(src: Darray[char], len: Natural): View[Natural] {.raises: [].} =
  result.view = cast[Darray[Natural]](addr src[0])
  result.len = len
  
proc newAlternateView*(src: Darray[char], startIndex: Natural, len: Natural): View[Natural] {.raises: [].} =
  result.view = cast[Darray[Natural]](addr src[startIndex])
  result.len = len

proc newAlternateView*(src: Darray[Natural], startIndex: Natural, len: Natural): View[char] {.raises: [].} =
  result.view = cast[Darray[char]](addr src[startIndex])
  result.len = len

proc newAlternateView*(src: Darray[Natural], len: Natural): View[char] {.raises: [].} =
  result.view = cast[Darray[char]](addr src[0])
  result.len = len

proc len*[T: AllowedTypes](view: View[T]): int {.raises: [].} =
  return view.len

proc `==`*[T: AllowedTypes](a: View[T], b: View[T]): bool {.raises: [].} =
  if a.len == b.len:
    if a.view == b.view:
      return true
    else:
      return equalMem(a.view, b.view, a.len)
  else:
    return false

proc `[]`*[T: AllowedTypes](view: View[T], index: Natural): T {.raises: [].} =
  return view.view[index]

proc `[]=`*[T: AllowedTypes](view: var View[T], index: Natural, value: T) {.raises: [].} =
  view.view[index] = value

iterator items*[T: AllowedTypes](view: View[T]): T {.raises: [].} =
  for i in 0 ..< view.len:
    yield view.view[i]

proc find*[T: AllowedTypes](view: View[T], item: T): int {.raises: [].} =
  result = 0
  for i in view:
    if i == item:
      return result
    inc(result)
  return -1

proc contains*[T: AllowedTypes](view: View[T], item: T): bool {.raises: [].} =
  find(view, item) >= 0

proc `$`*[T: AllowedTypes](view: View[T]): string {.raises: [].} =
  var aux: string = ""
  if (view.len == 0) or (view.view == nil):
    return aux
  else:
    when T is char:
      aux = newString(view.len)
      copyMem(addr aux[0], addr view.view[0], view.len)
    when T is Natural:
      for i in view:
        aux &= $i & " "
    return aux

proc overwriteWith*(view: View[char], str: string, allocator: HostAllocator = hostAllocator) {.raises: [].} =
  discard allocator(view.view, 0, ZEROMEM)
  if (view.len != 0) and (view.view != nil):
    if (str.len >= view.len):
      copyMem(addr view.view[0], addr str[0], view.len)
    else:
      copyMem(addr view.view[0], addr str[0], str.len())
