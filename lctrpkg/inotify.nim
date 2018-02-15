import posix.inotify as inotify
import posix.posix as posix
import strutils
import os
import selectors

# Inotify event class. Represents one inotify event
type
  InotifyEvent* = object of RootObj
    wd* : cint
    mask* : uint32
    cookie* : uint32
    name* : string

proc newInotifyEvent*(wd : cint, mask : uint32, cookie : uint32, name : string) : InotifyEvent =
  var i: InotifyEvent
  i.wd = wd
  i.mask = mask
  i.cookie = cookie
  i.name = name
  return i

## Inotify Watcher. Contains watcher information.
type
  InotifyWatcher* = object of RootObj
    wd* : FileHandle
    path* : string
    mask* : uint32

proc newInotifyWatcher*(fd : cint, path : string, mask : uint32) : InotifyWatcher =
  var w : InotifyWatcher
  w.wd = fd
  w.path = path
  w.mask = mask
  return w

## Inotify Manager. Contains overall inotify info
type
  InotifyManager* = object of RootObj
    fd : FileHandle
    file : File
    watchers : seq[InotifyWatcher]
    selector : Selector

proc newInotifyManager*() : InotifyManager = 
  var i : InotifyManager
  var fd : FileHandle = inotify.inotify_init()

  i.fd = fd
  if system.open(i.file, fd) != true:
    echo "Bad!"

  i.watchers = newSeq[InotifyWatcher]()

  ## Selector
  i.selector = newSelector()
  i.selector.register(cast[SocketHandle](i.fd), {EvRead}, nil)
  return i



## Add a new watcher
method addWatcher*(i : var InotifyManager, path : string, mask : uint32, recursive : bool = false ) : bool {.base.} = 
  var w : cint

  w = inotify.inotify_add_watch(i.fd, path, mask)
  if w < 0:
    echo "Bad Bad!"
    return false



  i.watchers.add(newInotifyWatcher(w, path, mask))
  if recursive:
    for kind, npath in os.walkDir(path):
      if kind == pcDir:
        discard i.addWatcher(npath, mask, recursive)


  return true

# Return true if there are any events to be read
# Timeout: milliseconds
method peek*(self : var InotifyManager, timeout : int) : bool = 
  let sel = self.selector.select(timeout)
  if len(sel) > 0:
    for ev in sel:
      let events = ev.events
      if EvRead in events:
        return true
  return false

## Read one event
method readEvent*(self : var InotifyManager, timeout : int = 0) : InotifyEvent {.raises : [Exception], base.} = 
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
    ## Strip 0x00 from the string. inotify spec says that messages can be padded
    ## with those
    name = name.strip(chars = {'\x00'})

  return newInotifyEvent(wd, mask, cookie, name)

method getWatcher*(self : InotifyManager, wd : int) : InotifyWatcher =
  for w in self.watchers:
    if w.wd == wd:
      return w
  raise newException(Exception, "No watcher")

