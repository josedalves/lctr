import posix.inotify as inotify
import posix.posix as posix
import strutils
import os
import selectors

# Inotify event class. Represents one inotify event
type
  InotifyEventObj* = object of RootObj
    wd : cint
    mask : uint32
    cookie : uint32
    name : string
    path : string
  InotifyEvent* = ref InotifyEventObj

# The errno variable
var errno {.importc, header: "<errno.h>".}: cint ## error variable

proc name*(self : InotifyEvent) : string {.inline.} = self.name
proc path*(self : InotifyEvent) : string {.inline.} = self.path
proc mask*(self : InotifyEvent) : uint32 {.inline.} = self.mask
proc cookie*(self : InotifyEvent) : uint32 {.inline.} = self.cookie

proc newInotifyEvent*(wd : cint, mask : uint32, cookie : uint32, name : string, path : string) : InotifyEvent =
  result = new InotifyEvent
  result.wd = wd
  result.mask = mask
  result.cookie = cookie
  result.name = name
  result.path = path

# Inotify Watcher. Contains watcher information.
type
  InotifyWatcherObj = object of RootObj
    wd : FileHandle
    path : string
    mask : uint32
  InotifyWatcher = ref InotifyWatcherObj

proc newInotifyWatcher*(fd : cint, path : string, mask : uint32) : InotifyWatcher =
  result = new InotifyWatcher
  result.wd = fd
  result.path = path
  result.mask = mask

# Inotify Manager. Contains overall inotify info
type
  InotifyManagerObj = object of RootObj
    fd : FileHandle
    file : File
    watchers : seq[InotifyWatcher]
    selector : Selector
  InotifyManager = ref InotifyManagerObj

method getWatcher*(self : InotifyManager, wd : int) : InotifyWatcher =
  for w in self.watchers:
    if w.wd == wd:
      return w
  raise newException(Exception, "No watcher")

proc newInotifyManager*() : InotifyManager = 
  result = new InotifyManager

  var fd : FileHandle = inotify.inotify_init()

  result.fd = fd
  if system.open(result.file, fd) != true:
    echo "Bad!"

  result.watchers = @[]

  ## Selector
  result.selector = newSelector()
  result.selector.register(cast[SocketHandle](result.fd), {EvRead}, nil)

# Add a new watcher
method addWatcher*(i : InotifyManager, path : string, mask : uint32, recursive : bool = false ) : bool {.base.} = 
  var w : cint

  echo len(i.watchers)
  #echo i.fd, path, mask
  w = inotify.inotify_add_watch(i.fd, path, mask)
  if w < 0:
    #echo "Bad Bad!  ", w
    echo strerror(w)
    echo strerror(errno)
    echo cast[int](w)
    return false

  i.watchers.add(newInotifyWatcher(w, path, mask))
  if recursive:
    for kind, npath in os.walkDir(path):
      if kind == pcDir:
        discard i.addWatcher(npath, mask, recursive)

  return true

# Return true if there are any events to be read
# Timeout: milliseconds
method peek*(self : InotifyManager, timeout : int) : bool = 
  let sel = self.selector.select(timeout)
  if len(sel) > 0:
    for ev in sel:
      let events = ev.events
      if EvRead in events:
        return true
  return false

## Read one event
method readEvent*(self : InotifyManager, timeout : int = 0) : InotifyEvent {.raises : [Exception], base.} = 
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
      raise newException(Exception, "Timeout")

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    raise newException(Exception, "Expected 4 bytes")

  wd = cast[cint](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    raise newException(Exception, "Expected 4 bytes")

  mask = cast[uint32](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    raise newException(Exception, "Expected 4 bytes")

  cookie = cast[uint32](buffer)

  if system.readBytes(self.file, buffer, 0, 4) != 4:
    raise newException(Exception, "Expected 4 bytes")

  {.hint : "Integer conversion is probably incorrect".}

  ln = cast[uint32](buffer)
  lni = cast[int](ln)

  if lni > 0:
    sq = newSeq[uint8](ln)
    let read = system.readBytes(self.file, sq, 0, lni)
    if read != lni:
      raise newException(Exception, format("Read %s. Expected %s", read, lni))
    name = cast[string](sq)
    # Strip 0x00 from the string. inotify spec says that messages can be padded
    # with those
    name = name.strip(chars = {'\x00'})

  return newInotifyEvent(wd, mask, cookie, name, path = self.getWatcher(cast[int](wd)).path)


