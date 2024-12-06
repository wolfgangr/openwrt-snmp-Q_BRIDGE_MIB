#!/usr/bin/perl


# develop snmp helper for openwrt
# to deliver 802.1q vlan info for observium
# following Q-BRIDGE-MIB
#
# work in progress, don't use, expect the worst
# (C) Wolfgang Rosner Dez 2024 - wolfgangr@github.com
#
# test environment:
# - OpenWrt 23.05.5 on x86_64
# - bond (aka trunk aka LAG) of 4x1Gbit ethernet
# - vlans on top of bond
# - management outbound over mainboard eth
# - HP 1810 / 1820 switch backbone for vlans
# - target device is switch between those vlans
# - TBD: vlan aware openWRT Access points 
#
# Information & Inspirations pointers:
# https://mibs.observium.org/mib/Q-BRIDGE-MIB/
# https://mibs.observium.org/mib/BRIDGE-MIB/
# https://mibs.observium.org/mib/IP-MIB/
# https://github.com/librenms/librenms/blob/master/mibs/Q-BRIDGE-MIB#L1035
# http://www.net-snmp.org/docs/man/snmpd.conf.html
#	section "MIB-Specific Extension Commands"
# https://stackoverflow.com/questions/60885050/net-snmp-snpmd-pass-script-not-working-with-daemon-but-with-debug-mode
# 	(5 line ibash snmp pass test)
# https://github.com/pgmillon/observium/blob/master/scripts/ifAlias_persist
#	(40 line PERL pass_persist)
# https://sourceforge.net/p/net-snmp/code/ci/master/tree/local/pass_persisttest
#	(100 line PERL example pass_persist MIB tree)
# https://forum.openwrt.org/t/configure-snmp-to-show-vlans-in-q-bridge-mib/217289/3
# https://serverfault.com/questions/227952/snmpd-configuration-to-enable-bridge-mib-or-q-bridge-mib
# http://www.net-snmp.org/wiki/index.php/TUT:Using_and_loading_MIBS
# https://linux.die.net/man/1/snmp-bridge-mib
#	perl 1170 line snmp agent in snmpd package of e.g. debian et al
#	somebody@linuxbox:~ $ vi -R /usr/bin/snmp-bridge-mib
#	not compatible to /sys layout of DuT
#	depends on some perl cpan modules not readily available in openwrt

