version       = "0.0.1"
author        = "josedalves"
description   = "LoCaToR - File search and indexing"
license       = "MIT"

# Dependencies

requires "nim >= 0.17.2"
skipDirs = @["trash"]
bin = @["lctr"]


task clean, "Clean source tree":
  rmDir("nimcache")
  rmFile("lctr")

before release:
  exec "nimble clean"

task release, "Compile for release":
  exec "nim c -d:release lctr.nim"


