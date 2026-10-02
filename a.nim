import std/[
  strutils,
  cmdline
]
template a(x, y: int32): int32 =
  block:
    x + y
proc b(x, y: int32): int32 =
  result = 1
  result += a(x, y)
var z: int = paramStr(1).parseInt()
echo $b(z, z)
