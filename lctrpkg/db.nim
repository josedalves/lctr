# Notes:
# - times: we only store up to seconds precision. Adding nanosecond precisions
# is far too much granularity, and would add significant overhead to the
# database (+3 integers)
#
import db_sqlite
import strutils
from ospaths import splitPath, DirSep, parentDirs
import posix
import tables
import sequtils
import dbfields


type
  DBQueryOpKind* = enum
    OpAnd,
    OpOr,
    OpMatch

  DBOrderKind* = enum
    OrderAsc
    OrderDesc

  DBMatchOperator* = enum
    DBMatchOperatorEq
    DBMatchOperatorNe
    DBMatchOperatorGt
    DBMatchOperatorGte
    DBMatchOperatorLt
    DBMatchOperatorLte
    DBMatchOperatorLike
    DBMatchOperatorBitAnd
    DBMatchOperatorBitOr

  DBQueryKind* = enum
    And,
    Or,
    DBQueryAdd,
    DBQueryUpdate,
    DBQueryRemove,
    DBQueryInfo

  DBQueryMatchCriteriaObj = object
    field : string
    value : string
    operator : DBMatchOperator
    quote : bool
  DBQueryMatchCriteria* = ref DBQueryMatchCriteriaObj

  DBQueryObj = object
    case kind* : DBQueryOpKind
    of OpAnd, OpOr:
      lhs* : DBQuery
      rhs* : DBQuery
    else:
      match* : DBQueryMatchCriteria
  DBQuery* = ref DBQueryObj

  DBSelectObj = object
    fields : seq[string]
    table : string
    where : DBQuery
    order : DBOrderBy
    limit : int

  DBOrderByObj = object
    field : string
    order : DBOrderKind
  DBOrderBy = ref DBOrderByObj

  # File attributes. Basically, a copy of 'stat' in a more readable format
  LCTRAttributesObj* = object of RootObj
    name* : string
    path* : string
    owner : int
    group : int
    size : int
    atime : int
    mtime : int
    ctime : int
    mode : LCTRAttributeMode
  LCTRAttributes* = ref LCTRAttributesObj

  LCTRAttributeModeObj = object
    ftype : int
    xu : bool
    xg : bool
    xo : bool
    ru : bool
    rg : bool
    ro : bool
    wu : bool
    wg : bool
    wo : bool
    suid : bool
    sgid : bool
    svtx : bool
  LCTRAttributeMode =  ref LCTRAttributeModeObj

  LCTRDBConnection* = object of RootObj
    conn* : DbConn
    file* : string

  LCTRDBQueryResult* = object of RootObj
    a : int
  
  LCTRMonitorSpec* = object of RootObj
    name : string
    path : string
    recursive : bool

# SQL STATEMENTS

proc newLCTRAttributeMode(mode : int) : LCTRAttributeMode =
  result = new LCTRAttributeMode

  # Type
  result.ftype = (mode and S_IFMT) shr 12

  # user
  result.xu = (mode and S_IXUSR) > 0
  result.ru = (mode and S_IRUSR) > 0
  result.wu = (mode and S_IWUSR) > 0

  # group
  result.xg = (mode and S_IXGRP) > 0
  result.rg = (mode and S_IRGRP) > 0
  result.wg = (mode and S_IWGRP) > 0

  # other
  result.xo = (mode and S_IXOTH) > 0
  result.ro = (mode and S_IROTH) > 0
  result.wo = (mode and S_IWOTH) > 0

  # suid, etc
  result.suid = (mode and S_ISUID) > 0
  result.sgid = (mode and S_ISGID) > 0
  result.svtx = (mode and S_ISVTX) > 0

proc newLCTRAttributes*(name : string, path : string, info : Stat) : LCTRAttributes = 
  var mode = cast[int](info.st_mode)
  result = new LCTRAttributes
  result.name = name
  result.path = path
  result.owner = cast[int](info.st_uid)
  result.group = cast[int](info.st_gid)
  result.size = cast[int](info.st_size)
  result.mode = newLCTRAttributeMode(mode)
  result.atime = cast[int](info.st_atim.tv_sec)
  result.ctime = cast[int](info.st_ctim.tv_sec)
  result.mtime = cast[int](info.st_mtim.tv_sec)

