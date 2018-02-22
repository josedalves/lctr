import posix.inotify as inotify
import posix.posix as posix
import strutils
import os
import selectors
import pegs

type
  InotifyEventObj* = object of RootObj
    ## Inotify event class. Represents one inotify event
    wd : cint
    mask : uint32
    cookie : uint32
    name : string
    path : string
  InotifyEvent* = ref InotifyEventObj

  InotifyWatcherObj = object of RootObj
    ## Inotify Watcher. Contains watcher information.
    wd : FileHandle
    path : string
    mask : uint32
  InotifyWatcher* = ref InotifyWatcherObj

  InotifyManagerObj = object of RootObj
    ## Inotify Manager. Contains overall inotify info
    fd : FileHandle
    file : File
    watchers : seq[InotifyWatcher]
    selector : Selector
  InotifyManager* = ref InotifyManagerObj

  InotifyException* = object of Exception
    error* : int
  InotifyWatcherException* = object of InotifyException

# accessors for InotifyEvent
proc name*(self : InotifyEvent) : string {.inline.} = self.name
proc path*(self : InotifyEvent) : string {.inline.} = self.path
proc mask*(self : InotifyEvent) : uint32 {.inline.} = self.mask
proc cookie*(self : InotifyEvent) : uint32 {.inline.} = self.cookie

# errno variable
var errno {.importc, header: "<errno.h>".}: cint

proc inotifyErr(s : string, error : int = 0) = 
  var e = new InotifyException
  e.msg = s
  e.error = error
  raise e

proc inotifyWatcherErr(s : string, error : int = 0) = 
  var e = new InotifyWatcherException
  e.msg = s
  e.error = error
  raise e

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
      patternParts.add("*")
    of '?':
      endWord()
      patternParts.add("?")
    of '[':
      endWord()
    of ']':
      endGroup()
    else:
      word.add(c)
  endWord()
  return patternParts.join(" ")

proc newInotifyEvent*(wd : cint, mask : uint32, cookie : uint32,
                      name : string, path : string) : InotifyEvent =
  result = new InotifyEvent
  result.wd = wd
  result.mask = mask
  result.cookie = cookie
  result.name = name
  result.path = path

proc newInotifyWatcher*(fd : cint, path : string,
                        mask : uint32) : InotifyWatcher =
  result = new InotifyWatcher
  result.wd = fd
  result.path = path
  result.mask = mask

proc newInotifyManager*() : InotifyManager = 
  result = new InotifyManager
  let fd : FileHandle = inotify.inotify_init()
  result.fd = fd
  if system.open(result.file, fd) != true:
    inotifyErr("Failed to open inotify file")
    discard close(fd) # abort, abort, abort!
  result.watchers = @[]
  result.selector = newSelector()
  result.selector.register(cast[SocketHandle](result.fd), {EvRead}, nil)

method getWatcher*(self : InotifyManager, wd : int) : InotifyWatcher =
  for w in self.watchers:
    if w.wd == wd:
      return w
  inotifyErr("Failed to retrieve watcher with id $1: no such watcher" % $wd)
  raise newException(Exception, "No watcher")

method getWatcher(self : InotifyManager, path : string) : InotifyWatcher = discard

# Add a new watcher
method addWatcher*(i : InotifyManager, path : string, mask : uint32,
                   recursive : bool = false, maxDepth : int = high(int),
                   excludeDirs : seq[string] = @[] ) {.base.} = 
  var w : cint
  var stk : seq[tuple[path : string, depth : int]] = @[]

  if not recursive:
    w = inotify.inotify_add_watch(i.fd, path, mask)
    if w < 0:
      inotifyWatcherErr("addWatcher error: $1" % $strerror(errno), errno)
    return

  stk.add((path, 0))

  while len(stk) > 0:
    let nxt = stk.pop()

    w = inotify.inotify_add_watch(i.fd, nxt.path, mask)
    if w < 0:
      inotifyWatcherErr("addWatcher error: $1" % $strerror(errno), errno)
    i.watchers.add(newInotifyWatcher(w, nxt.path, mask))

    if nxt.depth < maxDepth:
      for kind, npath in os.walkDir(nxt.path):
        for ex in excludeDirs:
          if splitPath(npath)[1] =~ peg(globToPEG(ex)):
            continue
        if kind == pcDir:
          stk.add((npath, nxt.depth+1))
    else:
      echo "Ex: depth"


proc calculateNeededWatchers*(path : string) : int = 
  var stk : seq[string] = @[path]
  var p : string
  result = 0

  while len(stk) > 0:
    p = stk.pop()
    for kind, npath in os.walkDir(p):
      if kind == pcDir:
        stk.add(npath)
    inc(result)

method peek*(self : InotifyManager, timeout : int) : bool = 
  ## Return true if there are any events to be read
  ## Timeout: milliseconds
  let sel = self.selector.select(timeout)
  if len(sel) > 0:
    for ev in sel:
      let events = ev.events
      if EvRead in events:
        return true
  return false


method readEvent*(self : InotifyManager, timeout : int = 0) : InotifyEvent {.raises : [Exception], base.} = 
  ## Read one event
  var
    buffer : array[4, uint8]
    wd : cint
    mask : uint32
    cookie : uint32
    ln : uint32
    lni : int
    name : string
    sq : seq[uint8]

  if timeout > 0:
    if not self.peek(timeout):
      inotifyErr("readEvent: Timeout")

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    inotifyErr("readEvent: Expected 4 bytes")

  wd = cast[cint](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    inotifyErr("readEvent: Expected 4 bytes")

  mask = cast[uint32](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    inotifyErr("readEvent: Expected 4 bytes")

  cookie = cast[uint32](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    inotifyErr("readEvent: Expected 4 bytes")

  {.hint : "Integer conversion is probably incorrect".}

  ln = cast[uint32](buffer)
  lni = cast[int](ln)

  if lni > 0:
    sq = newSeq[uint8](ln)
    let read = system.readBytes(self.file, sq, 0, lni)
    if read != lni:
      inotifyErr("readEvent: Expected $1 bytes, but only read $2" % [$read, $lni])
    name = cast[string](sq)
    # Strip 0x00 from the string. inotify spec says that messages can be padded
    # with those
    name = name.strip(chars = {'\x00'})

  return newInotifyEvent(wd, mask, cookie, name, path = self.getWatcher(cast[int](wd)).path)

method close*(self : InotifyManager) = 
  for w in self.watchers:
    discard inotify_rm_watch(self.fd, w.wd)
  self.file.close()
  discard self.fd.close()


