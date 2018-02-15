import datatypes
import parseopt2
import db
import strutils
import pegs
import os

type BadModeArgumentsException* = object of Exception

proc newBadModeArgumentsException() : ref BadModeArgumentsException =
  return newException(BadModeArgumentsException, "Bad arguments. Expected 'add' or 'del'")

proc usage() = 
  discard

let modePEG = peg """
  start <- {rule} ' ' {path}
  rule <- 'add recursive' / 'add' / 'del'
  path <- [a-zA-Z0-9_\\\.-]+
"""

proc modeMonitor*(config : LCTRConfig, op : var OptParser) = 
  ## Monitor mode: add and remove monitors
  ## Format:
  ##   monitor add|add recursive|del path
  var
    db = newLCTRDBConnection(config.dbPath)
    cmds : seq[string] = @[]
  op.next()
  while op.kind  != cmdEnd:
    cmds.add(op.key)
    op.next()

  if cmds.join(" ") =~ modePEG:
    let rule = matches[0]
    let path = expandFilename(matches[1])

    case rule:
    of "add":
      discard db.addMonitor(path, false)
    of "add recursive":
      discard db.addMonitor(path, true)
    of "del":
      discard db.delMonitor(path)
    else:
      raise newException(Exception, "A")
  else:
    raise newException(Exception, "B")

  db.close()
