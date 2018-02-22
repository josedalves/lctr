
import threadpool
import locks
import inotify
import os
import posix.inotify as pinotify
import posix
import db
import datatypes
import db_sqlite
import strutils
import parseopt2

var process_lock : Lock
var running : bool = false

const
  INOTIFY_EVENTS = (
    #pinotify.IN_ACCESS or
    pinotify.IN_ATTRIB or
    pinotify.IN_CLOSE_WRITE or
    pinotify.IN_CREATE or
    pinotify.IN_DELETE or
    pinotify.IN_MOVE or
    pinotify.IN_DELETE_SELF or
    pinotify.IN_MOVE_SELF or
    pinotify.IN_MODIFY
  )


type
  MyInotifyEvent = inotify.InotifyEvent

  MonitorSpecObj = object
    dir : string
    depth : int
    exclude : seq[string]

var errno {.importc, header: "<errno.h>".}: cint ## error variable

proc signal*(sig : cint, f : pointer) {.importc: "signal", header: "<signal.h>".}

proc myStat(dir : string) : Stat =
  var r = stat(dir, result)
  if r != 0:
    echo strerror(errno)
    raise newException(Exception, "Bad stat")

proc processThread(config : LCTRConfig,  events : seq[MyInotifyEvent]) = 
  process_lock.acquire()
  var fullpath : string
  var db_conn : LCTRDBConnection = newLCTRDBConnection(config.dbPath)
  db_conn.acquireDBLock(retries=60, timeout=1000)

  for e in events:
    if e.name == nil:
      continue
    else:
      fullpath = joinPath(e.path, e.name)

    try:

      if (e.mask and pinotify.IN_ISDIR) != 0:
        #TODO : Handle directories
        continue

      if (e.mask and pinotify.IN_ATTRIB) != 0:
        echo "Attributes changed for $1" % fullpath
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_CLOSE_WRITE) != 0:
        echo "Close write for $1" % fullpath
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_CREATE) != 0:
        echo "Create $1" % fullpath
        db_conn.addOrReplaceObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_DELETE) != 0:
        echo "Delete $1" % fullpath
        db_conn.delObject(e.name, e.path)
      elif (e.mask and pinotify.IN_MODIFY) != 0:
        echo "Modify $1" % fullpath
        db_conn.updateObject(newLCTRAttributes(e.name, e.path, myStat(fullpath)))
      elif (e.mask and pinotify.IN_DELETE_SELF) != 0:
        discard
      elif (e.mask and pinotify.IN_MOVE_SELF) != 0:
        discard
      elif (e.mask and pinotify.IN_MOVE) != 0:
        echo "Move $1" % fullpath
    except DBError:
      raise
    except:
      discard

  db_conn.releaseDBLock()
  db_conn.close()
  process_lock.release()

proc monitor(config : LCTRConfig) = 
  var im = newInotifyManager()
  #var process : Thread[tuple[directory : string, events : seq[MyInotifyEvent]]]
  var cache : seq[MyInotifyEvent] = @[]
  running = true

  var db = newLCTRDBConnection(config.dbPath)
  #{.gcsafe.}:
  #  for monitor_spec in db.getMonitors():
  #    echo "Adding monitor: " & monitor_spec.path
  #    discard im.addWatcher(monitor_spec.path, pinotify.IN_ALL_EVENTS, monitor_spec.recursive)
  db.close()

  #echo expandFilename("~/work")

  try:
    im.addWatcher(expandTilde("~/work"), INOTIFY_EVENTS, true)
  except InotifyWatcherException as e:
    if e.error == ENOSPC:
      echo "Failed to create all watchers. Please increase watch limit with 'echo n > /proc/sys/fs/inotify/max_user_watches'"

  while running:
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
  process_lock.release()
  im.close()

proc handleTERM(i : cint) = 
  running = false

proc handleINT(i : cint) = 
  running = false

proc modeDaemon*(config : LCTRConfig, opts : OptParser) = 
  # signal handler:
  signal(SIGTERM, handleTERM)
  signal(SIGINT, handleINT)
  monitor(config)

