import std/[
  unittest,
  tables
]
import unishell

suite "Module Versioning":
  test "Module comparison logic":
    let m1 = Module(version: (major: 1, minor: 0, patch: 0))
    let m2 = Module(version: (major: 1, minor: 0, patch: 1))
    let m3 = Module(version: (major: 1, minor: 1, patch: 0))
    let m4 = Module(version: (major: 2, minor: 0, patch: 0))
    
    check (m1 > m1) == false
    check (m1 > m2) == false
    check (m1 > m3) == false
    check (m1 > m4) == false
    check (m2 > m1) == true
    check (m2 > m2) == false
    check (m2 > m3) == false
    check (m2 > m4) == false
    check (m3 > m1) == true
    check (m3 > m2) == true
    check (m3 > m3) == false
    check (m3 > m4) == false
    check (m4 > m1) == true
    check (m4 > m2) == true
    check (m4 > m3) == true
    check (m4 > m4) == false
