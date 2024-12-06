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

# unless ($on_target) {
  use warnings;
  use strict;
unless ($on_target) {
  use Data::Dumper;   
}

my $foo = 'bar';

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


# skript level globals to share with subs

my %uci_net_data;
my %proc_vlan_data;
my %mib_out_cache;

my $time_now = time;
my $time_last; # = $time_now;
my $time_updated = 0; # when last data was updated

load_data(); # unconditionally at startup

while (<>){   # ===============  main loop =========================i=
  $time_last = $time_now;
  $time_now = time;
  debug(1, "# check // load data \n") ;
  check_data(); # reload only if required

  debug(5, sprintf "     \$time_now: %i; \$time_last: %i; passed: %i seconds  \n",
	$time_now,  $time_last,  $time_now - $time_last  );
  debug(5, sprintf "     \$time_now: %i; \$time_updated: %i; age of data: %i seconds  \n",
        $time_now,  $time_updated,  $time_now - $time_updated  );

####  check get and getnext normal operation cmds
  if (m!^get(next)?\s*$!){
    my $cmd = $_;
    my $req = <>;
    my $ret;
    chomp($cmd);
    chomp($req);

    debug (5, "input: cmd= $cmd - req= $req...\n");

    # if ( $cmd eq 'getnext' ) {
    if ($1) {        # match group
      debug (5, "     ### TBD: doing getnext\n");
    } else {
      debug (5, "     ### TBD: doing get\n");
    }

  debug (5, "    TBD: deliver some data\n");
  next;
  }

#### debug cases below

  if (m!^PING!){    # part of interface definition
    print "PONG\n";
    next;
  }

  if (m!^exit!){   # safe to keep in production?
    print STDERR "- cancelled -\n";
    exit;
  }

  if (m!^dump!){
    if ($on_target) {
      debug(1, "can't 'dump' - Dumper not available at target\n") ;
    } else {
      # debug(1, "# do the dumper thing\n") ;
      if (m!^dump uci!){
        print STDERR '\%uci_net_data: ', Dumper( \%uci_net_data);
      } else{ 
        debug(1, "# do the dumper thing\n") ;
      }
    }
    next;
  }    
  if (m!^print!){
    debug(1, "# print data in tab form\n") ;
    next;
  }

  debug(0, "end of main loop - cannot recognize command $_ \n") ;


} # === end of main loop ===========


die "   ===== DEBUG exit or error? ===== ";
# =============== subs ========================================================

sub load_data {
  debug(3, "perform initial load_data() ... \n");
  load_uci_net();
  load_proc_vlan();
  debug(4, "... completed initial load_data() \n");
}

sub check_data {
  debug(0, "### TBD check_data() \n");
  load_uci_net() if 0;
  load_proc_vlan() if 0;
}

# fill %uci_net_data;
sub load_uci_net {
  debug(5, "     ... loading load_uci_net() ... \n");
  my @uci_raw = split "\n" , `$uci_show_net`;
  die "executeing $uci_show_net delivered empty result\n" unless scalar @uci_raw;

  my $cb; # keep track of current blocks over multiple lines
  for my $line (@uci_raw) {
    # print "$line\n";
    my ($tag, $val) = split '=', $line;
    my @chunks = split /\./, $tag;
    # print ((join ' | ', @chunks) . " = >$val<\n");
    my $c1 = $chunks[1];
    unless ($chunks[0] eq 'network') {
      debug(2, "illegal chunk $c1 in line $line in input stream\n") ;
      next;
    }

    # only these sections are evaluated, others may throw error or undefined behaviour
    if ($val eq 'device' or $val eq 'interface' or $val eq 'globals') {
      $cb = { defname => $c1, class => $val };
      $uci_net_data{$c1} = $cb;  # create new item for section $c1
      # @device[5]
      my($class, $id) = ( $c1 =~ /^@(\w+)\[(\d+)\]$/ );
      if ($class and $class eq 'device') {
        if (defined $id) {
          $cb->{ID} = $id;
        } else {
          die "case not handled";
        }
      }
      next;
    }  # end of block header

    if (scalar @chunks <= 2) {
      debug(5, "skipping to parse section $c1 ");
      next;
    }
    
    if ($uci_net_data{$c1} == $cb and $chunks[2]) {
      $val =~ /^'(.*)'$/;
      $cb->{$chunks[2]} = $1 ;
      next;
    } 
    # should not be here
    print ((join ' | ', @chunks) . " = >$val<\n");
    die "case not implemented";
  }


  # ========~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~------------------
  # print  '\%uci_net_data: ', Dumper( \%uci_net_data);
  # die " ===== bleeding edge ========~~~~~~~~~~~~~~~~------------------";
}

# %proc_vlan_data;
sub load_proc_vlan {
  debug(0, "     ... ### TBD load_proc_vlan() { ... \n");
  my $vlan_dir = "$proc_dir/vlan";
  my $vlan_conf = "$vlan_dir/config";
  my @vlans_raw = `cat $vlan_conf`;
  die " empty $vlan_conf\n" unless scalar @vlans_raw;

  unless ((shift @vlans_raw) =~ /VLAN\s+Dev\s+name\s+\|\s+VLAN\s+ID/ ) {
    die "first line of $vlan_conf does not match" ;
  }

  unless ((shift @vlans_raw) ne 'Name-Type: VLAN_NAME_TYPE_RAW_PLUS_VID_NO_PAD') {
    die "second line of $vlan_conf does not match" ;
  }

  debug(5, "parsing \@vlans_raw with $#vlans_raw data rows\n");
  for my $line (@vlans_raw) {
    print $line;

  }
  print '\%proc_vlan_data: ', Dumper( \%proc_vlan_data);
  die "====== bleeding edge ==========~~~~~~~~~~~~~~~~~----------------";
}

# build mib tree
# %mib_out_cache;




# ------------------ helper stuff ---------------

sub debug {
  my ($l, $msg) = @_;
  print STDERR 'DEBUG: ', $msg if $l <= $debug;
}



