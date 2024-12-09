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

# grep patterns as first interface sorting criterion
# my @sort_interfaces = qw(lo eth\d eth_m eth_q eth_ eth phy ap lan br-lan bond);
# no clue how to autodetect "configured" interfaces
my @hw_ports = qw(lo eth_mb eth_q0 eth_q1 eth_q2 eth_q3); #  bond-bond0 );
my $MAC = '90 1B 0E 40 B5 23';  # 90:1B:0E:40:B5:23
# my $portmap = 0xffff; # sufficient bits or all ports to fit 
# my $portmap_bits = 16 ; # number of bits for binary mapping, 

# config of the real gadget data source
my $uci_show_net = '/sbin/uci show network';
my $ip_link_list = '/sbin/ip link list';
my $proc_dir = '/proc';
my $etc_dir  = '/etc';
my $usr_snmp_dir = '/usr/local/share/snmp';
my @mib_tabs = qw ( tab_BRIDGE-MIB.raw  tab_Q-BRIDGE-MIB.raw);


# pseudo data source for development environment
unless ($on_target) {
  my $emulation_root = '.';
  $uci_show_net = "cat $emulation_root/uci/show/network";
  $ip_link_list = "cat $emulation_root/ip/link";
  $proc_dir = "$emulation_root/proc";
  $etc_dir  = "$emulation_root/etc";
  $usr_snmp_dir  = "$emulation_root/usr/local/share/snmp";
  
}

debug(5, sprintf("uci: |%s| -  proc: |%s| -  etc: |%s| \n",
	$uci_show_net, $proc_dir, $etc_dir ));

my $mib_root = "1.3.6.1.2.1.17"; ### BRIDGE-MIB, no leading dot

# skript level globals to share with subs

my %uci_net_data;
my %ip_link_data;
my %proc_vlan_data;
my @proc_dev_data;
my @proc_arp_data;
my %mib_out_cache;
my @mib_out_sort;
my @mib_tab;
my %ifindex;

my %dump_def = (  # pointer, label   
  uci    => [\%uci_net_data,    '%uci_net_data'   ],
  iplink => [\%ip_link_data ,   '%ip_link_data'   ],
  vlan   => [\%proc_vlan_data , '%proc_vlan_data' ],
  dev    => [\@proc_dev_data  , '@proc_dev_data'  ],
  index  => [\%ifindex ,        '%ifindex'        ],
  arp    => [\@proc_arp_data  , '@proc_arp_data'  ],
  mib    => [\%mib_out_cache  , '%mib_out_cache'  ],
  mibsort  => [\@mib_out_sort,  '@mib_out_sort'   ],
  mibtab   => [\@mib_tab ,      '@mib_tab'        ] 
);  #  => [\ , '  '] ,


my $time_now = time;
my $time_last; # = $time_now;
my $time_updated = $time_now ;

load_data(); # unconditionally at startup
$time_now = time;
debug(4, sprintf "     \$time_updated: %i; \$time_now: %i; initial data loaded in %i seconds  \n",
        $time_updated,  $time_now,  $time_now - $time_updated  );
$time_updated = $time_now ;

