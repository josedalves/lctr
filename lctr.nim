import posix.inotify as pinotify
import os
import parseopt2
import lctrpkg.datatypes
import db_sqlite
import posix
import lctrpkg.inotify
import lctrpkg.db
import lctrpkg.monitors
import lctrpkg.query
import lctrpkg.daemon
import lctrpkg.index

const
  DEFAULT_DB_LOCATION = "db"

const
  INOTIFY_EVENTS = (pinotify.IN_MODIFY or
    pinotify.IN_ATTRIB or
    pinotify.IN_CLOSE_WRITE or
    pinotify.IN_MOVE or
    pinotify.IN_CREATE or
    pinotify.IN_DELETE or
    pinotify.IN_DELETE_SELF or
    pinotify.IN_MOVE_SELF
  )

proc usage() = 
  echo "LCTR [options] <command> [command options]"
  echo "Available commands:"
  echo "\t find -- query the database"
  echo "\t createdb -- create database"
  echo "\t daemon -- enable daemon"
  echo "\t monitor -- monitor ops"

proc main =
  var op : OptParser = initOptParser()
  var config = new LCTRConfig

  config.dbPath = DEFAULT_DB_LOCATION
  config.verbose = false

  op.next()
  while op.kind != cmdEnd:
    case op.kind:
      of cmdArgument:
        case op.key:
          of "daemon":
            #mainThread(config)
            modeDaemon(config)
          of "createdb":
            echo config.dbPath
            var db_conn = newLCTRDBConnection(config.dbPath)
            echo "creating database"
            db_conn.createDB()
            db_conn.close()
            echo "done"
            return
          of "monitor":
            modeMonitor(config, op)
            return
          of "refresh":
            modeRefresh(config, op)
            return
          of "query":
            modeQuery(config, op)
            return
          else:
            echo "Invalid option"
            usage()
            return
      of cmdLongOption:
        if op.key == "db":
          config.dbpath = op.val
        if op.key == "verbose":
          config.verbose = true
      of cmdShortOption:
        if op.key == "d":
          config.dbPath = op.val
        if op.key == "v":
          config.verbose = true
      else:
        continue
    op.next()
  usage()

main()

