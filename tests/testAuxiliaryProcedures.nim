from unishell/module import Version, newVersion, `>`, `>=`, `<`, `<=`, `==`, `!=`, castPointerToString, castStringToPointer

var
  v100: Version = newVersion(1, 0, 0)
  v010: Version = newVersion(0, 1, 0)
  v001: Version = newVersion(0, 0, 1)

assert (v100 > v100) == false
assert (v100 > v010) == true
assert (v100 > v001) == true
assert (v010 > v100) == false
assert (v010 > v010) == false
assert (v010 > v001) == true
assert (v001 > v100) == false
assert (v001 > v010) == false
assert (v001 > v001) == false
assert (v100 < v100) == false
assert (v100 < v010) == false
assert (v100 < v001) == false
assert (v010 < v100) == true
assert (v010 < v010) == false
assert (v010 < v001) == false
assert (v001 < v100) == true
assert (v001 < v010) == true
assert (v001 < v001) == false
assert (v100 >= v100) == true
assert (v100 >= v010) == true
assert (v100 >= v001) == true
assert (v010 >= v100) == false
assert (v010 >= v010) == true
assert (v010 >= v001) == true
assert (v001 >= v100) == false
assert (v001 >= v010) == false
assert (v001 >= v001) == true
assert (v100 <= v100) == true
assert (v100 <= v010) == false
assert (v100 <= v001) == false
assert (v010 <= v100) == true
assert (v010 <= v010) == true
assert (v010 <= v001) == false
assert (v001 <= v100) == true
assert (v001 <= v010) == true
assert (v001 <= v001) == true
assert (v100 == v100) == true
assert (v100 == v010) == false
assert (v100 == v001) == false
assert (v010 == v100) == false
assert (v010 == v010) == true
assert (v010 == v001) == false
assert (v001 == v100) == false
assert (v001 == v010) == false
assert (v001 == v001) == true
assert (v100 != v100) == false
assert (v100 != v010) == true
assert (v100 != v001) == true
assert (v010 != v100) == true
assert (v010 != v010) == false
assert (v010 != v001) == true
assert (v001 != v100) == true
assert (v001 != v010) == true
assert (v001 != v001) == false

var
  text: string = "Hello!"
  textPtr: ptr string = addr text
  textPtrString: string = castPointerToString(textPtr)
  textPtrStringPtr: ptr string = cast[ptr string](castStringToPointer(textPtrString))

assert text == textPtrStringPtr[]