proc newLCTRAttributes*(path : string, info : Stat) : LCTRAttributes = 
  var mode = cast[int](info.st_mode)
  result = new LCTRAttributes
  result.name = ""
  result.path = path
  result.owner = cast[int](info.st_uid)
  result.group = cast[int](info.st_gid)
  result.size = cast[int](info.st_size)
  result.mode = newLCTRAttributeMode(mode)
  result.atime = cast[int](info.st_atim.tv_sec)
  result.ctime = cast[int](info.st_ctim.tv_sec)
  result.mtime = cast[int](info.st_mtim.tv_sec)

proc newLCTRDBConnection*(file : string) : LCTRDBConnection = 
  var
    conn : LCTRDBConnection
  conn.conn = open(file, nil, nil, nil)
  conn.file = file
  ## Enable foreign key support
  conn.conn.exec(sql"PRAGMA foreign_keys=ON;")
  #conn.conn.exec(sql"PRAGMA journal_mode=WAL;")
  return conn

method createDB*(self : LCTRDBConnection, overwrite : bool = false) {.noSideEffect.} = 
  self.conn.exec(sql"BEGIN")

  self.conn.exec(sql"DROP TABLE IF EXISTS meta;")
  self.conn.exec(sql"DROP TABLE IF EXISTS objects;")
  self.conn.exec(sql"DROP TABLE IF EXISTS monitors;")

  self.conn.exec(sql"""
  CREATE TABLE meta (
    "version" INTEGER PRIMARY KEY CHECK ("version" = 1)
  )
  """)

  self.conn.exec(sql"""
  INSERT INTO meta ("version") VALUES (1)
  """)

  self.conn.exec(sql(SQL_CREATE_TABLE_OBJECTS))

  self.conn.exec(sql"""
  CREATE TABLE monitors (
    "path" VARCHAR PRIMARY KEY NOT NULL,
    "recursive" INTEGER DEFAULT 0
  )
  """)

  #self.conn.exec(sql"""
  #CREATE TABLE parentchild (
  #  "parent" INTEGER PRIMARY KEY NOT NULL,
  #  "child" INTEGER PRIMARY KEY NOT NULL
  #)
  #""")

  self.conn.exec(sql"COMMIT")



# Monitors

method addMonitor*(self : LCTRDBConnection, path : string, recursive : bool) : bool =
  {.hint : "FIXME: Handle errors" .}
  self.conn.exec(sql SQL_INSERT_MONITOR, path, $cast[int](recursive))
  return true

method delMonitor*(self : LCTRDBConnection, path : string ) : bool =
  {.hint : "FIXME: Handle errors" .}
  self.conn.exec(sql SQL_DELETE_MONITOR, path)
  return true

method getMonitors*(self : LCTRDBConnection) : seq[tuple[path : string, recursive : bool]] =
  result = @[]
  for m in  self.conn.getAllRows(sql"SELECT * from monitors;"): ## [path, recursive]
    result.add((path : m[0], recursive : cast[bool](parseInt(m[1]))))

# Get

method getDirectoryFileNames*(self : LCTRDBConnection, directory : string) : seq[string] = 
  result = @[]

  for row in self.conn.rows(sql SQL_GET_DIRECTORY_FILENAMES, directory):
    result.add(row[0])
  #echo result

method getAllFilenames*(self : LCTRDBConnection) : Table[string, seq[string]] = 
  result = initTable[string, seq[string]]()

  for row in self.conn.rows(sql"SELECT name, path FROM objects"):
    let name = row[0]
    let path = row[1]
    if result.hasKey(path):
      result[path].add(name)
    else:
      result[path] = @[name]

# Objects
#
method rmFilesFromDirectory*(self : LCTRDBConnection, dir : string, files : seq[string]) = 
  self.conn.exec(sql("""DELETE FROM objects where path=? and name IN ($1)""" % files.join(",")), dir)

method rmFilesFromDirectoryNot*(self : LCTRDBConnection, dir : string, files : seq[string]) = 
  self.conn.exec(sql("""DELETE FROM objects where path=? and name NOT IN ($1)""" % files.join(",")), dir)

method rmDirTree*(self : LCTRDBConnection, dir : string) = 
  self.conn.exec(sql("""DELETE FROM objects where path=? or path like ?"""), dir, dir&"/%")

method addObject*(self : LCTRDBConnection, attributes : LCTRAttributes) {.noSideEffect.} =
  self.conn.exec(
    sql SQL_ADD_OBJECT,
    attributes.name,
    attributes.path,
    attributes.owner,
    attributes.group,
    attributes.size,

    attributes.mode.ftype,

    attributes.mode.xu,
    attributes.mode.xg,
    attributes.mode.xo,

    attributes.mode.ru,
    attributes.mode.rg,
    attributes.mode.ro,

    attributes.mode.wu,
    attributes.mode.wg,
    attributes.mode.wo,

    attributes.mode.suid,
    attributes.mode.sgid,
    attributes.mode.svtx,

    attributes.atime,
    attributes.mtime,
    attributes.ctime
  )

