import unishell/view

var
  darray1: Darray[Natural]
  view1: View[Natural]
  darray2: Darray[char]
  view2: View[char]
  aux: int = 0

darray1.dallocDarray(3)
view1 = darray1.newView(3)
view1[0] = 0
view1[1] = 1
view1[2] = 2
assert view1[0] == 0
assert view1[1] == 1
assert view1[2] == 2
assert view1.len() == 3
assert $view1 == "0 1 2 "

for i in view1:
  aux += i
assert aux == 3
aux = 0
assert aux in view1

view1 = darray1.newView(1, 2)
assert view1[0] == 1
assert view1[1] == 2

darray1.dallocDarray(0)
assert darray1 == nil

darray2.dallocDarray(sizeOf(int)*3)
view2 = darray2.newView(sizeOf(int)*3)
var
  auxStr: string = ""
  auxInt: int = 65
for i in 0 .. (sizeOf(int)*3):
  auxStr &= cast[char](auxInt)
  auxInt += 1
  if auxInt > 90:
    auxInt = 65
view2.overwriteWith(auxStr)
assert view2[0] == 'A'
assert view2[1] == 'B'
assert view2[2] == 'C'
assert view2[3] == 'D'
assert view2[4] == 'E'
assert view2[5] == 'F'
assert view2[6] == 'G'
assert view2[7] == 'H'
view1 = darray2.newAlternateView(sizeOf(int), sizeOf(int)*2)
view1[0] = 0
view1[1] = 1
assert view2[sizeOf(int)] == cast[char](0)
assert view2[sizeOf(int)*2] == cast[char](1)
view2 = darray2.newView(4)
view2.overwriteWith("ABCD")
assert $view2 == "ABCD"

darray1.dallocDarray(0, hostAllocator)
darray2.dallocDarray(0, hostAllocator)
assert darray1 == nil
assert darray2 == nil
