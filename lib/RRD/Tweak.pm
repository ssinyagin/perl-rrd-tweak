package RRD::Tweak;

use strict;
use warnings;
use Carp;


use base 'DynaLoader';

our $VERSION = '0.01';
bootstrap RRD::Tweak;

=head1 NAME

RRD::Tweak - RRD file manipulation

=cut



=head1 SYNOPSIS

    use RRD::Tweak;
    my $foo = RRD::Tweak->new();
    ...


=head1 METHODS

=head2 new

 my $rrd = RRD::Tweak->new();

Creates a new RRD::Tweak object

=cut

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->{'errmsg'} = '';
    $self->_set_empty(1);

    return $self;
}


=head2 is_empty

  $status = $rrd->is_empty();

Returns true value if this RRD::Tweak object contains no data. The
object can be empty due to new() or clean() objects.

=cut

sub is_empty {
    my $self = shift;
    return $self->{'is_empty'};
}

sub _set_empty {
    my $self = shift;
    my $val = shift;
    $self->{'is_empty'} = $val;
    return;
}


=head2 validate

  $status = $rrd->validate();

Validates the contents of an RRD::Tweak object and returns false if the
data is inconsistent. In case of failed validation, $rrd->errmsg()
returns a human-readable explanation of the failure.

=cut

# DS types supported
my %ds_types =
    ('GAUGE' => 1,
     'COUNTER' => 1,
     'DERIVE' => 1,
     'ABSOLUTE' => 1,
     'COMPUTE' => 1);

# CF names and corresponding required attributes
my %cf_names_and_rra_attributes =
    ('AVERAGE'      => ['xff'],
     'MIN'          => ['xff'],
     'MAX'          => ['xff'],
     'LAST'         => ['xff'],
     'HWPREDICT'    => ['hw_alpha', 'hw_beta', 'dependent_rra_idx'],
     'MHWPREDICT'   => ['hw_alpha', 'hw_beta', 'dependent_rra_idx'],
     'DEVPREDICT'   => ['dependent_rra_idx'],
     'SEASONAL'     => ['seasonal_gamma', 'seasonal_smooth_idx',
                        'dependent_rra_idx'],
     'DEVSEASONAL'  => ['seasonal_gamma', 'seasonal_smooth_idx',
                        'dependent_rra_idx'],
     'FAILURES'     => ['delta_pos', 'delta_neg', 'window_len',
                        'failure_threshold', 'dependent_rra_idx'],
    );

# required cdp_prep attributes for each CF
my %cdp_prep_attributes =
    ('AVERAGE'      => ['value', 'unknown_datapoints'],
     'MIN'          => ['value', 'unknown_datapoints'],
     'MAX'          => ['value', 'unknown_datapoints'],
     'LAST'         => ['value', 'unknown_datapoints'],
     'HWPREDICT'    => ['intercept', 'last_intercept', 'slope', 'last_slope',
                        'null_count', 'last_null_count'],
     'MHWPREDICT'   => ['intercept', 'last_intercept', 'slope', 'last_slope',
                        'null_count', 'last_null_count'],
     'DEVPREDICT'   => [],
     'SEASONAL'     => ['seasonal', 'last_seasonal', 'init_flag'],
     'DEVSEASONAL'  => ['seasonal', 'last_seasonal', 'init_flag'],
     'FAILURES'     => ['history'],
    );



