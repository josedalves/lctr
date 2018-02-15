
import parseopt2
import db
import strutils
import pegs
import datatypes
import tables
import sequtils
import db_sqlite
import ospaths

const Rule = """
  rule <- {key ':' value}
  key <- 'name' / 'size' / 'limit' / 'order' / 'base'
  value <- ('+' / '-')? \w+
"""

let KeyValuePEG = peg """
  rule <- key ':' value
  key <- {'name' / 'size' / 'limit' / 'order' / 'base'}
  value <- {('+' / '-')? \w+}
"""

let rulePEG = peg(Rule)


let sizeValuePEG = peg"""
  value <- {[+-]?} {[0-9]+} {sizemul}?
  sizemul <- 'k' / 'K' / 'm' / 'M' / 'g' / 'G' / 't' / 'T'
"""

let orderPEG = peg"""
  value <- {[+-]?} {field}
  field <- 'name' / 'size'
"""

let queryPEG = peg ("""
  start <- rule_group ';'? $ / rule_group \s* ';' \s* start $ / $
  rule_group <- {rule (\s* rule)*}
  rule <- key ':' value
  key <- 'name' / 'size' / 'limit' / 'order' / 'base'
  value <- ('+' / '-')? \w+
""")


type
  QueryBase = tuple[key : string, value : string, op : DBMatchOperator]

  QueryFieldType = enum
    QueryFieldTypeString
    QueryFieldTypeNum
    QueryFieldTypeSize
    QueryFieldTypeOrder
    QueryFieldTypeLimit


let QueryFields : Table[string, QueryFieldType] = {
  "name" : QueryFieldTypeString,
  "base" : QueryFieldTypeString,
  "size" : QueryFieldTypeSize,
  "order" : QueryFieldTypeOrder,
  "limit" : QueryFieldTypeLimit
}.toTable()

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

  #echo "SELECT * from objects WHERE $1" % (parts.join(" OR "))
  for row in  db_conn.conn.getAllRows(sql ("SELECT path, name from objects WHERE $1 $2 $3" % [parts.join(" OR "), orders, limits])):
    echo joinPath(row[0], row[1])
    #echo row[0]


