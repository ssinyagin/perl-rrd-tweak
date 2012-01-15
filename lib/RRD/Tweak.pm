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

    $self->{errmsg} = '';
    return $self;
}


=head2 validate

  $status = $rrd->validate();

Validates the contents of an RRD::Tweak object and returns false if the
data is inconsistent. In case of failed validation, $rrd->errmsg()
returns a human-readable explanation of the failure.

=cut

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
                        'nan_count', 'last_nan_count'],
     'MHWPREDICT'   => ['intercept', 'last_intercept', 'slope', 'last_slope',
                        'nan_count', 'last_nan_count'],
     'DEVPREDICT'   => [],
     'SEASONAL'     => ['seasonal', 'last_seasonal', 'init_flag'],
     'DEVSEASONAL'  => ['seasonal', 'last_seasonal', 'init_flag'],
     'FAILURES'     => ['history'],
    );



sub validate {
    my $self = shift;

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
    my $n_ds = scalar(@{$self->{ds}});
    if( $n_ds == 0 ) {
        $self->_set_errmsg('no datasources are defined in RRD');
        return 0;
    }

    # validate each DS definition
    for( my $ds=0; $ds < $n_ds; $ds++ ) {
        my $r = $self->{ds}[$ds];

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

        # validate numbers
        my @number_keys = ('scratch_value', 'unknown_sec');
        if( $r->{type} ne 'COMPUTE' ) {
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
    my $n_rra = scalar(@{$self->{rra}});
    if( $n_rra == 0 ) {
        $self->_set_errmsg('no round-robin arrays are defined in RRD');
        return 0;
    }

    for( my $rra=0; $rra < $n_rra; $rra++) {
        my $r = $self->{rra}[$rra];

        if( ref($r) ne 'HASH' ) {
            $self->_set_errmsg('$self->{rra}[' . $rra . '] is not a HASH');
            return 0;
        }

        my $cf = $r->{cf};
        if( not defined($cf) ) {
            $self->_set_errmsg('$self->{rra}[' . $rra . ']{cf} is undefined');
            return 0;
        }

        my $pdp_per_row = $r->{pdp_per_row};
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

        if( not defined($cf_names_and_rra_attributes{$cf}) ) {
            $self->_set_errmsg('Unknown CF name in $self->{rra}[' . $rra .
                               ']{cf}: ' . $cf);
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

        if( ref($self->{cdp_prep}[$rra]) ne 'ARRAY' ) {
            $self->_set_errmsg('$self->{cdp_prep}[' . $rra .
                               '] is not an ARRAY');
            return 0;
        }

        my $cf = $self->{rra}[$rra]{cf};

        for( my $ds=0; $ds < $n_ds; $ds++ ) {
            my $r = $self->{cdp_prep}[$rra][$ds];

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
                if( ref($r->{history}) ne 'ARRAY' ) {
                    $self->_set_errmsg
                        ('$self->{cdp_prep}[' . $rra .
                         '][' . $ds . ']{history} is not an ARRAY');
                    return 0;
                }

                # in rrd_format.h: MAX_FAILURES_WINDOW_LEN=28
                if( scalar(@{$r->{history}}) > 28 ) {
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

        my $rra_data = $self->{cdp_data}[$rra];
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
    return $self->{errmsg};
}

sub _set_errmsg {
    my $self = shift;
    my $msg = shift;
    $self->{errmsg} = $msg;
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
               start => 1326288235,
               ds => {InOctets =>  {type=> 'COUNTER',
                                    heartbeat => 600},
                      OutOctets => {type => 'COUNTER',
                                    heartbeat => 600},
                      Load =>      {type => 'GAUGE',
                                    heartbeat => 800,
                                    min => 0,
                                    max => 255}},
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

The method will create a new RRD with the data-sources and RRAs
specified by the arguments. The arguments are presented in a hash
reference with the following keys and values: C<step>, defining the
minumum RRA resolution (default is 300 seconds); C<start> in seconds
from epoch (default is "time() - 10"); C<ds> pointing to a hash that
defines the datasources; C<rra> pointing to an array with RRA
definitions.

Each datasource definition is a hash entry with the DS name as key, and
a hash with arguments as a value. The following arguments are supported:
C<type>, C<heartbeat>, C<min> (default: "U"), C<max> (default: "U").

Each RRA definition is a hash with the following arguments: C<cf>,
C<xff>, C<steps>, C<rows>.

See also I<rrdcreate> manual page of RRDTool for more details.

=cut


sub create {
    my $self = shift;
    my $args = shift;

    ref($args) or croak('create() requies a hashref as argument');
    ref($args->{ds}) or croak('create() requires "ds" in the argument');
    ref($args->{rra}) or croak('create() requires "rra" in the argument');

    my $pdp_step = $args->{step};
    $pdp_step = 300 unless defined($pdp_step);

    my $last_up = $args->{start};
    $last_up = (time() - 10) unless defined($last_up);

    foreach my $ds_name (sort keys %{$args->{ds}} ) {
        my $r = $args->{ds}{$ds_name};

        defined($r->{type}) or croak('DS ' . $ds_name . ' is missing "type"');
        defined($r->{heartbeat}) or
            croak('DS ' . $ds_name . ' is missing "heartbeat"');
    }

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
