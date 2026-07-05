import unishell/rcutable

type TestObj = ref object
  field: int

var table = newRcuTable[int, TestObj]()
assert (table.getActiveSlot() == 0)
assert (table.getInactiveSlot() == 1)
assert (table.len() == 0)

table.modify:
  table[slot, 0] = TestObj(field: 0)
  table[slot, 1] = TestObj(field: 1)
  table[slot, 2] = TestObj(field: 2)
  table[slot, 3] = TestObj(field: 3)
assert (table.len() == 4)
assert (table[0].field == 0)
assert (table[1].field == 1)
assert (table[2].field == 2)
assert (table[3].field == 3)
assert (table.contains(1))
table.modify:
  table.clear(slot)
assert (table.len() == 0)
