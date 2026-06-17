type
  HostAllocatorAction* = enum
    ALLOC = 0,
    DEALLOC = 1,
    DEALLOCTOALLOC = 2,
    ZEROMEM = 3
  HostAllocator* = proc(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl, raises: [].}

proc hostAllocator*(address: pointer = nil, newsize: Natural = 0, action: HostAllocatorAction): pointer {.cdecl, raises: [].} =
  case action
  of ALLOC:
    if newsize > 0:
      return alloc0(newsize)
    else:
      return nil
  of DEALLOC:
    if address != nil:
      dealloc(address)
    return nil
  of DEALLOCTOALLOC:
    if address != nil:
      dealloc(address)
    if newsize > 0:
      return alloc0(newsize)
    else:
      return nil
  of ZEROMEM:
    if (address != nil) and (newsize != 0):
      zeroMem(address, newsize)
    return address

