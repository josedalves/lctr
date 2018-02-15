import posix
import datatypes
import db
import db_sqlite
import os
import parseopt2
import strutils
import sets
import tables


#proc showProgress() = 
#  var n = 0
#  let progress = @["-", "\\", "|", "/", "-", "\\", "|", "/"]
#  let ln = len(progress)
#
#  write(stdout, "\r")
#  write(stdout, progress[n mod ln])
#  flushFile(stdout)
#  n+=1
#  sleep(400)
#  discard

# Hardcoded ignore paths
const IGNORE_PATHS = @["/proc", "/sys"]

proc myStat(dir : string) : Stat =
  if stat(dir, result) != 0:
    raise newException(Exception, "Bad stat")

proc updateDirDeleteInsert(db : LCTRDBConnection, dir : string, files : ref seq[LCTRAttributes]) = 
  db.conn.exec(sql"DELETE FROM objects WHERE path=?", dir)

  for f in files[]:
    let name = f.name
    db.addObject(f)

proc updateDirInsertOrReplace(db : LCTRDBConnection, dir : string, files : ref seq[LCTRAttributes]) = 
  var fnames : seq[string] = @[]

  for f in files[]:
    let name = f.name
    db.addOrReplaceObject(f)
    fnames.add("\""&f.name&"\"")
  
  db.rmFilesFromDirectoryNot(dir, fnames)
  #db.conn.exec(sql("DELETE FROM objects WHERE path=? "), dir)


proc updateDirDelete(db : LCTRDBConnection, dir : string, files : ref seq[LCTRAttributes]) = 
  var fnames : seq[string] = @[]

  for f in files[]:
    let name = f.name
    db.addObject(f)
    #fnames.add("\""&f.name&"\"")
  
  #db.rmFilesFromDirectoryNot(dir, fnames)
  #db.conn.exec(sql("DELETE FROM objects WHERE path=? "), dir)
  #
proc updateDir(db : LCTRDBConnection, dir : string, files : ref seq[LCTRAttributes]) = 
  updateDirDelete(db, dir, files)

proc modeRefreshDelete(config : LCTRConfig, op : var OptParser) = 
  # Refresh mode: Manual database update
  let db = newLCTRDBConnection(config.dbPath)
  var path : string = os.getCurrentDir()
  var attrs : ref seq[LCTRAttributes]
  var dirStack : seq[string]
  op.next()

  case op.kind:
  of cmdArgument:
    path = expandFilename(op.key)
  of cmdEnd:
    discard
  else:
    raise newException(Exception, "")

  dirStack = @[path]

  db.rmDirTree(path)


  #echo len(t)
  #if true:
  #  return

  db.conn.exec(sql"""BEGIN""")


  while dirStack.len() > 0:
    let dir = dirStack.pop()
    if dir in IGNORE_PATHS:
      continue
    let dirstat = newLCTRAttributes(dir, myStat(dir))
    attrs = new seq[LCTRAttributes]
    attrs[] = @[]

    if config.verbose:
      echo dir

    for kind, path in walkDir(dir):
      case kind:
      of pcFile:
        var sp = splitPath(path)
        attrs[].add(newLCTRAttributes(sp[1], sp[0], myStat(path)))
      of pcDir:
        dirStack.add(path)
      else:
        continue
    updateDir(db, dir, attrs)
  db.conn.exec(sql"""COMMIT""")

proc modeRefreshNormal(config : LCTRConfig, op : var OptParser) = 
  # Refresh mode: Manual database update
  let db = newLCTRDBConnection(config.dbPath)
  var path : string = os.getCurrentDir()
  var attrs : ref seq[LCTRAttributes]
  var dirStack : seq[string]
  op.next()

  case op.kind:
  of cmdArgument:
    path = expandFilename(op.key)
  of cmdEnd:
    discard
  else:
    raise newException(Exception, "")

  dirStack = @[path]


  #echo len(t)
  #if true:
  #  return

  #db.conn.exec(sql"""BEGIN""")


  while dirStack.len() > 0:
    let dir = dirStack.pop()
    if dir in IGNORE_PATHS:
      continue
    let dirstat = newLCTRAttributes(dir, myStat(dir))
    attrs = new seq[LCTRAttributes]
    attrs[] = @[]

    if config.verbose:
      echo dir

    for kind, path in walkDir(dir):
      case kind:
      of pcFile:
        var sp = splitPath(path)
        attrs[].add(newLCTRAttributes(sp[1], sp[0], myStat(path)))
      of pcDir:
        dirStack.add(path)
      else:
        continue
    updateDir(db, dir, attrs)
  #db.conn.exec(sql"""COMMIT""")

proc modeRefresh*(config : LCTRConfig, op : var OptParser) = 
  modeRefreshDelete(config, op)

