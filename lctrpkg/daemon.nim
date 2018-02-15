
import threadpool
import locks
import inotify
import os
import posix.inotify as pinotify
import posix
import db
import datatypes

var process_lock : Lock

type
  MyInotifyEvent = inotify.InotifyEvent

proc myStat(dir : string) : Stat =
  if stat(dir, result) != 0:
    raise newException(Exception, "Bad stat")

proc processThread(data : tuple[directory : string, events : seq[tuple[event : MyInotifyEvent, directory : string]]]) = 
  {.hint : "processThread: Arguments are a mess" .}
  process_lock.acquire()

  var i = 0
  var fullpath : string
  var db_conn = newLCTRDBConnection(data.directory)

  ##createDB(db_conn)
  echo "Handling queries!"

  for ev in data.events:
    let e = ev.event
    if e.name == nil:
      continue
    else:
      fullpath = joinPath(ev.directory, e.name)

    #echo data.directory & "///" & $e.name
    if (e.mask and pinotify.IN_ATTRIB) != 0:
      #let info = getFileInfo(fullpath , false)
      #echo info
      discard
    elif (e.mask and pinotify.IN_CLOSE_WRITE) != 0:
      discard
    elif (e.mask and pinotify.IN_MOVE) != 0:
      discard
    elif (e.mask and pinotify.IN_CREATE) != 0:
      let info = myStat(fullpath)
      let attr : LCTRAttributes = newLCTRAttributes(fullpath, info)
      #let query : LCTRDBQuery = newLCTRQuery()
      discard db_conn.handleQuery(DBQueryAdd, attr)
    elif (e.mask and pinotify.IN_DELETE) != 0:
      let info : Stat = Stat()
      let attr : LCTRAttributes = newLCTRAttributes(fullpath, info)
      #let query : LCTRDBQuery = newLCTRQuery()
      discard db_conn.handleQuery(DBQueryRemove, attr)
    elif (e.mask and pinotify.IN_MODIFY) != 0:
      discard
    elif (e.mask and pinotify.IN_DELETE_SELF) != 0:
      discard
    elif (e.mask and pinotify.IN_MOVE_SELF) != 0:
      discard
  db_conn.close()
  echo "Done"
  process_lock.release()

proc monitorThread(config : LCTRConfig) {.thread.} = 
  var im = newInotifyManager()
  #var process : Thread[tuple[directory : string, events : seq[MyInotifyEvent]]]
  var cache : seq[tuple[event: MyInotifyEvent, directory : string]] = @[]

  var db = newLCTRDBConnection(config.dbPath)
  {.gcsafe.}:
    for monitor_spec in db.getMonitors():
      echo "Adding monitor: " & monitor_spec.path
      discard im.addWatcher(monitor_spec.path, pinotify.IN_ALL_EVENTS, monitor_spec.recursive)
  db.close()

  while true:
    #var ie : inotify.InotifyEvent
    {.gcsafe.}:
      try:
        let ie = im.readEvent(1000)
        let w : InotifyWatcher = im.getWatcher(ie.wd)
        cache.add((event: ie, directory : w.path))
      except Exception:
        discard
      #if ie != nil:

      
    if cache.len > 0 and process_lock.tryAcquire():
      let c = cache
      cache = @[]
      spawn processThread((config.dbPath, c))
      process_lock.release()

proc mainThread(config : LCTRConfig) = 
  spawn monitorThread(config)
  while true:
    discard

proc modeDaemon*(config : LCTRConfig) = 
  mainThread(config)

