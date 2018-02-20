
import threadpool
import locks
import inotify
import os
import posix.inotify as pinotify
import posix
import db
import datatypes

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

proc myStat(dir : string) : Stat =
  if stat(dir, result) != 0:
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

    if (e.mask and pinotify.IN_ATTRIB) != 0:
      db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
    elif (e.mask and pinotify.IN_CLOSE_WRITE) != 0:
      db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
    elif (e.mask and pinotify.IN_MOVE) != 0:
      discard
    elif (e.mask and pinotify.IN_CREATE) != 0:
      db_conn.addObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
    elif (e.mask and pinotify.IN_DELETE) != 0:
      db_conn.delObject(e.name, e.path)
    elif (e.mask and pinotify.IN_MODIFY) != 0:
      db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
    elif (e.mask and pinotify.IN_DELETE_SELF) != 0:
      discard
    elif (e.mask and pinotify.IN_MOVE_SELF) != 0:
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

  discard im.addWatcher(expandFilename("~/work"), INOTIFY_EVENTS, true)

  while true:
    try:
      let ie = im.readEvent(1000)
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

