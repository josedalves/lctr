import strutils
import sequtils
import db_sqlite
import tables

type
  DBType = enum
    Integer,
    Text

proc `$`(x : DBType) : string = 
  case x:
  of Integer:
    return "INTEGER"
  of Text:
    return "TEXT"


# All fields for "object" table
const ALL_OBJECT_FIELDS_TABLE : OrderedTable[string, DBType] = {
  "name" : Text,
  "path" : Text,
  "owner" : Integer,
  "group" : Integer,
  "size" : Integer,
  "type" : Text,
  "xu" : Integer,
  "xg" : Integer,
  "xo" : Integer,
  "ru" : Integer,
  "rg" : Integer,
  "ro" : Integer,
  "wu" : Integer,
  "wg" : Integer,
  "wo" : Integer,
  "suid" : Integer,
  "sgid" : Integer,
  "svtx" : Integer,
  "atime" : Integer,
  "mtime" : Integer,
  "ctime" : Integer
}.toOrderedTable()

const NFIELDS : int = (proc () : int = 
  result = 0
  for f in ALL_OBJECT_FIELDS_TABLE.keys():
    inc(result)
)()

# All fields from "objects"
const ALL_OBJECT_FIELDS = (
  proc () : seq[string] =
    result = @[]
    for x in ALL_OBJECT_FIELDS_TABLE.keys():
      result.add(x)
)()

# All fields for "object" table, quoted and comma separated
const ALL_OBJECT_FIELDS_QUOTED = (proc () : string = map(ALL_OBJECT_FIELDS, proc (x : string) : string = "\""&x&"\"").join(",\n"))()

# All fields for "object" table, quoted and prepated for UPDATE
const ALL_OBJECT_FIELDS_QUOTEDU = (proc () : string = map(ALL_OBJECT_FIELDS[2..^1], proc (x : string) : string = "\""&x&"\"=?").join(",\n"))()
#                                                                            ^
#                                                                      Hacky |



# All fields for "object" table, quoted and prepared for CREATE
const ALL_OBJECT_FIELDS_QUOTEDC = (
  proc () : string =
    var s : seq[string] = @[]
    for key, value in ALL_OBJECT_FIELDS_TABLE.pairs():
      s.add("\""&key&"\" $1 NOT NULL" % $value)
    return s.join(",\n")
)()

# Insert, update, delete
const SQL_ADD_OBJECT* = """
  INSERT INTO objects (
    $1
  )
  VALUES (
    $2
  )
""" % [
  ALL_OBJECT_FIELDS_QUOTED,
  cycle(@['?'], NFIELDS).join(",")
]

const SQL_ADD_OR_REPLACE_OBJECT* = """
  INSERT OR REPLACE INTO objects (
    $1
  )
  VALUES (
    $2
  )
""" % [
  ALL_OBJECT_FIELDS_QUOTED,
  cycle(@['?'], NFIELDS).join(",")
]

const SQL_UPDATE_OBJECT* = """
  UPDATE  objects set 
    $1
  WHERE
    "name"=? AND "path"=?
""" % [ ALL_OBJECT_FIELDS_QUOTEDU ]

const SQL_DELETE_OBJECT* = """
  DELETE FROM objects where name=? and path=?
"""

# Create
const SQL_CREATE_TABLE_OBJECTS* = """
CREATE TABLE objects (
  $1,
  PRIMARY KEY (name, path)
)
""" % [
  ALL_OBJECT_FIELDS_QUOTEDC
]

const SQL_CREATE_INDEX_OBJECTS* = """
CREATE INDEX iobjects (
  $1
  PRIMARY KEY (name, path)
)
""" % [
  ALL_OBJECT_FIELDS_QUOTED
]

# Monitors
const SQL_INSERT_MONITOR* = """INSERT INTO monitors (path, recursive) VALUES (?, ?) """
const SQL_DELETE_MONITOR* = """DELETE FROM monitors where path=?"""


# Get
const SQL_GET_DIRECTORY_FILENAMES* = """
  SELECT name from objects WHERE path=?
"""
