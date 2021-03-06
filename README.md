
**Warning**

This application is unlikely to devour data or cause any major damage.

However, this is absolute ALPHA quality, is missing loads of functionality
and probably has more bugs than... some thing with a lot of bugs. This is
nowhere close to being production ready.

You have been warned.

That said...

# LCTR (LoCaToR)

**lctr** is a tool for locating files that match some criteria, similar
to Unix's **locate**.

Like **locate**, **lctr** builds a database of files and their metadata, and
all search queries are directed at that database. Unlike **locate**, however,
**lctr** contains more information (currently, whatever **stat** provides, but in
the future may be able to contain other types of metadata) and allows for more
complicated queries.

For example, finding the top 10 largest files in your home can be done
by invoking the application as follows:

    lctr query 'base:/home/me order:-size limit:10'

To ensure that the database remains up to date, **lctr** can be instructed to
monitor certain directories for activity. Whenever file changes occur, the
database is updated automatically.

# Supported operating systems

Currently, this application targets **Linux** Operating Systems only.

In the future, it may target other platforms.

# Build instructions

To build:

    nimble build

A binary named **lctr** will be created.

# Usage

## Basic usage

First, a database must be created:

    lctr --db:/home/me/lctr.db createdb

This creates an empty database file at "/home/me/lctr.db". If the path is
not specified via "--db", the database will be created in the current directory.

Then, the database needs to be populated. To populate the database, the "refresh"
command is used:

    lctr --db:/home/me/lctr.db refresh /home/me

This will trawl through the directory "/home/me" and its descendents and build
up an index of the files and directories therein.

To perform queries, use the "query" command:

    lctr --db:/home/me/lctr.db query 'name:*.foo'

To use the daemon, a monitor must first be configured. Let us create a monitor
for the entire home directory:

    lctr --db:/home/me/lctr.db monitor add /home/me

Now the daemon can be started:

    lctr --db:/home/me/lctr.db daemon

# Detailed usage

## Common options

The following options are common for every mode:
* --db:path: Path to the database file. If none is specified, **lctr** looks for a file named **db** on the current directory
* -v/--verbose: Be more verbose

## Creating the database

    lctr createdb

This creates the database. Use "--db" to specify location

Examples:

    lctr --db:~/mydb createdb


## Querying the database

    lctr query '<query_string>'


A query string is made up of one or more field/value pairs with the following
format:

    field:value

Valid fields are:

    name: File name
    size: File size
    base: Base search location
    limit: Limit number of results
    order: Order of results

(More fields will be added in the future)

Note: The use of single quotes around the query string is recommended to
prevent the shell from trying to do funny things with the string.

## Query fields

### base
    base:<path>

Base search path. All searches are recursive from the given base path.  If none
is given, "/" is used as the base path.

Examples:

    ## Match all files named foo.bar in the current directory tree
    lctr query 'base:. name:foo.bar'

    ## Match all files named foo.bar in the directory /home/foo/
    lctr query 'base:/home/foo/ name:foo.bar'

### name
    name:<name>

Match by filename. There is some basic wildcard support: * matches any character
0 or more times and ? matches any character 1 or 0 times.

Examples:

    ## Match all files named foo.bar
    lctr query "name:foo.bar"

    ## Match all files that have the .nim extension:
    lctr query "name:*.nim"

### size
    size:[+, -]<size>[k, m, g, t]

size can be used to select files that match only certain size criteria. The
"+" specifies that only files of size greater than "size" will match and the
"-" specifies that only files of size lesser than "size" will match. They
are optional (default to "+")

The k, m, g and t (case insensitive) specifiers are convenient multipliers
for kilobyte, megabyte, gigabyte and terabyte.

Examples:

    ## Get all files of size greater than 100 megabytes:
    lctr query 'size:+100m'

    ## Get all files of size lesser than 1 Gigabyte:
    lctr query 'size:-1G'


### limit
    limit:<n>

Used to limit number of results.

Examples:

    ## Limit results to 10
    lctr query 'size:+1k limit:10'

### order
    order:[+, -]<field>

Used to order results by a given field. "-" indicates that results should be
ordered by descending order and "+" indicates that results sould be ordered
by ascending order.

Examples:

    ## Order by name ascending
    lctr query 'size:+1k order:+name'

## Monitors

Monitors can be used to monitor for filesystem changes and to automatically
update the database as those changes occur.

Before monitors can be used, they must be set up. Monitors can by recursive
or not. Recursive monitors monitor the selected directory plus
all descendends. Non-recursive monitors monitor only the specified directory.

### Adding a monitor

    lctr monitor add [recursive] <path>

Adds a monitor for "path".

Example:

    lctr monitor add /home/me/foo

### Removing a monitor

    lctr monitor del <path>

Removes a monitor currently associated with "path". If no such monitor exists,
this does nothing.

Example:

    lctr monitor del /home/me/foo

## Daemon

    lctr daemon

In daemon mode, for each monitor added with "lctr monitor add" above, **lctr**
listens to filesystem events and automatically updates the database as files
are added, removed and modified.

The daemon runs forever until killed.

