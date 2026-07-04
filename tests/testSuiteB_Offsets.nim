import unishell/[
  offsets,
  allocator
]

var
  auxOffsets:  Offsets
  auxOffsets2: Offsets
  auxView:     OffsetsView
  auxView2:    OffsetsView

auxOffsets = newOffsets(4)
assert (auxOffsets != nil)
assert (auxOffsets[0] == 0)
assert (auxOffsets[1] == 0)
assert (auxOffsets[2] == 0)
assert (auxOffsets[3] == 0)

auxOffsets[0] = 1
auxOffsets[1] = 2
auxOffsets[2] = 3
auxOffsets[3] = 4
assert (auxOffsets[0] == 1)
assert (auxOffsets[1] == 2)
assert (auxOffsets[2] == 3)
assert (auxOffsets[3] == 4)

destroyOffsets(auxOffsets)
assert (auxOffsets == nil)

auxOffsets = newOffsets(1, 2, 3, 4)
assert (auxOffsets[0] == 1)
assert (auxOffsets[1] == 2)
assert (auxOffsets[2] == 3)
assert (auxOffsets[3] == 4)

destroyOffsets(auxOffsets)
assert (auxOffsets == nil)

auxOffsets = newOffsets(hostAllocator, 4)
assert (auxOffsets != nil)
assert (auxOffsets[0] == 0)
assert (auxOffsets[1] == 0)
assert (auxOffsets[2] == 0)
assert (auxOffsets[3] == 0)

destroyOffsets(hostAllocator, auxOffsets)
assert (auxOffsets == nil)

auxOffsets = newOffsets(hostAllocator, 1, 2, 3, 4)
assert (auxOffsets[0] == 1)
assert (auxOffsets[1] == 2)
assert (auxOffsets[2] == 3)
assert (auxOffsets[3] == 4)

auxView = auxOffsets.toOffsetsView(4)
assert (auxView[0] == 1)
assert (auxView[1] == 2)
assert (auxView[2] == 3)
assert (auxView[3] == 4)

for i in auxView:
  assert (i in auxView)
assert (auxView.len() == 4)

auxOffsets2 = newOffsets(1, 2, 3, 4)
auxView2 = auxOffsets2.toOffsetsView(4)
assert (auxView == auxView2)

auxView2[0] = 0
auxView2[1] = 1
auxView2[2] = 2
auxView2[3] = 3

auxView.overwriteWith(auxView2)
assert (auxView == auxView2)

auxView2[0] = 3
auxView2[1] = 4
auxView2[2] = 5
auxView2[3] = 6
overwriteWith(hostAllocator, auxView, auxView2)
assert (auxView == auxView2)
