
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
import pegs

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
    path : string
    depth : int
    exclude : seq[string]
    mask : uint32
  MonitorSpec = ref MonitorSpecObj
  #MonitorSpec = tuple[dir : string, depth : int, exclude : seq[string]]

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

proc globToPEG*(pattern : string) : string =
  var word : seq[char] =  @[]
  var patternParts : seq[string] = @[]

  proc endWord() = 
    if len(word) > 0:
      patternParts.add("'" & word.join() & "'")
      word = @[]

  proc endGroup() = 
    patternParts.add(word.join())
    word = @[]

  for c in pattern:
    case c:
    of '*':
      endWord()
      patternParts.add(".*")
    of '?':
      endWord()
      patternParts.add(".?")
    of '[':
      endWord()
    of ']':
      endGroup()
    else:
      word.add(c)
  endWord()
  return (@["^"] & patternParts & @["$"]).join(" ")

proc setupWatchers(i : InotifyManager, specs : seq[MonitorSpec], abortOnError : bool = false ) = 
  var w : cint
  var stk : seq[tuple[path : string, depth : int]]

  for spec in specs:
    stk = @[]
    let path = spec.path
    let maxDepth = spec.depth
    let excludeDirs = spec.exclude
    let mask = spec.mask

    stk.add((path, 0))

    while len(stk) > 0:
      let nxt = stk.pop()

      try:
        discard i.addWatcher(nxt.path, mask)
      except InotifyWatcherException as e:
        case e.error:
        of ENOSPC:
          echo "Failed to create all watchers. Please increase watch limit with 'echo n > /proc/sys/fs/inotify/max_user_watches'"
          return
        of EACCES:
          discard
        else:
          discard

      if nxt.depth < maxDepth:
        for kind, npath in os.walkDir(nxt.path):
          var exclude = false
          for ex in excludeDirs:
            if splitPath(npath)[1] =~ peg(globToPEG(ex)):
              echo "Excluding: ", npath
              exclude = true
              break

          if kind == pcDir and not exclude:
            echo "Add ", npath
            stk.add((npath, nxt.depth+1))
      else:
        echo "Ex: depth"

proc monitor(config : LCTRConfig, monitorSpecs : seq[MonitorSpec]) = 
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
  echo "Initializing watchers"

  setupWatchers(im, monitorSpecs)

  #for spec in monitorSpecs:
  #  try:
  #    echo spec.path, " ", spec.depth, " ", spec.exclude
  #    im.addWatcher(expandTilde(spec.path), INOTIFY_EVENTS, true, spec.depth, spec.exclude)
  #  except InotifyWatcherException as e:
  #    if e.error == ENOSPC:
  #      echo "Failed to create all watchers. Please increase watch limit with 'echo n > /proc/sys/fs/inotify/max_user_watches'"
  #    else:
  #      raise

  echo "Starting daemon"

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

# lctr daemon 'monitor:/foo/bar depth:2 exclude:.*'
# lctr daemon --monitor:'/home/sup' --exclude:'ff' --exclude:'ff' --limit:1 --monitor:
proc modeDaemon*(config : LCTRConfig, op : var OptParser) = 
  # signal handler:
  signal(SIGTERM, handleTERM)
  signal(SIGINT, handleINT)
  var specs : seq[MonitorSpec] = @[]
  var cur : MonitorSpec

  op.next()
  while op.kind != cmdEnd:
    case op.kind:
    of cmdLongOption:
      case op.key:
      of "monitor":
        if cur != nil:
          specs.add(cur)
        cur = new MonitorSpec
        cur.path = op.val
        cur.depth = high(int)
        cur.exclude = @[]
        cur.mask = INOTIFY_EVENTS
      of "depth":
        if cur == nil:
          raise newException(Exception, "")
        cur.depth = parseInt(op.val)
      of "exclude":
        if cur == nil:
          raise newException(Exception, "")
        cur.exclude.add(op.val)
    else:
      raise newException(Exception, "")
    op.next()

  if cur != nil:
    specs.add(cur)

  if len(specs) == 0:
    raise newException(Exception, "")

  monitor(config, specs)

