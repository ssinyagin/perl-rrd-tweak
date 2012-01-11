#!perl -T

use Test::More tests => 4;

use File::Temp qw/tmpnam/;
use RRDs;
use Data::Dumper;

BEGIN {
  use_ok('RRD::Tweak', "use RRD::Tweak") or
    BAIL_OUT("cannot load the module");
}

diag("Testing RRD::Tweak $RRD::Tweak::VERSION, Perl $], $^X");

my $filename = tmpnam();

RRDs::create($filename, '--step', '300',
             'DS:x1:GAUGE:600:-273.0:5000',
             'DS:x2:GAUGE:600:0.0001:U',
             'DS:x3:COMPUTE:x1,x2,*',
             'RRA:AVERAGE:0.5:1:1200',
             'RRA:MIN:0.5:12:2400',
             'RRA:MAX:0.5:12:2400',
             'RRA:AVERAGE:0.5:12:2400');

my $err = RRDs::error();
ok((not $err), "creating RRD file: $filename") or
  BAIL_OUT("Cannot create RRD file: " . $err);


my $rrd = RRD::Tweak->new();
ok((defined($rrd)), "RRD::Tweak->new()");

diag("\$rrd->load_file($filename)");
$rrd->load_file($filename);

print Dumper($rrd);

ok((unlink $filename), "unlink $filename");




# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
                 

