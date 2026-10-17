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
# BUFFER
# =============================================================================
##[
  This module provides an opaque fat pointer called `Buffer`, which is a flat
  memory structure, so it can be passed across memory boundaries between the
  main executable and it's shared/dynamic/runtime-loaded libraries; without
  worrying about matching the memory allocator, garbage collector or language.

  **THIS STRUCTURE IS MEANT TO BE:**
  - AN OPAQUE POINTER
  - MODIFIED ONLY BY ITS METHODS
  - MANAGED BY THE ALLOCATOR PROVIDED IN THE INTRASHELL INSTANCE
  - USED IN A SYNCHRONOUS MANNER
  - COMPATIBLE WITH C99
  **WITH THE GOAL OF BEING:**
  - LANGUAGE INDEPENDENT (IMPORTABLE BY ANY LANGUAGE WITH SUPPORT FOR C FFI)
  - PLATFORM INDEPENDENT (ONLY REQUIRE A CPU THAT SUPPORTS A 32 BIT INTEGER
    SIZE)

  ```nim
  # EXAMPLE:
  ```
]##

import intrashell/allocator

type
  ExitCodes*  {.size: sizeOf(uint32).} = enum
    ##[
      The exit code of any dispatch call. It can either be `OK`, which means no
      errors, or any of the other specific error types provided. This
      enumeration exists to make binding to other languages easier, as they
      won't share the same exception handling mechanism, and therefore should
      handle this matter as they see fit based on the returned value.
    ]##
    OK                = 0,
    UnknownCommand    = 1,
    WrongParameters   = 2,
    CommandFailed     = 3
  BufferObj* = tuple
    ##[
      A flat structure for transmitting data across memory boundaries. It's
      structured like this:

      | **FIELD** | Exit Code |     Size     |   Data   |
      | --------- | --------- | ------------ | -------- |
      | **BYTES** |    4      |      4       | variable |

      - Exit Code: indicates the final status of the call.
      - Size: the size in bytes of the Buffer.
      - Data: the contained data.
    ]##
    exitCode: ExitCodes
    size: uint32
    data: UncheckedArray[byte]
  Buffer* = ptr BufferObj

const
  baseBufferSize: uint32 = cast[uint32](sizeOf(BufferObj))

proc newBuffer*(
  allocator: Allocator,
  size: uint32
): Buffer {.cdecl, exportc, raises: [].} =
  return cast[Buffer](
    allocator(nil, ALLOC0, size, nil)
  )

proc destroyBuffer*(
  allocator: Allocator,
  buffer: Buffer
) {.cdecl, exportc, raises: [].} =
  discard allocator(buffer, DEALLOC, 0u32, nil)
