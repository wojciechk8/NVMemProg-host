## Host PC software for [NVMemProg](https://github.com/wojciechk8/NVMemProg-hardware) memory programmer.

*Note: This is still a work in progress...*

The program is written in Vala language. Memory devices definitions are stored in file chips.db, which
is an SQLite database. Adding new devices will be possible in the GUI interface sometime. Files in firmware
directory are compiled firmwares for the microcontroller (source code repository is [here](https://github.com/wojciechk8/NVMemProg-firmware)).
FPGA configurations are located in the fpga/ directory (as *rbf* files; source code available in the hardware repository).


### Dependencies
* GLib
* GTK+-3.0
* libusb-1.0
* sqlite3
* gtkhex-3


### Building
After fulfilling dependencies, run:
```
make
```


### License
This software is licensed under GPL version 3. See the COPYING file for the full text of the license.