sub validate {
    my $self = shift;

    if( $self->is_empty() ) {
        $self->_set_errmsg('This is an empty RRD::Tweak object');
        return 0;
    }

    # validate positive numbers
    foreach my $key ('pdp_step', 'last_up') {
        if( not defined($self->{$key}) ) {
            $self->_set_errmsg('$self->{' . $key . '} is undefined');
            return 0;
        }
        if( not eval {$self->{$key} > 0}) {
            $self->_set_errmsg('$self->{' . $key .
                               '} is not a positive number');
            return 0;
        }
    }

    # validate the presence of arrays
    foreach my $key ('ds', 'rra', 'cdp_prep', 'cdp_data') {
        if( not defined($self->{$key}) ) {
            $self->_set_errmsg('$self->{' . $key . '} is undefined');
            return 0;
        }
        if( ref($self->{$key}) ne 'ARRAY' ) {
            $self->_set_errmsg('$self->{' . $key .
                               '} is not an ARRAY');
            return 0;
        }
    }

    # Check that we have a positive number of DS'es
    my $n_ds = scalar(@{$self->{'ds'}});
    if( $n_ds == 0 ) {
        $self->_set_errmsg('no datasources are defined in RRD');
        return 0;
    }

    # validate each DS definition
    for( my $ds=0; $ds < $n_ds; $ds++ ) {
        my $r = $self->{'ds'}[$ds];

        # validate strings
        foreach my $key ('name', 'type', 'last_ds') {
            if( not defined($r->{$key}) ) {
                $self->_set_errmsg('$self->{ds}[' . $ds .
                                   ']{' . $key . '} is undefined');
                return 0;
            }
            if( $r->{$key} eq '' ) {
                $self->_set_errmsg('$self->{ds}[' . $ds .
                                   ']{' . $key . '} is empty');
                return 0;
            }
        }

        # check if the type is valid
        if( not $ds_types{$r->{'type'}} ) {
            $self->_set_errmsg('$self->{ds}[' . $ds .
                               ']{type} has invalid value: "' . $r->{'type'} .
                               '"');
            return 0;
        }

        # validate numbers
        my @number_keys = ('scratch_value', 'unknown_sec');
        if( $r->{'type'} ne 'COMPUTE' ) {
            push(@number_keys, 'hb', 'min', 'max');
        } else {
            # COMPUTE is not currently supported by Tweak.xs because RPN
            # processing methods are not exported by librrd
            push(@number_keys, 'rpn');
        }

        foreach my $key (@number_keys) {
            if( not defined($r->{$key}) ) {
                $self->_set_errmsg('$self->{ds}[' . $ds .
                                   ']{' . $key . '} is undefined');
                return 0;
            }

            if( $r->{$key} !~ /nan$/i and
                $r->{$key} !~ /^[0-9e+\-.]+$/i ) {
                $self->_set_errmsg('$self->{ds}[' . $ds .
                                   ']{' . $key . '} is not a number');
                return 0;
            }
        }
    }

    # Check that we have a positive number of RRA's
    my $n_rra = scalar(@{$self->{'rra'}});
    if( $n_rra == 0 ) {
        $self->_set_errmsg('no round-robin arrays are defined in RRD');
        return 0;
    }

    for( my $rra=0; $rra < $n_rra; $rra++) {
        my $r = $self->{'rra'}[$rra];

        if( ref($r) ne 'HASH' ) {
            $self->_set_errmsg('$self->{rra}[' . $rra . '] is not a HASH');
            return 0;
        }

        my $cf = $r->{cf};
        if( not defined($cf) ) {
            $self->_set_errmsg('$self->{rra}[' . $rra . ']{cf} is undefined');
            return 0;
        }

        if( not defined($cf_names_and_rra_attributes{$cf}) ) {
            $self->_set_errmsg('Unknown CF name in $self->{rra}[' . $rra .
                               ']{cf}: ' . $cf);
            return 0;
        }

        my $pdp_per_row = $r->{'pdp_per_row'};
        if( not defined($pdp_per_row) ) {
            $self->_set_errmsg('$self->{rra}[' . $rra .
                               ']{pdp_per_row} is undefined');
            return 0;
        }
        if( 0 + $pdp_per_row <= 0 ) {
            $self->_set_errmsg('$self->{rra}[' . $rra .
                               ']{pdp_per_row} is not a positive integer');
            return 0;
        }

        foreach my $key (@{$cf_names_and_rra_attributes{$cf}}) {
            if( not defined($r->{$key}) ) {
                $self->_set_errmsg('$self->{rra}[' . $rra . ']{' . $key .
                                   '} is undefined');
                return 0;
            }
        }
    }

    # validate cdp_prep
    for( my $rra=0; $rra < $n_rra; $rra++) {

        if( ref($self->{'cdp_prep'}[$rra]) ne 'ARRAY' ) {
            $self->_set_errmsg('$self->{cdp_prep}[' . $rra .
                               '] is not an ARRAY');
            return 0;
        }

        my $cf = $self->{'rra'}[$rra]{cf};

        for( my $ds=0; $ds < $n_ds; $ds++ ) {
            my $r = $self->{'cdp_prep'}[$rra][$ds];

            if( ref($r) ne 'HASH' ) {
                $self->_set_errmsg('$self->{cdp_prep}[' . $rra .
                                   '][' . $ds . '] is not an HASH');
                return 0;
            }

            foreach my $key (@{$cdp_prep_attributes{$cf}}) {
                if( not defined($r->{$key}) ) {
                    $self->_set_errmsg
                        ('$self->{cdp_prep}[' . $rra .
                         '][' . $ds . ']{' . $key . '} is undefined');
                    return 0;
                }
            }

            if( $cf eq 'FAILURES' ) {
                if( ref($r->{'history'}) ne 'ARRAY' ) {
                    $self->_set_errmsg
                        ('$self->{cdp_prep}[' . $rra .
                         '][' . $ds . ']{history} is not an ARRAY');
                    return 0;
                }

                # in rrd_format.h: MAX_FAILURES_WINDOW_LEN=28
                if( scalar(@{$r->{'history'}}) > 28 ) {
                    $self->_set_errmsg
                        ('$self->{cdp_prep}[' . $rra .
                         '][' . $ds . ']{history} is a too large array');
                    return 0;
                }
            }
        }
    }

    # validate cdp_data
    for( my $rra=0; $rra < $n_rra; $rra++) {

        my $rra_data = $self->{'cdp_data'}[$rra];
        if( ref($rra_data) ne 'ARRAY' ) {
            $self->_set_errmsg('$self->{cdp_data}[' . $rra .
                               '] is not an ARRAY');
            return 0;
        }

        my $rra_len = scalar(@{$rra_data});
        if( $rra_len == 0 ) {
            $self->_set_errmsg('$self->{cdp_data}[' . $rra .
                               '] is an empty array');
            return 0;
        }

        for( my $row=0; $row < $rra_len; $row++ ) {
            my $row_data = $rra_data->[0];
            if( ref($row_data) ne 'ARRAY' ) {
                $self->_set_errmsg('$self->{cdp_data}[' . $rra .
                                   '][' . $row . '] is not an ARRAY');
                return 0;
            }

            my $row_len = scalar(@{$row_data});
            if( $row_len != $n_ds ) {
                $self->_set_errmsg('$self->{cdp_data}[' . $rra .
                                   '][' . $row . '] array has wrong size. ' .
                                   'Expected: ' . $n_ds . ', found: ' .
                                   $row_len);
                return 0;
            }

            for( my $ds=0; $ds < $n_ds; $ds++ ) {
                if( not defined($row_data->[$ds]) ) {
                    $self->_set_errmsg('$self->{cdp_prep}[' . $rra .
                                       '][' . $ds . '][' . $ds .
                                       '] is undefined');
                    return 0;
                }
            }
        }
    }

    return 1;
}




