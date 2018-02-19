
import parseopt2
import db
import strutils
import pegs
import datatypes
import tables
import sequtils
import db_sqlite
import ospaths
import posix


type
  QueryFieldType = enum
    QueryFieldTypeString
    QueryFieldTypeNum
    QueryFieldTypeSize
    QueryFieldTypeOrder
    QueryFieldTypeLimit
    QueryFieldTypeOType
    QueryFieldTypeUser
    QueryFieldTypeGroup
    QueryFieldTypeMode


let QueryFields : Table[string, QueryFieldType] = {
  "name" : QueryFieldTypeString,
  "size" : QueryFieldTypeSize,
  "type" : QueryFieldTypeOType,
  "owner" : QueryFieldTypeUser,
  "user" : QueryFieldTypeUser,
  "group" : QueryFieldTypeGroup,
  "mode" : QueryFieldTypeMode,
  "base" : QueryFieldTypeString,
  "order" : QueryFieldTypeOrder,
  "limit" : QueryFieldTypeLimit
}.toTable()

const FIELDS = [
  "name",
  "size",
  "type",
  "owner",
  "user",
  "group",
  "mode",
  "base",
  "order",
  "limit"
]



#PEGs for various components
const fieldRule = map(FIELDS, proc(x : string) : string = "'" & x & "'").join("/")
const valueRule = """('+' / '-' / '!')? \w+"""
const permissionRule = """('u' / 'g' / 'o' / 'a') [+, -] ('r' / 'w' / 'x')"""
const jointValueRule = "$2 / $1" % [valueRule, permissionRule]

const Rule = """
  rule <- {key ':' value}
  key <- $1
  value <- $2
""" % [fieldRule, jointValueRule]

let KeyValuePEG = peg """
  rule <- key ':' value
  key <- { $1 }
  value <- { $2 }
""" % [fieldRule, jointValueRule]

let rulePEG = peg(Rule)

let queryPEG = peg ("""
  start <- rule_group ';'? $ / rule_group \s* ';' \s* start $ / $
  rule_group <- {rule (\s* rule)*}
  rule <- key ':' value
""" & """
  key <- $1
  value <- $2
""" % [fieldRule, jointValueRule])


let sizeValuePEG = peg"""
  value <- {[+-]?} {[0-9]+} {sizemul}?
  sizemul <- 'k' / 'K' / 'm' / 'M' / 'g' / 'G' / 't' / 'T'
"""

let orderPEG = peg"""
  value <- {[+-]?} {field}
  field <- 'name' / 'size'
"""

let userGroupPEG = peg"""
  value <- {[+-]?} {field}
  field <- \w+
"""

let permissionsPEG = peg"""
  value <- {[ugoa]} {[+-]} {[rwx]} / {\d+}
"""

let filetypePEG = peg"""
  value <- {'!'?}  { 'b' / 'c' / 'd' / 'p' / 'f' / 'l' / 's' }
"""

proc modeToFileTypeMask(str : string) : int = 
  #[
  NOTE:
  
  From the "stat" manpage (man 2 stat):

  POSIX refers to the st_mode bits corresponding to the mask S_IFMT (see below)
  as the file type, the 12 bits corresponding to the mask 07777 as the file mode
  bits and the least significant  9 bits (0777) as the file permission bits.

  The following mask values are defined for the file type of the st_mode
  field:

    S_IFMT     0170000   bit mask for the file type bit field

    S_IFSOCK   0140000   socket
    S_IFLNK    0120000   symbolic link
    S_IFREG    0100000   regular file
    S_IFBLK    0060000   block device
    S_IFDIR    0040000   directory
    S_IFCHR    0020000   character device
    S_IFIFO    0010000   FIFO

  ]#
  result = 0

  for c in str:
    case c:
    of 'b': # block special
      result = result or 0o6
    of 'c': # character special
      result = result or 0o2
    of 'd': # directory
      result = result or 0o4
    of 'p': # FIFO (named pipe)
      result = result or 0o1
    of 'f': # regular file
      result = result or 0o10
    of 'l': # symbolic link
      result = result or 0o12
    of 's': # socket
      result = result or 0o14
    else:
      raise newException(Exception, "")

proc handleType(value : string) : DBQuery = 
  var mask : int

  if value =~ filetypePEG:
    mask = modeToFileTypeMask(matches[1])
    if matches[0].len() == 0:
      return newDBQuery("type", $mask, DBMatchOperatorEq, false)
    else:
      return newDBQuery("type", $mask, DBMatchOperatorNe, false)
  raise newException(Exception, "")

proc handleSize(key : string, value : string) : DBQuery = 
  var op : DBMatchOperator
  var base : string
  var mul : string

  if value =~ sizeValuePEG:

    case matches[0]:
    of "+":
      op = DBMatchOperatorGte
    of "-":
      op = DBMatchOperatorLte
    else:
      op = DBMatchOperatorGte
    base  = matches[1]
    if matches[2] != nil:
      mul = repeat("0", SizeExponentTable[matches[2][0]])
    else:
      mul = ""

  result = newDBQuery(key, base & mul, op)

