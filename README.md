
see the source code for configuration, details and pointers

## Task to be solved:  
While openWrt is able to implement **tagged vlans** as of **802.1Q**, it's snmpd obviously ist not equipped to supply the information as defined by Q-BRIDGE-MIB and the higher level BRIDGE-MIB.   
The perl script at hand ist developed and tested for a **openWRT router only** on **x86** platform.  
Implementation for wlan AP is planned.  

The final goal is to gain some high level insight into the whole network infrastructure containing e. g.
- openWRT router
- openWRT access points
- enterprise grade manageable switches (venerable HP ProCurve 1810 and HPE OfficeConnect 1820 in my case)

using some snmp-aware network surveillance system ([observium](https://www.observium.org/) in my case)

## State of the code
Early development state - consider as untestet and dangerous  
- drafted on development environment
- deployed to openWRT router
- modified until it delivers snmpd data to observium
- watch for and fix some really obvious nonsense

## Draft of intended deployment cycle 
- make sure that 802.1Q, snmpd and perl fits to target device
- copy `/dev/config/network`, `/proc/net`
and output form `uci show network` and `ip link`  
from openWRT target to development workstation in `etc/` `proc/` `uci/` and `ip/` directories
- on the development machine, set `$on_target=0;` in the source and uncomment `use warnings|strict|Data::Dumper`
- check the `snmpd pass_persist` interface (`PING, get, getnext`) on STDIN / STDOUT
- there is a superset of commands for debug purposes as well
  - `dump <var>` to dump different data structures captured from system state
  - `raw/rawnext <OID>` - similiar to `get/getnext`, but dump more internal data
  - `list|walk [@|start-oid [end-oid]]` perform OID lookup similiar to snmpget / snmpwalk,
    (but without client-server communication)
    - `list` shows only definitions from `*.raw` MIB destillates, finds next lexical entry even if no precise match
    - `walk` includes system state data if available, requires matching entry for start
- when satisfied,
  - copy (e.g. by `scp`) the script to `/usr/local/bin/snmp_Q-BRIDGE-MIB.pl` on openWRT target
  - copy usr/local/share/snmp/*.raw to target
  - on the target, set `$on_target=1;` in the source and comment out `use warnings|strict|Data::Dumper` lines
  - check whether debug and `pass_persist` interface are working as intended
  (`list` and `walk` are available on target as well, but expect to miss stuff relying on `Data::Dumper`)
  - enable skript in `/etc/config/snmpd` and call `/etc/init.d/snmpd restart` (see stanza below)
  - test the relevant OIDs with some snmp client
 
configuration stanza in `/etc/config/snmpd`:

```
config pass
        option miboid '.1.3.6.1.2.1.17'
        option prog '/usr/local/bin/snmp_Q-BRIDGE-MIB.pl'
        option persist 1
```

This should deliver the whole dot1dBridge below 1.3.6.1.2.1.17  
```
snmpwalk -v2c -c mysecret myrouter 1.3.6.1.2.1.17
```

only qBridgeMIB at 1.3.6.1.2.1.17.7   
```
snmpwalk -v2c -c mysecret myrouter 1.3.6.1.2.1.17.7
```  

see `usr/local/share/snmp/tab_*BRIDGE-MIB.raw` or ask the internet for details

## UNLICENSE
This work is covered by UNLICENSE.

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

For details, see https://unlicense.org/


