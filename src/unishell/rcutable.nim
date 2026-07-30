##[
  This module provides a concurrent hash table based on RCU, that relies
  on Nim's ARC/ORC/Atomic ARC reference counting to deallocate the old
  data, called `RcuTable`.

  The `RcuTable` object uses an array that holds the references to two hash
  tables, an atomic integer that represents the index of the active table and
  a single lock that is only used by writers to avoid clashing with each other.
  This means that one table should be active and contain actual information,
  while the other, the inactive one, will be reserved to, on writes, perform a
  copy of the current active table, modify it, and become the active one. The
  specific behaviour is the following:

  - Writers: copy the contents of the active table on the inactive table, modify
    the copy, swap the value of the active index to change the active table,
    and lastly create a new hash table, which reference will now occupy the
    inactive slot.
  - Readers: get the reference of the active table, which increments its counter
    in Nim's memory manager, and perform the desired read; this prevents the
    deallocation of the table while a write is being performed or has already
    happened, as the table will only be deallocated after all readers have
    finished and the counter for the reference reaches zero.

  *THE `RcuTable` OBJECT IS NOT READY TO HANDLE COPIES, SO AVOID DUPLICATING IT*

  Example use:

  ```nim
  var x: RcuTableRef = newRcuTable[int, string]

  x.modify:
    x[slot, 0] = "Hello "
    x[slot, 1] = "World!"

  echo x[0], x[1] # "Hello World!"
  ```
]##
when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  {.error: "rcutable.nim requires to be compiled with --mm:arc, --mm:orc or --mm:atomicArc".}
import std/[
  tables,
  atomics,
  locks
]
type
  RcuTable*[K, V] = object
    ##[
      The base object that holds the array with the references to the hash
      tables, the atomic integer that holds the active index of the array,
      and the lock that will be used by the writers to prevent clashing with
      each other.

      Use `RcuTableRef` instead.
    ]##
    slots: array[2, TableRef[K, V]]
    activeSlot: Atomic[int]
    writerLock: Lock
  RcuTableRef*[K, V] = ref RcuTable[K, V]
    ##[
      A reference to a `RcuTable` object and also the intended object to use
      in this module.
    ]##

proc newRcuTable*[K, V](initialsize = defaultInitialSize): RcuTableRef[K, V] =
  ##[
    Creates a new `RcuTable` and returns a reference to it. Example:

    ```nim
    var x: RcuTableRef = newRcuTable[int, string]()
    # The first type is the key, and the second one the value
    ```
  ]##
  new(result)
  result.slots[0] = newTable[K, V](initialSize)
  result.slots[1] = newTable[K, V](initialSize)
  result.activeSlot.store(0b00)
  result.writerLock.initLock()

proc getActiveSlot*[K, V](table: RcuTableRef[K, V]): int {.inline.} =
  ## Returns the index of the active table
  result = table.activeSlot.load(moAcquire)

proc getInactiveSlot*[K, V](table: RcuTableRef[K, V]): int {.inline.} =
  ## Returns the index of the inactive table
  result = (table.activeSlot.load(moAcquire) xor 0b01)

proc setActiveSlot*[K, V](table: RcuTableRef[K, V], newValue: int) {.inline.} =
  ## Sets the index of the active table
  table.activeSlot.store(newValue, moRelease)

proc len*[K, V](table: RcuTableRef[K, V]): int =
  ## Returns the number of elements inside the selected table
  var targetTable: TableRef[K, V] = table.slots[table.getActiveSlot()]
  result = targetTable.len()

proc `[]`*[K, V](table: RcuTableRef[K, V], key: K): V =
  ## Returns the value of the given key of the selected table
  var targetTable: TableRef[K, V] = table.slots[table.getActiveSlot()]
  result = targetTable[key]

proc `[]`*[K, V](table: RcuTableRef[K, V], slot: int, key: K): V =
  ## Returns the value of the given key of the selected table
  var targetTable: TableRef[K, V] = table.slots[slot]
  result = targetTable[key]

proc `[]=`*[K, V](table: RcuTableRef[K, V], slot: int, key: K, value: sink V) =
  ## Sets the value of the given key of the selected table
  var targetTable: TableRef[K, V] = table.slots[slot]
  targetTable[key] = value

proc hasKey*[K, V](table: RcuTableRef[K, V], key: K): bool =
  ## Checks if the key is present in the selected table
  var targetTable: TableRef[K, V] = table.slots[table.getActiveSlot()]
  result = targetTable.hasKey(key)

proc contains*[K, V](table: RcuTableRef[K, V], key: K): bool {.inline.} =
  ## Alias for `hasKey`
  result = table.hasKey(key)

proc del*[K, V](table: RcuTableRef[K, V], slot: int, key: K) =
  ## Deletes the given key of the selected table
  var targetTable: TableRef[K, V] = table.slots[slot]
  targetTable.del(key)

proc clear*[K, V](table: RcuTableRef[K, V], slot: int, initialSize = defaultInitialSize) =
  ## Replaces the (reference to the) selected table with a new one
  table.slots[slot] = newTable[K, V](initialSize)

proc commit*[K, V](table: RcuTableRef[K, V]) =
  ## Swaps the active table, and calls `clear` on the inactive one
  table.setActiveSlot(table.getInactiveSlot)
  table.clear(table.getInactiveSlot)

# Modifications go to inactive slot and it is only activated once 'commit' is called
template modify*(table: RcuTableRef, body: untyped) =
  ##[
    This template is the intended way of writing modifications to the
    table, as it automatically handles the lock, copy of the data,  and call
    `commit` after finishing. It also injects a variable called `slot` which
    should be used as the `slot` parameter of all procedures that accept it.
    Example:

    ```nim
    var x: RcuTableRef = newRcuTable[int, string]
    x.modify:
      x[slot, 0] = "Hello "
      x[slot, 1] = "World!"
    ```
  ]##
  withLock(table.writerLock):
    let
      activeSlot: int = table.getActiveSlot()
      inactiveSlot: int = table.getInactiveSlot()
      slot {.inject.} = inactiveSlot
    (table.slots[inactiveSlot])[] = (table.slots[activeSlot])[]
    try:
      body
    finally:
      table.commit()