proc handleOrder(value : string) : string = 
  if value =~ orderPEG:
   case matches[0]:
    of "+":
      return "$1 ASC" % value
    of "-":
      return "$1 DESC" % value
    else:
      return "$1" % value

proc nameToUID(name : string) : int = 
  var passwd = getpwnam(name)
  if passwd == nil:
    raise newException(Exception, "")
  return cast[int](passwd.pw_uid)

proc nameToGID(name : string) : int = 
  var gr = getgrnam(name)
  if gr == nil:
    raise newException(Exception, "")
  return cast[int](gr.gr_gid)

proc handleUser(value : string) : DBQuery = 
  var uid : int
  var uids : string
  var op : DBMatchOperator = DBMatchOperatorEq
  
  if value =~ userGroupPEG:
    if matches[0] == "-":
      op = DBMatchOperatorNe
    uids = matches[1]
  else:
    raise newException(Exception, "No")

  # Check if "value" is an integer
  try:
    uid = parseInt(uids)
  except:
    uid = nameToUID(uids)
  return newDBQuery("owner", $uid, op)

proc handleGroup(value : string) : DBQuery = 
  var gid : int
  var gids : string
  var op : DBMatchOperator = DBMatchOperatorEq

  if value =~ userGroupPEG:
    if matches[0] == "-":
      op = DBMatchOperatorNe
    gids = matches[1]
  else:
    raise newException(Exception, "No")

  # Check if "value" is an integer
  try:
    gid = parseInt(gids)
  except:
    gid = nameToGID(gids)
  return newDBQuery("\"group\"", $gid, op)

proc handlePermissions(value : string) : DBQuery = 
  var mask : int = 0
  var op : DBMatchOperator = DBMatchOperatorEq

  if value =~ permissionsPEG:
    if matches[0].len() > 0:
      var field : string = matches[2] & matches[0]

      if matches[1] == "-":
        return newDBQuery("$1" % field, "true", DBMatchOperatorEq)
      else:
        return newDBQuery("$1" % field, "true", DBMatchOperatorNe)
      ## TODO: Numeric mode!
      #elif matches[3].len() > 0:
      #  return newDBQuery("mode", value, DBMatchOperatorEq)
    else:
      raise newException(Exception, "")

proc modeQuery*(config : LCTRConfig, op : var OptParser) = 
  var query : string

  op.next()
  if op.kind != cmdArgument:
    raise newException(Exception, "BAAA!")

  query = op.key
  
  #echo "Query: $1" % query
  #echo "base: $1" % base

  ## Check if query string is malformed
  if not (query =~ queryPEG):
    echo queryPEG
    echo jointValueRule
    raise newException(Exception, "Query syntax error")


  var parts : seq[string] = @[]
  var g : seq[string]
  var order : seq[string] = @[]
  var limit : int
  
  #for group in findAll(query, queryPEG):
  for group in query.split(";"):
    g = @[]
    #order = nil
    #order.reset()
    limit = -1

    for keyvalue in  findAll(group, rulePEG):

      #echo keyvalue

      if keyvalue =~ KeyValuePEG:
        let key = matches[0]
        let value = matches[1]
        var op : DBMatchOperator

        echo key, value

        echo "Key:$1; Value:$2" % [key, value]

        case QueryFields[key]:
        of QueryFieldTypeString:
          g.add($newDBQuery(key, value, DBMatchOperatorLike))
        of QueryFieldTypeNum:
          discard
        of QueryFieldTypeSize:
          g.add($handleSize(key, value))
        of QueryFieldTypeOrder:
          #limit = parseInt(value)
          order.add(handleOrder(value))
        of QueryFieldTypeLimit:
          limit = parseInt(value)
        of QueryFieldTypeUser:
          g.add($handleUser(value))
        of QueryFieldTypeGroup:
          g.add($handleGroup(value))
        of QueryFieldTypeOType:
          g.add($handleType(value))
          discard
        of QueryFieldTypeMode:
          g.add($handlePermissions(value))

    #echo "G: $1" % g
    #for gg in g:
    #echo "Adding: $1" % [$g]
    parts.add("(" & join(g, " AND ") & ")")
    #echo parts
  echo parts.join(" OR ")

  var limits = ""
  var orders = ""

  if limit > 0:
    limits = "LIMIT $1" % $limit

  if len(order) > 0:
    orders = "ORDER BY $1" % order.join(",")


  echo limit
  echo limits

  var db_conn = newLCTRDBConnection(config.dbPath)

  echo "SELECT * from objects WHERE $1" % (parts.join(" OR "))
  for row in  db_conn.conn.getAllRows(sql ("SELECT path, name from objects WHERE $1 $2 $3" % [parts.join(" OR "), orders, limits])):
    echo joinPath(row[0], row[1])
    #echo row[0]