=head2 errmsg

  $msg = $rrd->errmsg();

Returns a text string explaining the details if $rrd->validate() failed.

=cut

sub errmsg {
    my $self = shift;
    return $self->{'errmsg'};
}

sub _set_errmsg {
    my $self = shift;
    my $msg = shift;
    $self->{'errmsg'} = $msg;
    return;
}




=head2 load_file
 $rrd->load_file($filename);

Reads the RRD file and stores its whole content in the RRD::Tweak object

=cut

sub load_file {
    my $self = shift;
    my $filename = shift;

    # the native method is defined in Tweak.xs and uses librrd methods
    $self->_load_file($filename);

    $self->_set_empty(0);

    if( not $self->validate() ) {
        croak('load_file prodiced an invalid RRD::Tweak object: ' .
              $self->errmsg());
    }

    return;
}




=head2 save_file

 $rrd->save_file($filename);

Creates a new RRD file from the contents of the RRD::Tweak object. If
the file already exists, it's truncated and overwritten.

=cut

sub save_file {
    my $self = shift;
    my $filename = shift;

    if( not $self->validate() ) {
        croak('Cannot run save_file because RRD::Tweak object is invalid: '  .
              $self->errmsg());
    }

    # the native method is defined in Tweak.xs and uses librrd methods
    $self->_save_file($filename);

    return;
}




=head2 create

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

The method initializes the RRD::Tweak object with new RRD data as
specified by the arguments.  The arguments are presented in a hash
reference with the following keys and values: C<step>, defining the
minumum RRA resolution (default is 300 seconds); C<start> in seconds
from epoch (default is "time() - 10"); C<ds> pointing to an array that
defines the datasources; C<rra> pointing to an array with RRA
definitions.

Each datasource definition is a hash with the following arguments:
C<name>, C<type>, C<heartbeat>, C<min> (default: "-nan"), C<max>
(default: "-nan"). The COMPUTE datasource type is currently not supported.

