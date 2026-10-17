#[
  Copyright 2026 Carmelo Augusto Maita Orlando

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]#
# =============================================================================
# ALLOCATOR
# =============================================================================
##[
 This is the allocator procedure; its function is to make Intrashell's allocator
 available to both the modules and the host.
]##

type
  AllocatorAction* = enum
    ##[
      Enumeration for the possible actions that the allocator can perform:

      0. `ALLOC`: allocates a new block of memory.
      1. `DEALLOC`: deallocates a block of memory.
      2. `REALLOC`: reallocates the memory from one block to another.
      3. `ZEROMEM`: zeroes a given block of memory.
      4. `COPYMEM`: copies one block of memory into another.
      5. `ALLOC0`: allocates a new block of memory and initializes it to `0`.
    ]##
    ALLOC    = 0,
    DEALLOC  = 1,
    REALLOC  = 2,
    ZEROMEM  = 3,
    COPYMEM  = 4,
    ALLOC0   = 5
  Allocator* = proc(
    dest: pointer,
    action: AllocatorAction,
    size: uint32 = 0,
    src: pointer = nil
  ): pointer {.raises: [].}
    ##[
      The signature for the allocator. Rather than a tuple containing pointers
      to the individual allocator functions, it is a single procedure for the
      sake of simplifying the binding process. It also helps with performance,
      as it avoids pointer-chasing.
    ]##

proc allocator*(
  dest: pointer,
  action: AllocatorAction,
  size: uint32 = 0,
  src: pointer = nil
): pointer {.raises: [].} =
  ##[
    The allocator procedure of Intrashell. Its supported actions, their
    behaviour and their accepted parameters are:

    0. ALLOC(size): allocates a new memory block of `size` bytes.
    1. DEALLOC(dest): deallocates a given memory block.
    2. REALLOC(dest, size): creates a new memory block of the given `size` and
       copies the previous block into it. Deallocates the previous block after.
    3. ZEROMEM(dest, size): zeroes a block of memory
    4. COPYMEM(dest, size, src): copies `size` bytes from a memory block into
       another.
    5. ALLOC0(size): same as `ALLOC` but zeroes the memory block.
  ]##
  result = dest
  case action
  of ALLOC, ALLOC0:
    if (action == ALLOC):
      result = alloc(size)
    else:
      result = alloc0(size)
  of DEALLOC:
    dealloc(dest)
    result = nil
  of REALLOC:
    result = realloc(dest, size)
  of ZEROMEM:
    zeroMem(dest, size)
    result = dest
  of COPYMEM:
    copyMem(dest, src, size)
    result = dest
