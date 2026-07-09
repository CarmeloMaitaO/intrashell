import unishell/allocator

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

proc dallocDarray*[T: AllowedTypes](dest: var Darray[T], size: Natural, allocator: HostAllocator = hostAllocator) {.raises: [].} =
  if size > 0:
    dest = allocator(dest, size, DEALLOCTOALLOC)
  else:
    dest = allocator(dest, size, DEALLOC)

proc newView*[T: AllowedTypes](src: Darray[T], len: Natural): View {.raises: [].} =
  result.view = src
  result.len = len

proc newView*[T: AllowedTypes](src: Darray[T], startIndex: Natural, len: Natural): View {.raises: [].} =
  result.view = cast[Darray[T]](addr src[startIndex])
  result.len = len

proc newView*[S: AllowedTypes; D: AllowedTypes](src: Darray[S], destType: D, startIndex: Natural, len: Natural): View {.raises: [].} =
  result.view = cast[Darray[D]](addr src[startIndex])
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

iterator items*[T: AllowedTypes](view: View[T]): int {.raises: [].} =
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
        aux &= $i
    return aux

proc overwriteWith*(view: View[char], str: string, allocator: HostAllocator = hostAllocator) {.raises: [].} =
  discard allocator(view.view, 0, ZEROMEM)
  if (view.len != 0) and (view.view != nil):
    if (str.len >= view.len):
      copyMem(addr view.view[0], addr str[0], view.len)
    else:
      copyMem(addr view.view[0], addr str[0], str.len())