while (<>){   # ===============  main loop ==========================
  $time_last = $time_now;
  $time_now = time;
  debug(6, "# check // load data \n") ;
  # check_data(); # reload only if required

  debug(6, sprintf "     \$time_now: %i; \$time_last: %i; passed: %i seconds  \n",
	$time_now,  $time_last,  $time_now - $time_last  );
  debug(6, sprintf "     \$time_now: %i; \$time_updated: %i; age of data: %i seconds  \n",
        $time_now,  $time_updated,  $time_now - $time_updated  );

  $_ = lc($_);   # commands case insensitive
  
  # get / getnext demon interface as defined here:
  # http://www.net-snmp.org/docs/man/snmpd.conf.html
  if (m!^get(next)?\s*$!){
    my $cmd = $_;
    my $req = <>;
    # my $ret;
    chomp($cmd);
    chomp($req);

    debug (5, "doing get(next) - input: cmd= $cmd - req= $req\n");
    my $ret = retrieve($req, $1); # oid, next
    
    if ($ret && $ret->{OID}  && $ret->{type} && $ret->{value}) {
      #  OID for the result varbind, the TYPE and the VALUE itself 
      print $ret->{OID} . "\n";
      print $ret->{type} . "\n";
      print $ret->{value} . "\n";
    } else {
      print "NONE\n";
    }    
    next;
  }

  # PING/PONG is part of interface definition
  if (m!^ping!){   
    print "PONG\n";
    next;
  }

  
  #### debug cases below
  # cmd superset of defined interface - safe to keep in production?
  if (m!^exit!){   
    print STDERR "- cancelled -\n";
    exit;
  }

  if (m!^dump\s+(\S+)!){
    if ($on_target) {
      debug(1, "can't 'dump' - Dumper not available at target\n") ;

    } else {
      # dumps internal variables as defined in %dump_def if key matches $1
      if (my $to_dump = $dump_def{$1}) {
        debug(5, "dump of $$to_dump[1]:\n") ;
        print STDERR Data::Dumper->Dump([ $$to_dump[0] ] , [ $$to_dump[1] ] );

      } else { 
        debug(1, "unknown dumper target: $1\n") ;
      }
    }
    next;
  }    

  if (m!^canoid\s+(\S+)\s*$!){
    print STDERR canonic_oid($1), "\n"; 
    next;
  }

  if (m!^raw(next)?\s+(\S+)\s*$!){
    my $ret = retrieve($2, $1); # oid, next
    if ($ret) {
      print STDERR Dumper($ret);
    } else {
      printf STDERR "could not find%s entry for OID %s \n",
		$1 ? ' next': '' ,  $2 ;
    }
    next;
  }

  # if (m!^list!){
  if (m!^(list|walk)\s*(\S+)?\s*(\S+)?\s*$!){
    debug(1, "# print data in tab form\n") ;
    my $cmd = $1;
    my $start = canonic_oid( $2 || '@' );
    # my $end;
    my $end   = canonic_oid( $3 || '9z' ); # lecically larger than any number?
    my ($i_max) = ( $3 =~ /^(\d+)/ );
    if ($i_max) {  $end = '99z' ; }
    
    # find first entry, even if no match
    # my $first 

    # printf ( '$cmd=%s; $start=%s; $end=%s; $i_max=%s;' . "\n\n", 
    #	$cmd, $start, $end, $i_max) ;

    if ($cmd eq 'list') {
      my $i;
      for my $o (@mib_out_sort) {
        next if $o lt $start;
        $i++;
        last if ($i_max and ( $i > $i_max)) ;
        last if $end and  $o gt $end;

        my $oref = retrieve($o,0);
        die "wtf" unless defined $oref;
        print STDERR oid_line($oref) . "\n";
      }  
    } else { # $cmd eq 'walk'
      my $oref = retrieve($start, 0) // retrieve($start, 1);
      # $oref = retrieve($start, 1) unless de$oref;
      my $i;
      while (defined $oref) {
        $i++;
        last if ($i_max and ( $i > $i_max)) ;
        print STDERR oid_line($oref) . "\n";
        my $nxt = $oref->{next};
        last if $nxt gt $end;
        $oref = retrieve($nxt, 0)
      }
      #   print STDERR "cannot find entry for start oid $start\n";
      
    } 

    next;
  }

  debug(0, "end of main loop - cannot recognize command $_ \n") ;

} # === end of main loop ===========

die "   ===== DEBUG exit or error? ===== ";
# =============== subs ========================================================

sub load_data {
  debug(3, "perform initial load_data() ... \n");
  load_uci_net();
  load_ip_link();
  load_proc_vlan();
  load_proc_dev();
  load_proc_arp();
  load_mibtabs();
  build_if_index_static();
  build_mib_tree();
  debug(4, "... completed initial load_data() \n");
}



sub check_data {
  debug(0, "### TBD check_data() \n");
  load_uci_net() if 0;
  load_proc_vlan() if 0;
}

# ====== helpers to select data =======


# remove leading dots and substitue @ by mib_root
sub canonic_oid {
  my $in = shift;
  $in =~ s/^\.// ;  # remove leading dot
  if ( $in =~ /^@\.?(\S*)/ ) {
    return $mib_root . ($1 ? ".$1" : '')  ;
  } else { 
    return $in ;
  }
}


# common selector for get / raw / rage ...
# retrieve( $OID, $next) 
sub retrieve {
    # if (m!^raw(next)?\s+(\S+)\s*$!){
    my ($oid, $next) = @_;
    my $cid = canonic_oid($oid) ;
    my $ret =  $mib_out_cache{ $cid };

    if ($ret and  $next) {
      $ret = $mib_out_cache{ $ret->{next} } ;
    }
    return $ret ;  # undef if not found
}

sub oid_line {
  my $oref = shift;
  return  '--# UNDEF # --' unless defined $oref ;

  return sprintf ('%-40s %-35s %20s:  %s',
    $oref->{def}->{OName} // ' -',   
    $oref->{OID} // $oref->{def}->{OID} // '?????',
    $oref->{type} // '# n/a',
    $oref->{value} // '# n/a'
  )
}

