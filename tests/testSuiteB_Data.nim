import unishell/[
  data,
  allocator
]

const
  ZEROINT:  int  = 0
  ZEROCHAR: char = cast[char](ZEROINT)
  TESTSTR:  string = "test"

var
  auxData: Data
  auxView: DataView
  auxStr:  string

auxData = newData(4)
assert (auxData != nil)
assert (auxData[0] == ZEROCHAR)
assert (auxData[1] == ZEROCHAR)
assert (auxData[2] == ZEROCHAR)
assert (auxData[3] == ZEROCHAR)

auxData[0] = 't'
auxData[1] = 'e'
auxData[2] = 's'
auxData[3] = 't'
assert (auxData[0] == 't')
assert (auxData[1] == 'e')
assert (auxData[2] == 's')
assert (auxData[3] == 't')

auxView = auxData.toDataView(4)
assert (auxView[0] == 't')
assert (auxView[1] == 'e')
assert (auxView[2] == 's')
assert (auxView[3] == 't')
assert (auxView == auxData)
assert (auxData == auxView)
assert (auxView == newData("test").toDataView(4))
assert (auxView == "test")
assert ("test" == auxView)
assert (TESTSTR.toDataView() == auxView)
assert (auxView == TESTSTR.toDataView())

auxView.overwriteWith("tset")
assert (auxView[0] == 't')
assert (auxView[1] == 's')
assert (auxView[2] == 'e')
assert (auxView[3] == 't')

auxView.overwriteWith("test".toDataView())
assert (auxView[0] == 't')
assert (auxView[1] == 'e')
assert (auxView[2] == 's')
assert (auxView[3] == 't')

auxStr = $auxView
assert (auxStr == "test")

auxData.destroyData()
assert (auxData == nil)

auxData = newData(hostAllocator, 4)
assert (auxData != nil)
destroyData(hostAllocator, auxData)
assert (auxData == nil)
auxData = newData(hostAllocator, "test")
assert (auxData != nil)

auxView = auxData.toDataView(4)
assert (auxView[0] == 't')
assert (auxView[1] == 'e')
assert (auxView[2] == 's')
assert (auxView[3] == 't')

overwriteWith(hostAllocator, auxView, "tset".toDataView())
assert (auxView[0] == 't')
assert (auxView[1] == 's')
assert (auxView[2] == 'e')
assert (auxView[3] == 't')
overwriteWith(hostAllocator, auxView, "test")
assert (auxView[0] == 't')
assert (auxView[1] == 'e')
assert (auxView[2] == 's')
assert (auxView[3] == 't')

assert ('t' in auxView)
assert not ('a' in auxView)
for i in auxView:
  assert (i in "test")
assert (auxView.len() == 4)

destroyData(hostAllocator, auxData)
assert (auxData == nil)
