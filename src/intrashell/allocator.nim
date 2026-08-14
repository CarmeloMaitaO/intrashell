# =============================================================================
# EXTERNAL ALLOCATOR
# =============================================================================

##[
 This is the allocator procedure; it's function is to make the host's allocator
 available to modules, so the memory used by the module is allocated and freed
 in the host.
 
 Currently, it is implemented as a case statement in order to make it easier
 to export to other languages. It might be turned into a VTable with pointers
 to the respective memory management procedures later on.
]##

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