method addOrReplaceObject*(self : LCTRDBConnection, attributes : LCTRAttributes) {.noSideEffect.} =
  self.conn.exec(
    sql SQL_ADD_OR_REPLACE_OBJECT,
    attributes.name,
    attributes.path,
    attributes.owner,
    attributes.group,
    attributes.size,

    attributes.mode.ftype,

    attributes.mode.xu,
    attributes.mode.xg,
    attributes.mode.xo,

    attributes.mode.ru,
    attributes.mode.rg,
    attributes.mode.ro,

    attributes.mode.wu,
    attributes.mode.wg,
    attributes.mode.wo,

    attributes.mode.suid,
    attributes.mode.sgid,
    attributes.mode.svtx,

    attributes.atime,
    attributes.mtime,
    attributes.ctime
  )

method updateObject*(self : LCTRDBConnection, attributes : LCTRAttributes) {.noSideEffect.} =
  discard self.conn.execAffectedRows(
    sql SQL_UPDATE_OBJECT,
    attributes.owner,
    attributes.group,
    attributes.size,

    attributes.mode.ftype,

    attributes.mode.xu,
    attributes.mode.xg,
    attributes.mode.xo,

    attributes.mode.ru,
    attributes.mode.rg,
    attributes.mode.ro,

    attributes.mode.wu,
    attributes.mode.wg,
    attributes.mode.wo,

    attributes.mode.suid,
    attributes.mode.sgid,
    attributes.mode.svtx,

    attributes.atime,
    attributes.mtime,
    attributes.ctime,
    attributes.name,
    attributes.path
  )

method delObject*(self : LCTRDBConnection, name : string, path : string) {.base, noSideEffect.} =
  self.conn.exec(sql SQL_DELETE_OBJECT, name, path)

method handleQuery*(self : LCTRDBConnection, kind : DBQueryKind, attributes : LCTRAttributes) : LCTRDBQueryResult {.gcsafe.} = 
  var result : LCTRDBQueryResult

  let sp = splitPath(attributes.path)

  if kind == DBQueryAdd:
    self.addObject(attributes)
  elif kind == DBQueryRemove:
    self.delObject(attributes.name, attributes.path)
  elif kind == DBQueryInfo:
    discard

method query*(self : LCTRDBConnection, query : string, base : string) : seq[Row] =
  return self.conn.getAllRows(sql(query), base)

method close*(self : LCTRDBConnection) {.noSideEffect.} = 
  self.conn.close()

proc `$`(op : DBMatchOperator) : string =
  case op:
    of DBMatchOperatorEq:
      return "="
    of DBMatchOperatorNe:
      return "!="
    of DBMatchOperatorGt:
      return ">"
    of DBMatchOperatorGte:
      return ">="
    of DBMatchOperatorLt:
      return "<"
    of DBMatchOperatorLte:
      return "<="
    of DBMatchOperatorLike:
      return " LIKE "
    of DBMatchOperatorBitAnd:
      return " & "
    of DBMatchOperatorBitOr:
      return " | "

proc `$`*(m : DBQueryMatchCriteria) : string = 
    if m.quote:
      return "$1$2\"$3\"" % [m.field, $(m.operator), m.value]
    else:
      return "$1$2$3" % [m.field, $(m.operator), m.value]

proc `$`*(q : DBQuery) : string =
  if q == nil:
    return "nil"
  case q.kind:
    of OpAnd:
      return "$1 AND ($2)" % [$(q.lhs), $(q.rhs)]
    of OpOr:
      return "$1 OR ($2)" % [$(q.lhs), $(q.rhs)]
    else:
      return $(q.match)

proc newDBQueryMatchCriteria*(field : string, value : string, operator : DBMatchOperator, quote = true) : DBQueryMatchCriteria = 
  result = new DBQueryMatchCriteria
  result.field = field
  result.value = value
  result.operator = operator
  result.quote = quote

proc newDBQuery*(field : string, value : string, operator : DBMatchOperator, quote : bool = true) : DBQuery = 
  result = new DBQuery
  result.kind = OpMatch
  result.match = newDBQueryMatchCriteria(field, value, operator, quote)

