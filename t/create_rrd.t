
####!perl -T

use Test::More tests => 4;

use File::Temp qw/tmpnam/;
use RRDs;
use Data::Dumper;

BEGIN {
  use_ok('RRD::Tweak', "use RRD::Tweak") or
    BAIL_OUT("cannot load the module");
}

diag("Testing RRD::Tweak $RRD::Tweak::VERSION, Perl $], $^X");

my $filename1 = tmpnam();

my $rrd = RRD::Tweak->new();
ok((defined($rrd)), "RRD::Tweak->new()");

$rrd->create({step => 300,
              start => time(),
              ds => [{name => 'InOctets',
                      type=> 'COUNTER',
                      heartbeat => 600},
                     {name => 'OutOctets',
                      type => 'COUNTER',
                      heartbeat => 600},
                     {name => 'Load',
                      type => 'GAUGE',
                      heartbeat => 800,
                      min => 0,
                      max => 255}],
              rra => [{cf => 'AVERAGE',
                       xff => 0.5,
                       steps => 1,
                       rows => 2016},
                      {cf => 'AVERAGE',
                       xff => 0.25,
                       steps => 12,
                       rows => 768},
                      {cf => 'MAX',
                       xff => 0.25,
                       steps => 12,
                       rows => 768}]});

diag("created RRD::Tweak with new RRD data");

diag("Saving $filename1");
$rrd->save_file($filename1);
ok(not $@);
diag("Saved $filename1");

ok((unlink $filename1), "unlink $filename1");




# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