# ===== subs to build OID tree

# %mib_out_cache;
sub build_mib_tree {
  debug(5, "     ### TBD... indexing interfaces ... \n");

  # instantiate from mibtab
  for my $mtrow (@mib_tab) {
    $mib_out_cache{ $mtrow->{OID} }->{def} = $mtrow;
    $mib_out_cache{ $mtrow->{OID} }->{OID} = $mtrow->{OID};
  }

  # add constant stuff
    $mib_out_cache{ '1.3.6.1.2.1.17.1.1.0'}->{value} = $MAC;
    $mib_out_cache{ '1.3.6.1.2.1.17.1.1.0'}->{type} = 'Hex-STRING'; 
		#  dot1qVlanVersionNumber
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.1.0'}->{value} = 1; 
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.1.0'}->{type} = 'INTEGER'; 
		# dot1qMaxVlanId
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.2.0'}->{value} = 4093; 
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.2.0'}->{type} = 'INTEGER'; 

		# dot1qMaxSupportedVlans
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.3.0'}->{value} = 99;
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.1.3.0'}->{type} = 'Gauge32';
	# dot1qNextFreeLocalVlanIndex   1.3.6.1.2.1.17.7.1.4.4
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.4.4.0'}->{value} = 4096;
    $mib_out_cache{ '1.3.6.1.2.1.17.7.1.4.4.0'}->{type} = 'INTEGER';

  

    # dot1dBaseNumPorts                        1.3.6.1.2.1.17.1.2   
    my $portlist = $ifindex{ports_static_avail};
    $mib_out_cache{ '1.3.6.1.2.1.17.1.2.0'}->{value} = $#$portlist;
    $mib_out_cache{ '1.3.6.1.2.1.17.1.2.0'}->{type} = 'INTEGER';

  # dot1dBaseType                            1.3.6.1.2.1.17.1.3  
  # dot1dBasePortTable                       1.3.6.1.2.1.17.1.4  
  # dot1dBasePort                            1.3.6.1.2.1.17.1.4.1.1
    for my $i (1 .. ($#$portlist +1)) {
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.1.1.$i"}->{value} = $i;
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.1.1.$i" }->{type} = 'INTEGER';
      my $idx = $ip_link_data{$$portlist[$i -1] }->{index};
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.1.2.$i"}->{value} = $idx;
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.1.2.$i" }->{type} = 'INTEGER';

    }

  # forward database (aka arp table)
	# dot1dTp                                  1.3.6.1.2.1.17.4
	# dot1dTpLearnedEntryDiscards              1.3.6.1.2.1.17.4.1 
		# no data source at hand
	# dot1dTpAgingTime                         1.3.6.1.2.1.17.4.2 
		# no data source at hand
        # dot1dTpFdbStatus                         1.3.6.1.2.1.17.4.3.1.3 
                # no datasource at hand

	# dot1dTpFdbTable                          1.3.6.1.2.1.17.4.3 
	# dot1dTpFdbEntry                          1.3.6.1.2.1.17.4.3.1 
	# dot1dTpFdbAddress                        1.3.6.1.2.1.17.4.3.1.1 
	# dot1dTpFdbPort                           1.3.6.1.2.1.17.4.3.1.2 
		#  all boils down to data source: $@proc_arp_data
    # we need a reverse index: mac -> seen port

    my %dev_byname  = map { $$portlist[$_ -1],  $_ }   (1 .. ($#$portlist +1));
    my %fdb;          # for dot1d 
    # my %fdb_q_byMAC;  # for dot1q   
    my %fdb_q_byvlid; 
    my %dot1qTpFdbPort;
    my %dot1qTpFdbStatus; 

    for  my $fde (@proc_arp_data) {
      my $device = $fde->{Device};
      # ^([\w\-]+)(\.(\d+))?
      my ($port, $bs, $vlid) = ( $device =~ /^([\w\-]+)(\.(\d+))?$/ );
      my $mac = $fde->{'HW address'};
      $fdb{$mac}->{$port}++;      # for dot1d - by physical port
      if (defined $vlid and $vlid ne '') {
        # $fdb_q_byMAC{$mac}->{$vlid}++;    # for dot1q - by vlan id
        $fdb_q_byvlid{$vlid}->{$mac}++;
        $dot1qTpFdbPort{$vlid}->{$mac}->{$port}++;
        $dot1qTpFdbStatus{$vlid}->{$mac} = arp_status_from_flags($fde->{Flags});
      }
    }

    for my $target_mac (keys %fdb) {
      my @mac_bytes = split ':', $target_mac;
      my $mac_snmp_str = join ' ' , @mac_bytes;
      my $mac_snmp_suboid = join '' , map { '.' . hex($_)  } @mac_bytes;
      # dot1dTpFdbAddress                        1.3.6.1.2.1.17.4.3.1.1  
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.3.1.1$mac_snmp_suboid"}->{value} = $mac_snmp_str;
      $mib_out_cache{ "1.3.6.1.2.1.17.1.4.3.1.1$mac_snmp_suboid"}->{type} = 'Hex-STRING';
      
      for my $port (keys %{$fdb{$target_mac}} ) {
        # looks like the loop is bs here ... only 1 port per target ... never mind ...
        my $port_index = $dev_byname{$port};
        # dot1dTpFdbPort                           1.3.6.1.2.1.17.4.3.1.2
        $mib_out_cache{ "1.3.6.1.2.1.17.1.4.3.1.2$mac_snmp_suboid"}->{value} = $port_index;
        $mib_out_cache{ "1.3.6.1.2.1.17.1.4.3.1.2$mac_snmp_suboid"}->{type} = 'INTEGER';
      }
    }
    # print Dumper (\%fdb);
    # print Dumper (\%fdb_q_byvlid);
    # print Dumper (\%dot1qTpFdbPort);

	# dot1dTpPortTable                         1.3.6.1.2.1.17.4.4
	# dot1dTpPortEntry                         1.3.6.1.2.1.17.4.4.1 
	# dot1dTpPort                              1.3.6.1.2.1.17.4.4.1.{1..5}.* 
		# per port/mac statistics I haven't yet bothered to find

	# iso.3.6.1.2.1.17.7.1.1.{1..3}.0 = INTEGER: 1
		# already done

	# dot1qNumVlans   
	#   1.3.6.1.2.1.17.7.1.1.4  
	# iso.3.6.1.2.1.17.7.1.1.4.0 = Gauge32: 20
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.1.4.0"}->{value} = scalar keys %fdb_q_byvlid;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.1.4.0"}->{type}  = 'Gauge32';

    while ( my ($vlid, $maclist) = each %fdb_q_byvlid) {
        # dot1qFdbDynamicCount 
        #   1.3.6.1.2.1.17.7.1.2.1.1.2
        # iso.3.6.1.2.1.17.7.1.2.1.1.2.4066 = Counter32: 4
      $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.1.1.2.$vlid"}->{value} = scalar keys %$maclist;
      $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.1.1.2.$vlid"}->{type}  = 'Counter32';
      while ( my ($mac, $cnt) = each %$maclist) { 
        my @mac_bytes = split ':', $mac;
        # my $mac_snmp_str = join ' ' , @mac_bytes;
        my $m_oid = join '' , map { '.' . hex($_)  } @mac_bytes;
	# dot1qTpFdbPort  
	#   1.3.6.1.2.1.17.7.1.2.2.1.2 vlID ##:## :##:## :##:##
	# iso.3.6.1.2.1.17.7.1.2.2.1.2.4066.40.128.35.154.89.64 = INTEGER: 29
        # print '$dot1qTpFdbPort{$vlid}->{$mac}: ', Dumper (\%{$dot1qTpFdbPort{$vlid}->{$mac}});
        my @l = keys %{$dot1qTpFdbPort{$vlid}->{$mac}};
        # printf "keys %s\n", join '|',  keys %{$dot1qTpFdbPort{$vlid}->{$mac}} ;
        my $bondname = shift @l;
        my $port_index = $dev_byname{$bondname};
        # printf "shift %s\n", $bondname;
        $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.2.1.2.${vlid}${m_oid}"}->{value} = $port_index; 
		# shift (keys %{$dot1qTpFdbPort{$vlid}->{$mac}}) ;
        $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.2.1.2.${vlid}${m_oid}"}->{type} = 'INTEGER'; 
	# dot1qTpFdbStatus 
	#   1.3.6.1.2.1.17.7.1.2.2.1.3 V # #  #   #  #  #
	# iso.3.6.1.2.1.17.7.1.2.2.1.3.1.0.21.187.18.46.82 = INTEGER: 3
	# sub arp_status_from_flags($flags)
        $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.2.1.3.${vlid}${m_oid}"}->{value} = $dot1qTpFdbStatus{$vlid}->{$mac};
        $mib_out_cache{ "1.3.6.1.2.1.17.7.1.2.2.1.3.${vlid}${m_oid}"}->{type} = 'INTEGER';

      }
    }

  # dot1qVlan	1.3.6.1.2.1.17.7.1.4    
    # not implemented:
    # - dot1qVlanTimeMark      1.3.6.1.2.1.17.7.1.4.2.1.1
    # - dot1qVlanFdbId         1.3.6.1.2.1.17.7.1.4.2.1.3
    # - dot1qVlanCreationTime  1.3.6.1.2.1.17.7.1.4.2.1.7
    # - untagged ports (always shown as 000)
 
  my %vlan_names = reverse %{$ifindex{vlans_static_names}};
  # print Dumper(\%vlan_names);
  # die "echt jetzt?";
  for my $vlanID (@{$ifindex{vlans_static_byID}}) {
    # dot1qVlanIndex 1.3.6.1.2.1.17.7.1.4.2.1.2
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.2.1.${vlanID}"}->{value} = ${vlanID};
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.2.1.${vlanID}"}->{type} = 'INTEGER';
    # dot1qVlanStatus ...6.1.2.1.17.7.1.4.2.1.6
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.6.1.${vlanID}"}->{value} = 2;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.6.1.${vlanID}"}->{type} = 'INTEGER';

    # dot1qVlanStaticTable      1.3.6.1.2.1.17.7.1.4.3
    #              iso.3.6.1.2.1.17.7.1.4.3.1.1.1 = STRING: "Default" 
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.1.${vlanID}"}->{value} = $vlan_names{$vlanID};
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.1.${vlanID}"}->{type} = 'STRING';


    my @ports = @{$ifindex{ports_static_avail}};
    my $portmap_bytes = (int((scalar @ports) /8 )) +1;
    my $portmask = 1 << ($portmap_bytes * 8) ;
    my $egress   = 0; # current (from ip link
    my $egressS  = 0; # static (from uci)
    my $untagged = 0;

    for my $pi (0 .. $#ports) {
      my $portname =  $ports[$pi];
      $portmask >>= 1;
      die " defined portmap too short" unless $portmask;

      my $vl_if_search = sprintf "%s.%u@%s", $portname, $vlanID, $portname;
      if ($ip_link_data{$vl_if_search}) {
         $egress |= $portmask;
      }

      if ($ifindex{vlans_static}->{$vlanID}->{ifname} eq $portname) {
         $egressS |= $portmask;
      }

    }

    # dot1qVlanCurrentEgressPorts  1.3.6.1.2.1.17.7.1.4.2.1.4
    #              iso.3.6.1.2.1.17.7.1.4.2.1.4.1.1 = Hex-STRING: FF FF FC 60 00 
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.4.1.${vlanID}"}->{value} = format_hex_groups($egress, $portmap_bytes);
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.4.1.${vlanID}"}->{type} = 'Hex-STRING';

    # dot1qVlanCurrentUntaggedPorts	1.3.6.1.2.1.17.7.1.4.2.1.5
    #                1.3.6.1.2.1.17.7.1.4.2.1.5.1.*
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.5.1.${vlanID}"}->{value} = format_hex_groups(0, $portmap_bytes);
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.2.1.5.1.${vlanID}"}->{type} = 'Hex-STRING';     
    # dot1qVlanStaticEgressPorts 
    #                1.3.6.1.2.1.17.7.1.4.3.1.2
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.2.${vlanID}"}->{value} = format_hex_groups($egressS, $portmap_bytes);
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.2.${vlanID}"}->{type} = 'Hex-STRING';
    # dot1qVlanForbiddenEgressPorts	1.3.6.1.2.1.17.7.1.4.3.1.3
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.3.${vlanID}"}->{value} = format_hex_groups(0, $portmap_bytes);
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.3.${vlanID}"}->{type} = 'Hex-STRING';
    # dot1qVlanStaticUntaggedPorts	1.3.6.1.2.1.17.7.1.4.3.1.4
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.4.${vlanID}"}->{value} = format_hex_groups(0, $portmap_bytes);
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.4.${vlanID}"}->{type} = 'Hex-STRING';
    # dot1qVlanStaticRowStatus 1.3.6.1.2.1.17.7.1.4.3.1.5    
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.5.${vlanID}"}->{value} = 1;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.3.1.5.${vlanID}"}->{type} = 'INTEGER';
    
  }
  # dot1qPortVlanTable                       1.3.6.1.2.1.17.7.1.4.5
  # "default vlan" is a weird concept in linux iproute2 world, 
  #    but we may have to keep observium happy
  my @ports = @{$ifindex{ports_static_avail}};
  for my $pi (0 .. $#ports) {
    # my $portname =  $ports[$pi];
    # dot1qPvid	1.3.6.1.2.1.17.7.1.4.5.1.1   # default port
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.1.$pi"}->{value} = 1;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.1.$pi"}->{type} = 'INTEGER';
    # dot1qPortAcceptableFrameTypes	1.3.6.1.2.1.17.7.1.4.5.1.2
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.2.$pi"}->{value} = 1;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.2.$pi"}->{type} = 'INTEGER';
    # dot1qPortIngressFiltering	1.3.6.1.2.1.17.7.1.4.5.1.3
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.3.$pi"}->{value} = 1;
    $mib_out_cache{ "1.3.6.1.2.1.17.7.1.4.5.1.3.$pi"}->{type} = 'INTEGER';
  }


  # sort and chain ============ mib output -----------------------------------------------------------------------
  # @mib_out_sort = sort keys %mib_out_cache; # keep sort cache as well
  # https://rosettacode.org/wiki/Sort_a_list_of_object_identifiers#Perl
  # my @sorted =
  @mib_out_sort = 
    map { $_->[0] }
    sort { $a->[1] cmp $b->[1] }
    map { [$_, join '', map { sprintf "%6d", $_ } split /\./, $_] }
    keys %mib_out_cache;

  my $next = ''; # marks end of populated tree 
  for my $k ( reverse @mib_out_sort ) {
    my $m = $mib_out_cache{$k};
    $m->{OID} ||= $m->{def}->{OID}  || $k  || die "wtf";
    $m->{next} = $next;

    if ( $m->{value}  ) {  # only populated oids are valid next targets
      $next = $m->{OID};
    }
  }
}




