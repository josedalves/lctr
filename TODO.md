
# Daemon mode

* Handle:
    * [ ] File added
    * [ ] File removed
    * [ ] File moved
    * [ ] File modified
    * [ ] Directory added
    * [ ] Directory removed
    * [ ] Directory moved
    * [ ] Directory modified
* [ ] React to live monitor add and monitor del
* [ ] Provide a mechanism for graceful stop

# Indexing

* [ ] Limit depth
* [ ] Exclude directories

# Query mode

* Support queries on the following fields:
    * [x] Name
    * [x] Size
    * [ ] Type
    * [x] Owner: query by name and uid
    * [x] Group: query by name and gid
    * [x] Permissions
    * [ ] Last access time
    * [ ] Last modification time
    * [ ] Creation time
* [x] Support result limiting
* [x] Support result ordering
* [ ] Support depth limit
* [ ] Support exclude directories
* [ ] Support more expressive wildcards or regular expressions for paths and names. Currently, we are limited to sqlite's "like" wildcards.

# Metadata

* [ ] Add support for other types of metadata:
    * [ ] id3 tags
* [ ] Add support for arbitrary user tags on files and directories (`lctr tag <tag_name> <file_or_directory>`)

# General

* File sizes:
    * stat: what are the limitations on "size"?
    * sqlite: Sizes are being handled as Integers. Integers are limited to 64 bits (platform dependent?). How to handle arbitrarily large sizes (without major performance penalties)?
    * nim: Sizes are being handled as BiggestInt, which is (i think) platform dependent. Look into this.
* Handle multiple devices/partitions:
    * Currently, the application traverses the directory tree ignoring device and partition boundaries.
* Handle symbolic links (currently being ignored)
* Code cleanup
* Unicode support


