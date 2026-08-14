import intrashell/allocator

var
  aux: ptr UncheckedArray[char] = nil
  auxZero: char = cast[char](0)

proc auxproc(value: Natural, action: HostAllocatorAction) =
  aux = cast[ptr UncheckedArray[char]](
    hostAllocator(aux, value, action)
  )

auxproc(1, ALLOC)

assert aux != nil

aux[0] = 'a'

assert aux[0] == 'a'

auxproc(1, ZEROMEM)

assert aux[0] == auxZero

auxproc(2, DEALLOCTOALLOC)

aux[0] = 'b'
aux[1] = 'c'

assert aux[0] == 'b'
assert aux[1] == 'c'

auxproc(2, ZEROMEM)

assert aux[0] == auxZero
assert aux[1] == auxZero
