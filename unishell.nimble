# Package

version       = "0.1.0"
author        = "Carmelo Maita"
description   = "A framework for dynamically loaded, nested, concurrent state-machines"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.4"
requires "https://github.com/beef331/wasm3 >= 0.1.1"

before test:
  exec "nim c --app:lib --noMain --mm:orc --define:useMalloc --out:tests/libmodule1.so tests/module1.nim"
  exec "nim c --app:lib --noMain --mm:orc --define:useMalloc --out:tests/libmodule2.so tests/module2.nim"
  exec "nim c --app:lib --noMain --mm:orc --define:useMalloc --out:tests/libmodule3.so tests/module3.nim"
