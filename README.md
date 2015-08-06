LVM-System-Backup
=================

The script creates a live backup of every logical volume in multiple volume groups using lvm snapshots. It is also capable of backing up a Samba ADDC and MySQL databases. The success of the backups can be monitored with nagios. Old backups are deleted after n days.

Docs
=================
https://github.com/MrCrankHank/LVM-System-Backup/wiki/Usage

ToDo
=================
- [ ] Create Wiki entry for complete system restore
- [ ]  Create Wiki entry for samba restore
- [ ]  Create Wiki entry for MySQL database restore
- [ ]  Support for system backup on gpt partitions
- [ ]  Check if APT lock exists
- [ ]  Support for Wake on lan
- [ ]  Shutdown remote server after backup
- [ ]  Add debug mode
- [ ]  Config option for compression + compression level
- [ ]  Fix snapshot size calculation
- [ ]  Add error handling functions (handle_error, handle_error_critical)
- [ ]  Own file for functions
- [ ] Check if snapshot already exists
- [ ] Rewrite this in python...

License
=================

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
