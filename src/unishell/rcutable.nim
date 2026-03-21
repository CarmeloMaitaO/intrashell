import std/[
  tables,
  atomics,
  locks
]
type
  RcuTable*[K, V] = object
    slots: array[2, TableRef[K, V]]
    activeSlot: Atomic[int]
    writerLock: Lock
  RcuTableRef*[K, V] = ref RcuTable[K, V]

proc newRcuTable*[K, V](initialsize = defaultInitialSize): RcuTableRef[K, V] =
  new(result)
  result.slots[0] = newTable[K, V](initialSize)
  result.slots[1] = newTable[K, V](initialSize)
  result.activeSlot.store(uint(0b00))
  result.writerLock.initLock()

proc getActiveSlot*(table: RcuTableRef[K, V]): int =
  result = table.activeSlot.load(moAcquire)

proc getInactiveSlot*(table: RcuTableRef[K, V]): int =
  result = (table.activeSlot.load(moAcquire) xor 0b01)

proc setActiveSlot*(table: RcuTableRef[K, V], newValue: int) =
  table.activeSlot.store(newValue, moRelease)

proc commit*[K, V](table: RcuTableRef[K, V]) =
  table.setActiveSlot(table.getInactiveSlot)
  table.clear(table.getInactiveSlot)

proc len*[K, V](table: RcuTableRef[K, V], slot: int): int =
  var targetTable: TableRef[K, V] = table.slots[slot]
  result = targetTable.len()

proc `[]`*[K, V](table: RcuTableRef[K, V], slot: int, key: K): var V =
  var targetTable: TableRef[K, V] = table.slots[slot]
  result = targetTable[key]

proc `[]=`*[K, V](table: RcuTableRef[K, V], slot: int, key: K, value: V) =
  var targetTable: TableRef[K, V] = table.slots[slot]
  targetTable[key] = value

proc hasKey*[K, V](table: RcuTableRef[K, V], slot: int, key: K): bool =
  var targetTable: TableRef[K, V] = table.slots[slot]
  result = targetTable.hasKey(key)

proc contains*[K, V](table: RcuTableRef[K, V], slot: int, key: K): bool =
  result = table.hasKey(slot, key)

proc del*[K, V](table: RcuTableRef[K, V], slot: int, key: K) =
  var targetTable: TableRef[K, V] = table.slots[slot]
  targetTable.del(key)

proc clear*[K, V](table: RcuTableRef[K, V], slot: int, initialSize = defaultInitialSize) =
  table.slots[slot] = newTable[K, V](initialSize)

# Modifications go to inactive slot and it is only activated once 'commit' is called
template modify*(table: RcuTableRef, body: untyped) =
  withLock(table.writerLock):
    try:
      var
        activeSlot: int = table.getActiveSlot()
        inactiveSlot: int = activeSlot xor 0b01
      (table.slots[inactiveSlot])[] = (table.slots[activeSlot])[]
      body
    finally:
      table.commit()
