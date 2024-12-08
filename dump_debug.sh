#!/bin/bash

# "dump index" | ./snmp_Q-BRIDGE-MIB.pl 2> test/dump_index
TARGETS='uci vlan dev index arp mib mibsort mibtab'

for TG in $TARGETS ; do
    # echo "$TG"
    CMD="echo 'dump $TG' | ./snmp_Q-BRIDGE-MIB.pl 2> test/dump_$TG"
    echo $CMD
    eval $CMD
done