Each RRA definition is a hash with arguments: C<cf> defines the
consolidation function; C<steps> defines how many minimal steps are
aggregated by this RRA; C<rows> defines the size of the RRA.

For AVERAGE, MIN, MAX, and LAST consolidation functions, C<xff> is required.

The a subset of the following attributes is required for each RRA that
is related to the Holt-Winters Forecasting: C<hw_alpha>, C<hw_beta>,
C<dependent_rra_idx>, C<dependent_rra_idx>, C<seasonal_gamma>,
C<seasonal_smooth_idx>, C<delta_pos>, C<delta_neg>, C<window_len>,
C<failure_threshold>, C<dependent_rra_idx>. Also C<smoothing_window> is
supported for RRD files of version 4.

See also I<rrdcreate> manual page of RRDTool for more details.

=cut


sub create {
    my $self = shift;
    my $arg = shift;

    if( not $self->is_empty() ) {
        croak('create() requies an empty RRD::Tweak object');
    }

    if( ref($arg) ne 'HASH' ) {
        croak('create() requies a hashref as argument');
    }

    if( ref($arg->{'ds'}) ne 'ARRAY' ) {
        croak('create() requires "ds" array in the argument');
    }

    my $n_ds = scalar(@{$arg->{'ds'}});
    if( $n_ds == 0 ) {
        croak('create(): "ds" is an empty array');
    }

    if( ref($arg->{rra}) ne 'ARRAY' ) {
        croak('create() requires "rra" array in the argument');
    }

    my $n_rra = scalar(@{$arg->{'rra'}});
    if( $n_rra == 0 ) {
        croak('create(): "rra" is an empty array');
    }

    my $pdp_step = $arg->{'step'};
    $pdp_step = 300 unless defined($pdp_step);
    $self->{'pdp_step'} = $pdp_step;

    my $last_up = $arg->{'start'};
    $last_up = (time() - 10) unless defined($last_up);
    $self->{'last_up'} = $last_up;

    my $unknown_sec = $last_up % $pdp_step;

    # process DS definitions
    $self->{'ds'} = [];

    for( my $ds=0; $ds < $n_ds; $ds++ ) {
        my $r = $arg->{'ds'}[$ds];
        if( ref($r) ne 'HASH' ) {
            croak('create(): $arg->{ds}[' . $ds .
                  '] is not a HASH');
        }

        my $ds_attr = {};

        foreach my $key ('name', 'type') {
            if( not defined($r->{$key}) ) {
                croak('create(): $arg->{ds}[' . $ds .
                      ']{' . $key . '} is undefined');
            }

            if( $r->{$key} eq '' ) {
                croak('create(): $arg->{ds}[' . $ds .
                      ']{' . $key . '} is empty');
            }

            $ds_attr->{$key} = $r->{$key};
        }

        if( length($r->{'name'}) > 19 ) {
            croak('create(): $arg->{ds}[' . $ds .
                  ']{name} is too long: "' . $r->{'name'} . '"');
        }

        if( $r->{'name'} !~ /^[0-9a-zA-Z_-]+$/o ) {
            croak('create(): $arg->{ds}[' . $ds .
                  ']{name} has invalid characters: "' . $r->{'name'} . '"');
        }

        if( not $ds_types{$r->{'type'}} ) {
            croak('create(): $arg->{ds}[' . $ds .
                  ']{type} has invalid value: "' . $r->{'type'} . '"');
        }

        if( $r->{'type'} eq 'COMPUTE' ) {
            croak('create(): DS type COMPUTE is currently unsupported');
        }
        else {
            my $hb = $r->{'heartbeat'};
            if( not defined($hb) ) {
                croak('create(): $arg->{ds}[' . $ds .
                      ']{heartbeat} is undefined');
            }
            $ds_attr->{'hb'} = int($hb);

            foreach my $key ('min', 'max') {
                my $val = $r->{$key};
                if( defined($val) ) {
                    if( $val eq 'U' ) {
                        $val = '-nan';
                    }
                }
                else {
                    $val = '-nan';
                }

                $ds_attr->{$key} = $val;
            }
        }

        # Values as defined in rrd_create.c
        $ds_attr->{'last_ds'} = 'U';
        $ds_attr->{'scratch_value'} = '0.0';
        $ds_attr->{'unknown_sec'} = $unknown_sec;

        push(@{$self->{'ds'}}, $ds_attr);
    }


    # process RRA definitions
    $self->{'rra'} = [];
    $self->{'cdp_prep'} = [];
    $self->{'cdp_data'} = [];

    for( my $rra=0; $rra < $n_rra; $rra++) {
        my $r = $arg->{'rra'}[$rra];
        if( ref($r) ne 'HASH' ) {
            croak('create(): $arg->{rra}[' . $rra .
                  '] is not a HASH');
        }

        my $rradef_attr = {};

        my $cf = $r->{cf};
        if( not defined($cf) ) {
            croak('create(): $arg->{rra}[' . $rra . ']{cf} is undefined');
        }
        if( not defined($cf_names_and_rra_attributes{$cf}) ) {
            $self->_set_errmsg('create(): Unknown CF name in ' .
                               '$arg->{rra}[' . $rra . ']{cf}');
        }
        $rradef_attr->{'cf'} = $cf;

        my $pdp_per_row = $r->{'steps'};
        if( not defined($pdp_per_row) or int($pdp_per_row) <= 0 ) {
            croak('create(): $arg->{rra}[' . $rra .
                  ']{steps} is not a positive integer');
        }
        $rradef_attr->{'pdp_per_row'} = $pdp_per_row;

        my $rra_len = $r->{'rows'};
        if( not defined($rra_len) or int($rra_len) <= 0 ) {
            croak('create(): $arg->{rra}[' . $rra .
                  ']{rows} is not a positive integer');
        }

        foreach my $key (@{$cf_names_and_rra_attributes{$cf}}) {
            if( not defined($r->{$key}) ) {
                croak('create(): $arg->{rra}[' . $rra . ']{' .
                      $key . '} is undefined');
            }
            $rradef_attr->{$key} = $r->{$key};
        }

        push(@{$self->{'rra'}}, $rradef_attr);

        # done with RRA definition. Now fill out cdp_prep as specified
        # in rrd_create.c

        my $cdp_prep_attr = {};

        if( grep {$cf eq $_} qw/AVERAGE MIN MAX LAST/ ) {
            $cdp_prep_attr->{'value'} = '-nan';
            $cdp_prep_attr->{'unknown_datapoints'} =
                (($last_up - $unknown_sec) % ($pdp_step * $rra_len)) /
                    $pdp_step;
        }
        elsif( grep {$cf eq $_} qw/HWPREDICT MHWPREDICT/ ) {
            $cdp_prep_attr->{'intercept'} = '-nan';
            $cdp_prep_attr->{'last_intercept'} = '-nan';
            $cdp_prep_attr->{'slope'} = '-nan';
            $cdp_prep_attr->{'last_slope'} = '-nan';
            $cdp_prep_attr->{'null_count'} = 1;
            $cdp_prep_attr->{'last_null_count'} = 1;
        }
        elsif( grep {$cf eq $_} qw/SEASONAL DEVSEASONAL/ ) {
            $cdp_prep_attr->{'seasonal'} = '-nan';
            $cdp_prep_attr->{'last_seasonal'} = '-nan';
            $cdp_prep_attr->{'init_flag'} = 1;
        }
        elsif( $cf eq 'FAILURES' ) {
            my $history = [];
            for( my $i=0; $i < $r->{'window_len'}; $i++ ) {
                push(@{$history}, 0);
            }
            $cdp_prep_attr->{'history'} = $history;
        }

        # duplicate cdp_prep attributes for every DS
        my $rra_cdp_prep = [];
        for( my $ds=0; $ds < $n_ds; $ds++ ) {
            my $attr = {};
            while(my($key, $value) = each %{$cdp_prep_attr}) {
                $attr->{$key} = $value;
            }
            push(@{$rra_cdp_prep}, $attr);
        }

        push(@{$self->{'cdp_prep'}}, $rra_cdp_prep);

        # done with cdp_prep. Now fill out cdp_data

        my $rra_data = [];
        for( my $row=0; $row < $rra_len; $row++ ) {
            my $row_data = [];
            for( my $ds=0; $ds < $n_ds; $ds++ ) {
                push(@{$row_data}, '-nan');
            }
            push(@{$rra_data}, $row_data);
        }

        push(@{$self->{'cdp_data'}}, $rra_data);
    }

    $self->_set_empty(0);
    return;
}




=head1 AUTHOR

Stanislav Sinyagin, C<< <ssinyagin at k-open.com> >>


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Stanislav Sinyagin.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 dated June, 1991 or at your option
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A copy of the GNU General Public License is available in the source tree;
if not, write to the Free Software Foundation, Inc.,
59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


=cut

1;

# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
