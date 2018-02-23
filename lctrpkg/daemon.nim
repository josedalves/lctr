
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
import system

var process_lock : Lock
var process_cond : Cond
var process_channel : Channel[inotify.InotifyEvent]

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
    pinotify.IN_MODIFY or
    pinotify.IN_EXCL_UNLINK
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

proc processThread(config : LCTRConfig) = 

  var fullpath : string
  var db_conn : LCTRDBConnection = newLCTRDBConnection(config.dbPath)
  var event : inotify.InotifyEvent

  process_channel.open()

  while running:

    wait(process_cond, process_lock)

    db_conn.acquireDBLock(retries=60, timeout=1000)

    var cdata = process_channel.tryRecv()

    while cdata.dataAvailable:
      event = cdata.msg

      if event == nil:
        echo "ABORT!"
        return

      if event.name == nil:
        continue
      else:
        fullpath = joinPath(event.path, event.name)

      try:
        if (event.mask and pinotify.IN_ISDIR) != 0:
          #TODO : Handle directories
          continue

        if (event.mask and pinotify.IN_ATTRIB) != 0:
          echo "Attributes changed for $1" % fullpath
          db_conn.updateObject(newLCTRAttributes(event.name, event.path, myStat(fullpath)))
        elif (event.mask and pinotify.IN_CLOSE_WRITE) != 0:
          echo "Close write for $1" % fullpath
          db_conn.updateObject(newLCTRAttributes(event.name, event.path, myStat(fullpath)))
        elif (event.mask and pinotify.IN_CREATE) != 0:
          echo "Create $1" % fullpath
          db_conn.addOrReplaceObject(newLCTRAttributes(event.name, event.path, myStat(fullpath)))
        elif (event.mask and pinotify.IN_DELETE) != 0:
          echo "Delete $1" % fullpath
          db_conn.delObject(event.name, event.path)
        elif (event.mask and pinotify.IN_MODIFY) != 0:
          echo "Modify $1" % fullpath
          db_conn.updateObject(newLCTRAttributes(event.name, event.path, myStat(fullpath)))
        elif (event.mask and pinotify.IN_DELETE_SELF) != 0:
          discard
        elif (event.mask and pinotify.IN_MOVE_SELF) != 0:
          discard
        elif (event.mask and pinotify.IN_MOVE) != 0:
          echo "Move $1" % fullpath
      except DBError:
        raise
      except:
        discard

      # get next cdata
      cdata = process_channel.tryRecv()

    db_conn.releaseDBLock()

  process_channel.close()
  db_conn.close()
  #process_lock.release()

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
  var cache : seq[MyInotifyEvent] = @[]
  running = true

  var db = newLCTRDBConnection(config.dbPath)
  db.close()
  echo "Initializing watchers"
  setupWatchers(im, monitorSpecs)
  echo "Starting daemon"

  spawn processThread(config)
  process_channel.open()

  var event : inotify.InotifyEvent
  while running:
    try:
      event = im.readEvent(1000)
      if joinPath(event.path, event.name) ==  expandFilename(config.dbPath):
        #HACK: filter out db file
        continue
      #cache.add(ie)
    except Exception:
      continue
      #raise

    withLock(process_lock):
      process_channel.send(event)
      process_cond.signal()

  process_channel.close()
  #process_lock.release()
  process_cond.signal()
  #sync()
  im.close()

proc handleTERM(i : cint) = 
  running = false

proc handleINT(i : cint) = 
  running = false

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

