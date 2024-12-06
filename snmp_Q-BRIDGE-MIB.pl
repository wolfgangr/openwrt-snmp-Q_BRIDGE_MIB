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

my $debug=5; 		# debug level
my $on_target=0;	# 0 for debian test environment, 1 for openWrt target widget

unless ($on_target) {
  use warnings;
  use strict;
  use Data::Dumper;   
}

# config of the real gadget data source
my $uci_show_net = '/sbin/uci show network';
my $proc_dir = '/proc';
my $etc_dir  = '/etc';

# pseudo data source for dev env
unless ($on_target) {
  my $emulation_root = '.';
  $uci_show_net = "cat $emulation_root/uci/show/network";
  $proc_dir = "$emulation_root/proc";
  $etc_dir  = "$emulation_root/etc";
}

debug(5, sprintf("uci: |%s| -  proc: |%s| -  etc: |%s| \n",
	$uci_show_net, $proc_dir, $etc_dir ));


# my $counter = 0;
# my $place = ".1.3.6.1.4.1.8072.2.255";
my $mib_root = ".1.3.6.1.2.1.17.1.4.1.2";  ### BRIDGE-MIB


while (<>){
  if (m!^PING!){
    print "PONG\n";
    next;
  }

  if (m!^exit!){
    print "- cancelled -\n";
    exit;
  }


  my $cmd = $_;
  my $req = <>;
  my $ret;
  chomp($cmd);
  chomp($req);

  debug (5, "input: cmd= $cmd - req= $req...\n");

  if ( $cmd eq 'getnext' ) {
    debug (5, "     ### TBD: doing getnext\n");
  } elsif ( $cmd eq 'get' ) {
    debug (5, "     ### TBD: doing get\n");
  } else {
    debug(2, "cmd= $cmd - not recognized\n");
    next;
  }
  debug (5, "    TBD: deliver some data\n");

}




die "   ===== DEBUG exit or error? ===== ";
# =============== subs =================


sub debug {
  my ($l, $msg) = @_;
  print STDERR 'DEBUG: ', $msg if $l <= $debug;
}



