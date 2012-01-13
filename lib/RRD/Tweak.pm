package RRD::Tweak;

use warnings;
use strict;
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

sub validate {
    my $self = shift;
    # TODO: do the real validation
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
        croak("load_file prodiced an invalid RRD::Tweak object: " .
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
        croak("Cannot run save_file because RRD::Tweak object is invalid:"  .
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
