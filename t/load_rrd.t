#!perl -T

use Test::More tests => 16;

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
             'RRA:AVERAGE:0.5:1:1200',
             'RRA:HWPREDICT:1440:0.1:0.0035:288:3',
             'RRA:SEASONAL:288:0.1:2',
             'RRA:DEVPREDICT:1440:5',
             'RRA:DEVSEASONAL:288:0.1:2',
             'RRA:FAILURES:288:7:9:5',
             'RRA:MIN:0.5:12:2400',
             'RRA:MAX:0.5:12:2400',
             'RRA:AVERAGE:0.5:12:2400');

my $err = RRDs::error();
ok((not $err), "creating RRD file: $filename") or
  BAIL_OUT("Cannot create RRD file: " . $err);

my $n_ds = 2;
my $n_rra = 9;
my $n_rra0_steps = 1200;

my $rrd = RRD::Tweak->new();
ok((defined($rrd)), "RRD::Tweak->new()");

diag("\$rrd->load_file($filename)");
$rrd->load_file($filename);

ok((defined($rrd->{version}) and defined($rrd->{pdp_step}) and
    defined($rrd->{last_up}) and ref($rrd->{ds}) and ref($rrd->{rra}) and
    ref($rrd->{cdp_prep}) and ref($rrd->{cdp_data})),
   "load_file making a valid object");

my $rra0 = $rrd->{rra}[0];

sub check_expr {
    my $expr = shift;
    my $expected_result = shift;

    my $x = eval($expr);
    my $y = eval($expected_result);

    ok(($x == $y), $expr . ' == ' . $expected_result) or
        diag($expr . ' is: ' . $x);
}

check_expr('$rrd->{version}', '3');
check_expr('$rrd->{pdp_step}', '300');
check_expr('scalar(@{$rrd->{ds}})', '$n_ds');
check_expr('scalar(@{$rrd->{rra}})', '$n_rra');

check_expr('$rra0->{pdp_per_row}', '1');

ok(($rra0->{cf} eq 'AVERAGE'), '$rra0->{cf} eq "AVERAGE"') or
    diag('$rra0->{cf} is: ' . $rra0->{cf});


check_expr('scalar(@{$rrd->{cdp_prep}})', '$n_rra');
check_expr('scalar(@{$rrd->{cdp_data}})', '$n_rra');
check_expr('scalar(@{$rrd->{cdp_prep}[0]})', '$n_ds');
check_expr('scalar(@{$rrd->{cdp_data}[0]})', '$n_rra0_steps');
check_expr('scalar(@{$rrd->{cdp_data}[0][0]})', '$n_ds');


# print Dumper($rrd);

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
                 