# %ifindex
sub build_if_index_static {
  debug(5, "     ... indexing static network configuration ... \n");
  # print Dumper(\%uci_net_data);

  # my %ports;
  my %vlans;
  my %otherdevs;
  my %interfaces;
  my %otherconf;
  my %vlan_names; # name => ID
  my %ports;    # counter of vlans per port
  my %bonds;

  while ( my ($k,$v) = each %uci_net_data) {
     # print "k: $k - class: $v->{class}  \n";

     if  ($v->{class} eq 'device') {
       if (($v->{type} // '') eq '8021q') {
         if (defined $v->{vid}) {
           $vlans{$v->{vid} } = $v ; # reindex by vid
         } else {
           # next;
           die "device $k: type 8021q without vlan ID\n" ;
         }

         if (defined (my $port = $v->{ifname}) ) {
           # $ports{$port}->{vl_ifs}++; # count vlans on port
           $ports{$port}->{vl_devices}++
         }

       } else {  
         $otherdevs{$v->{name}} =$v; # don't know yet what to do with that
       }

     } elsif  ($v->{class} eq 'interface') {
       my $dn = $v->{defname};
       $interfaces{$dn} =$v;

       if ( $v->{proto} eq 'bonding') {
         my $bondname = 'bond-' . $dn;
         $bonds{$bondname}->{proto}   = 'bonding';  
         $bonds{$bondname}->{slaves}  = $v->{slaves};
         $bonds{$bondname}->{defname} = $dn;
         $bonds{$bondname}->{ifname}  = $bondname;
         
       }
       # interface is collected, can we extract a vlan name from its def?
       my $def_name = $v->{defname} or next;
       my $device   = $v->{device}  or next;
       my ( $port, $vid ) = ( $device =~ /^([^\.]+)\.(\d+)$/ )  ;
       ($port and defined $vid) or next;
       $ports{$port}->{vl_interfaces}++; # count vlans on port
       $vlan_names{$def_name} = $vid;

     } else { # neither device nor interface, e.g. globals
       $otherconf{$v->{defname}} =$v;
     }
  }  

  # my @ports_available = @hw_interfaces; # dummy TBD hw + bonds + otherdevices + really used
  my @ports_available = (@hw_ports, (sort keys %otherdevs), (sort keys %bonds), (sort keys %ports));



  $ifindex{vlans_static}      = \%vlans;
  $ifindex{vlans_static_byID} = [ sort { $a <=> $b } keys  %vlans  ];
  $ifindex{vlans_static_names}= \%vlan_names;
  $ifindex{stat_other_devs}   = \%otherdevs ;
  $ifindex{stat_oconf}        = \%otherconf ;
  $ifindex{stat_interfaces}   = \%interfaces;
  $ifindex{stat_bonds}        = \%bonds;

  # ###TBD: can we autodetect static interfaces for any platform?
  $ifindex{ports_static_avail}=  [ uniq(@ports_available) ] ;  # \%ports;
  $ifindex{ports_static_used} = \%ports ;

  # print Dumper(\%ifindex);
  # die "DEBUG ====================in ifindex =~~~~~~~~~~~~~~~~~------------------"; 
  
}

sub load_mibtabs {
  debug(5, "     ... loading mibtabs ... \n");

  for my $mt (@mib_tabs) {
    my @mtrows = split "\n" , `cat $usr_snmp_dir/$mt`;
    debug(5, sprintf ("          loaded %4s data rows from %s/%s \n" ,
		 $#mtrows , $usr_snmp_dir, $mt)) ;
    for my $ln (@mtrows) {
      next if $ln =~ /^#/;
      my ($oname, $onam2, $oid, $ot) = split '\s+', $ln;
      push @mib_tab, {
        OName => $oname, 
        OID   => $oid,
        OType => $ot,
        source => $mt
      };
    }
  }
  # print Dumper(\@mib_tab);
  # exit;
}

# ===== subs to retrieve system data


# fill %ip_link_data
sub load_ip_link {
  debug(5, "     ... loading load_ip_link() ... \n");
  my @ip_raw = split "\n" , `$ip_link_list`;
  die "executing $ip_link_list delivered empty result\n" unless scalar @ip_raw;

  my $link; # keep track of current blocks over multiple lines
  while ( my $l1 = shift @ip_raw) {
    my $l2 = shift @ip_raw;
    # print "$l1\n$l2\n" ;
    # ^(\d+)\: (\S+)\: \<([\w\,]*)\>(.*)$
    # ^(\d+)\:\s(\S+)\:\s\<([\w\,]*)\>\s(.*)$
    my ($if_idx, $if_label, $bools, $pairs) = ($l1 =~ /^(\d+)\:\s(\S+)\:\s\<([\w\,]*)\>\s(.*)$/) ;
    #  ^\s+link\/(\w+)\s(\S+)\sbrd\s(\S+)
    my ($linktype, $mac, $brd) = ($l2 =~ /^\s+link\/(\w+)\s(\S+)\sbrd\s(\S+)/);
    # ^([\w\-]+)(\.(\d+))?(\@([\w\-]+))?$
    my ($base, $nope1, $vlid, $nope2, $trunk) = ( $if_label  =~ /^([\w\-]+)(\.(\d+))?(\@([\w\-]+))?$/ );
    my @pairs = split '\s', $pairs;
    my @bools = map { ($_, 'true') } split ',', $bools;
    $ip_link_data{$if_label} = {  index => $if_idx, label => $if_label, 
       linktype => $linktype, MAC => $mac, brd => $brd,
       ifname => $base, vlanID => $vlid, trunk => $trunk,
       (@pairs), (@bools)
        } ;
  }
  # print Dumper(\%ip_link_data);
  # exit;
}


# fill %uci_net_data;
sub load_uci_net {
  debug(5, "     ... loading load_uci_net() ... \n");
  my @uci_raw = split "\n" , `$uci_show_net`;
  die "executing $uci_show_net delivered empty result\n" unless scalar @uci_raw;

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
}

# %proc_vlan_data;
sub load_proc_vlan {
  
  debug(5, "     ... loading proc/net/vlan ... \n");
  my $vlan_dir = "$proc_dir/vlan";
  my $vlan_conf = "$vlan_dir/config";
  my @vlans_raw = split "\n" , `cat $vlan_conf`;
  die " empty $vlan_conf\n" unless scalar @vlans_raw;

  unless ((shift @vlans_raw) =~ /VLAN\s+Dev\s+name\s+\|\s+VLAN\s+ID/ ) {
    die "first line of $vlan_conf does not match" ;
  }

  unless ((shift @vlans_raw) =~ '^Name\-Type\:\ VLAN\_NAME\_TYPE_RAW_PLUS_VID_NO_PAD') {
    die "second line of $vlan_conf does not match" ;
  }

  %proc_vlan_data = (); # start afresh

  debug(6, "parsing \@vlans_raw with $#vlans_raw data rows\n");
  for my $line (@vlans_raw) {
    my ($vl_name, $vl_id, $vl_iface) = split /\s*\|\s+/, $line; 
    $proc_vlan_data{$vl_id} = { ID => $vl_id, 
        name => $vl_name, port => $vl_iface };
  }

  for my $id (keys %proc_vlan_data) {
    my $vldat = $proc_vlan_data{$id};
    my $vl_name = $vldat->{name};
    # print "$vl_name\n";

    my $vl_dat = "$vlan_dir/$vl_name";
    my @vld_raw = split "\n" , `cat $vl_dat`;
    die "cannot process $vlan_conf" if scalar @vld_raw < 5;
    # bond-bond0.4081  VID: 4081       REORDER_HDR: 1  dev->priv_flags: 1021
    # ^(\S+)\s*VID\:\s*(\d+)\s+REORDER_HDR\:\s*(\d+)\s*dev\-\>priv\_flags\:\s*(\d+)\s*$

    my $nl = shift @vld_raw;
    $nl =~ /^(\S+)\s*VID\:\s*(\d+)\s+REORDER_HDR\:\s*(\d+)\s*dev\-\>priv\_flags\:\s*(\d+)\s*$/ ;
    my $datasub = $vldat->{data} = { name => $1, ID => $2, REORDER_HDR => $3, dev_priv_flags => $4 };

    while (defined ($nl = shift @vld_raw) ) {
      next if $nl =~ /^\s*$/;

      #       Broadcast/Multicast Rcvd          104
      if ( $nl =~ /^\s*(\S.*\S)\s+(\d+)\s*$/ ) {
        $datasub->{$1} = $2;
      # }
      #  INGRESS priority mappings: 0:0  1:0  2:0  3:0  4:0  5:0  6:0 7:0
      } elsif ( $nl =~ /^\s*(\S.*\S)\:\s+(\S.*\S)\s*$/ ) {
        $datasub->{$1} = $2;
      }
    }
  }
}


# @proc_dev_data;       /proc/net/dev
sub load_proc_dev {
  debug(5, "     ... loading /proc/net/dev ... \n");
  my $dev_dir = "$proc_dir/dev";
  my @devs_raw = split "\n" , `cat $dev_dir`;
  die " empty $dev_dir\n" unless scalar @devs_raw;

  # my $h1 = shift @devs_raw;
  my ($if1, $rxl, $txl)       = split /\s*\|\s*/, (shift @devs_raw);
  my ($if2, $rxtags, $txtags) = split /\s*\|\s*/, (shift @devs_raw);
  my @rxtaglist = split /\s+/, $rxtags;
  my @txtaglist = split /\s+/, $txtags;

  # print Dumper(\@rxtaglist, \@txtaglist);

  for my $ln (@devs_raw) {
    # print "$ln\n";
    # $string =~ s/^\s+|\s+$//g ;
    $ln =~ s/^\s+|//g ;
    my @cells = split /\s+/, $ln;
    # print ((join '|', @cells) . "\n");
    # lo: interface has leading spaces...

    (shift @cells) =~ /^(\S+)\:$/ ;
    my $dev_row = { Interface => $1, RX => {}, TX => {} };
    push @proc_dev_data, $dev_row;

    for my $rxt (@rxtaglist) {
      $dev_row->{RX}->{$rxt} = shift @cells;
    }

    for my $txt (@txtaglist) {
      $dev_row->{TX}->{$txt} = shift @cells;
    }
  }
}


# @proc_arp_data;       /proc/net/arp 
sub load_proc_arp {
  debug(5, "     ... loading /proc/net/arp ... \n");
  my $arp_dir = "$proc_dir/arp";
  my @arps_raw = split "\n" , `cat $arp_dir`;
  die " empty $arp_dir\n" unless scalar @arps_raw;

  #my @arptags = qw(IP-address HW- type     Flags       HW address            Mask     Device);
  my @arptags =  split /\s\s+/, (shift @arps_raw);

  for my $ln (@arps_raw) {
    my @cells = split /\s+/, $ln;
    my $arp_row = {};
    push @proc_arp_data, $arp_row;
    for my $atg (@arptags) {
      $arp_row->{$atg} = shift @cells;
    }
  }
}

# map arp status for e.g. dot1qTpFdbStatus 1.3.6.1.2.1.17.7.1.2.2.1.3
# caveat - largely untested
# just by guess, slightly educated from linux /usr/include/linux/if_arp.h
# arp_status_from_flags($flags)  i.e. 0x2 or 0x02 
sub arp_status_from_flags {
  my $f = hex (shift);
  return 5 if $f & 0x4; # managed
  return 3 if $f & 0x2; # learned
  return 2 unless $f ;   # invalid
  return 1;              # unknown
}

#
# ====================================build mib tree ==================0
# %mib_out_cache;



# ------------------ helper stuff ---------------

sub debug {
  my ($l, $msg) = @_;
  print STDERR 'DEBUG: ', $msg if $l <= $debug;
}

# http://stackoverflow.com/questions/7651/ddg#7657
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

# convert hex strings in specific length
# pattern e.g. 00 12 ff3B 00 as seen on hp
# format_hex_groups(number, bytes, ['spacer'] );
sub format_hex_groups {
  my ($num, $bytes, $spc) = @_;
  $num //= 0;
  $bytes //= 1;
  $spc //= ' ';
  my @chunks;
  while ($bytes--) {
    unshift @chunks, sprintf("%02X", $num & 0xff);
    $num /= 0x100;
  }
  return join $spc,  @chunks;
}
