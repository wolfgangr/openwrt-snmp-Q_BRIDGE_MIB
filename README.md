(see the source code for details and pointers)

## Task to be solved:  
While openWrt is able to implement **tagged vlans** as of **802.1Q**, it's snmpd obviously ist not.  
This script ist developped and tested for a **openWRT router** only on **x86** platform.  
Implementation for wlan AP is planned.  

The final goal is to gain some high level insight into the whole network infrastructure containing e. g.
- openWRT router
- openWRT access points
- enterprise grade manageable switches (HP ProCurve 1810 and HPE OfficeConnect 1820 in my case)

using some snmp-aware surveillance system ([observium](https://www.observium.org/) in my case)

## state of the code
early development state - consider as untestet and dangerous  
- drafted on development environment
- deployed to openWRT router
- modfied until it delivers snmpd data to observium
- watch for and fix some really obvious nonsense

## draft of intended deployment cycle 
- make sure that 802.1Q, snmpd and perl fits to target device
- copy `/dev/config/network`, `/proc/net`
and output form `uci show network` and `ip link`  
from openWRT target to development workstation in `etc/` `proc/` `uci/` and `ip/` directories
- on the development machine, set `$on_target=0;` in the source and uncomment use warnings|strict|Data::Dumper
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
-  to be continued ----

