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

## draft of development cycle 
- copy `/dev/config/network`, `/proc/net`
and output form `uci show network` and `ip link`  
from openWRT target to development workstation
-  to be continued ----

