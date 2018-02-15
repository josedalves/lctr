import tables

type
  LCTRConfigObj = object
    dbPath* : string
    verbose* : bool
  LCTRConfig* = ref LCTRConfigObj

  FieldRelashionship* = enum
    DontCare
    Greater
    Lesser
    GreaterOrEqual
    LesserOrEqual
    Equal
    NotEqual

  LCTRQueryFieldFilter* = object of RootObj
    field* : string
    value* : string
    relationship* : FieldRelashionship

  AttributeFields* = enum
    AttributeFieldPath
    AttributeFieldSize
    AttributeFieldFileType
    AttributeFieldOwner
    AttributeFieldGroup

  FileType* = enum
    FileTypeRegularFile
    FileTypeDirectory

const
  StringToField* = {
    "path" : AttributeFieldPath,
    "size" : AttributeFieldSize,
    "filetype" : AttributeFieldFileType
  }.toTable()

  FileTypeTable* = {
    'f' : FileTypeRegularFile,
    'd' : FileTypeDirectory,
  }.toTable()

  
  ## Table contains exponents for sizes in bytes. For example:
  ## SizeExponentTable['G'] = 9 --> G is 10^9 bytes
  SizeExponentTable* : Table[char, int] = toTable({
    'k' : 3,
    'K' : 3,
    'm' : 6,
    'M' : 6,
    'g' : 9,
    'G' : 9,
    't' : 12,
    'T' : 12
  })

  RelationToString* = {
    Greater : ">",
    Lesser : "<",
    Equal : "="
  }.toTable()
