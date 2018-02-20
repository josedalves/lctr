
import threadpool
import locks
import inotify
import os
import posix.inotify as pinotify
import posix
import db
import datatypes
import db_sqlite

var process_lock : Lock

const
  INOTIFY_EVENTS = (pinotify.IN_MODIFY or
    pinotify.IN_ATTRIB or
    pinotify.IN_CLOSE_WRITE or
    pinotify.IN_MOVE or
    pinotify.IN_CREATE or
    pinotify.IN_DELETE or
    pinotify.IN_DELETE_SELF or
    pinotify.IN_MOVE_SELF
  )


type
  MyInotifyEvent = inotify.InotifyEvent

var errno {.importc, header: "<errno.h>".}: cint ## error variable

proc myStat(dir : string) : Stat =
  var r = stat(dir, result)
  if r != 0:
    echo strerror(errno)
    raise newException(Exception, "Bad stat")

proc processThread(config : LCTRConfig,  events : seq[MyInotifyEvent]) = 
  {.hint : "processThread: Arguments are a mess" .}
  process_lock.acquire()

  var i = 0
  var fullpath : string
  var db_conn = newLCTRDBConnection(config.dbPath)
  echo "Handling queries!"

  for e in events:
    if e.name == nil:
      continue
    else:
      fullpath = joinPath(e.path, e.name)

    echo e.name
    echo e.path
    echo e.mask

    try:
      if (e.mask and pinotify.IN_ISDIR) != 0:
        continue
      if (e.mask and pinotify.IN_ATTRIB) != 0:
        echo "1"
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_CLOSE_WRITE) != 0:
        echo "2"
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_MOVE) != 0:
        discard
      elif (e.mask and pinotify.IN_CREATE) != 0:
        echo "3"
        db_conn.addOrReplaceObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_DELETE) != 0:
        echo "4"
        db_conn.delObject(e.name, e.path)
      elif (e.mask and pinotify.IN_MODIFY) != 0:
        echo "5"
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_DELETE_SELF) != 0:
        discard
      elif (e.mask and pinotify.IN_MOVE_SELF) != 0:
        discard
    except DBError:
      raise
    except:
      discard
  db_conn.close()
  echo "Done"
  process_lock.release()

proc monitorThread(config : LCTRConfig) = 
  var im = newInotifyManager()
  #var process : Thread[tuple[directory : string, events : seq[MyInotifyEvent]]]
  var cache : seq[MyInotifyEvent] = @[]

  var db = newLCTRDBConnection(config.dbPath)
  #{.gcsafe.}:
  #  for monitor_spec in db.getMonitors():
  #    echo "Adding monitor: " & monitor_spec.path
  #    discard im.addWatcher(monitor_spec.path, pinotify.IN_ALL_EVENTS, monitor_spec.recursive)
  db.close()

  #echo expandFilename("~/work")
  discard im.addWatcher(expandTilde("~/work"), INOTIFY_EVENTS, true)

  while true:
    try:
      let ie = im.readEvent(1000)
      if joinPath(ie.path, ie.name) ==  expandFilename(config.dbPath):
        #HACK: filter out db file
        continue
      cache.add(ie)
    except Exception:
      discard
      
    if cache.len > 0 and process_lock.tryAcquire():
      let c = cache
      cache = @[]
      spawn processThread(config, c)
      process_lock.release()

proc mainThread(config : LCTRConfig) = 
  monitorThread(config)

proc modeDaemon*(config : LCTRConfig) = 
  mainThread(config)

