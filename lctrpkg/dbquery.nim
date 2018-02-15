
# DB query abstraction, with a limited subset of operations based around
# sqlite grammar

type

  # Expression kinds
  DBExpressionKind = enum
    DBExpressionKindUnaryOp
    DBExpressionKindBinaryOp

    # Literals
    DBExpressionKindLiteral

    # Table column expression
    DBExpressionKindTableColumn


  DBBinaryExpressionKind = enum
    DBBinaryExpressionKindEq
    DBBinaryExpressionKindNe
    DBBinaryExpressionKindGt
    DBBinaryExpressionKindGte
    DBBinaryExpressionKindLt
    DBBinaryExpressionKindLte
    DBBinaryExpressionKindLike
    DBBinaryExpressionKindAnd
    DBBinaryExpressionKindOr

  ## db literal
  DBLiteralKind = enum
    DBLiteralKindString
    DBLiteralKindInt
    DBLiteralKindBlob
    DBLiteralKindNull

  DBLiteralObj = object
    case kind : DBLiteralKind
    of DBLiteralKindString:
      stringValue : string
    of DBLiteralKindInt:
      intValue : int
    of DBLiteralKindNull:
      discard
    else:
      discard
  DBLiteral = ref DBLiteralObj


  # expression
  DBExpressionObj = object
    case kind : DBExpressionKind

    # Unary operation (<key> <op> <valu>
    #of DBExpressionKindUnaryOp:
    #  key : string
    #  value : string
    #  operation : DBUnaryOperation

    # Binary operation
    of DBExpressionKindBinaryOp:
      expression : DBBinaryExpressionKind
      lhs : DBExpression
      rhs : DBExpression

    # String literal
    of DBExpressionKindLiteral:
      literal : DBLiteral

    # Table column
    of DBExpressionKindTableColumn:
      schema : string
      table : string
      column : string

    else:
      discard
  DBExpression = ref DBExpressionObj

  ## Select operation
  DBSelectObj = object
    fields : seq[string]
    fromTables : seq[string]
    where : DBExpression
    groupBy : void
    orderBy : void
    limit : int
  DBSelect = ref DBSelectObj

  #DBQueryOpKind* = enum
  #  OpAnd,
  #  OpOr,
  #  OpMatch

  #DBMatchOperator* = enum
  #  DBMatchOperatorEq
  #  DBMatchOperatorNe
  #  DBMatchOperatorGt
  #  DBMatchOperatorGte
  #  DBMatchOperatorLt
  #  DBMatchOperatorLte
  #  DBMatchOperatorLike


  #DBQueryKind* = enum
  #  And,
  #  Or,
  #  DBQueryAdd,
  #  DBQueryUpdate,
  #  DBQueryRemove,
  #  DBQueryInfo

  #DBQueryMatchCriteriaObj = object
  #  field : string
  #  value : string
  #  operator : DBMatchOperator
  #DBQueryMatchCriteria* = ref DBQueryMatchCriteriaObj


  #DBQueryObj = object
  #  case kind* : DBQueryOpKind
  #  of OpAnd, OpOr:
  #    lhs* : DBQuery
  #    rhs* : DBQuery
  #  else:
  #    match* : DBQueryMatchCriteria

  #DBQuery* = ref DBQueryObj

  #DBSelectPartWhereObj = object
  #  discard

  #DBSelectQueryObj = object
  #  where : DBSelectPartWhereObj
  #  groupby : seq[string]
  #  limit : int
  #  having : void # reserved



  ### File attributes. Basically, a copy of 'stat' in a more readable format
  #IFindAttributes* = object of RootObj
  #  path : string
  #  owner : int
  #  group : int
  #  size : int
  #  mode : int
  #  ftype : int
  #  atime : int
  #  mtime : int
  #  ctime : int

  ### A Query
  #IFindQuery* = object of RootObj
  #  base : string
  #  attributes : IFindAttributes

#proc newDBBinaryExpression(kind : DBBinaryExpressionKind)

proc newDBLiteral(val : string) : DBLiteral = 
  result = new DBLiteral()


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

proc `$`*(m : DBQueryMatchCriteria) : string = 
    return "$1$2\"$3\"" % [m.field, $(m.operator), m.value]

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

proc newDBQueryMatchCriteria*(field : string, value : string, operator : DBMatchOperator) : DBQueryMatchCriteria = 
  result = new DBQueryMatchCriteria
  result.field = field
  result.value = value
  result.operator = operator

proc newDBQuery*(field : string, value : string, operator : DBMatchOperator) : DBQuery = 
  result = new DBQuery
  result.kind = OpMatch
  result.match = newDBQueryMatchCriteria(field, value, operator)

