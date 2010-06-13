package URI::geo;

use warnings;
use strict;

use Carp;
use URI::Split qw( uri_split uri_join );

use base qw( URI );

=head1 NAME

URI::geo - The geo URI scheme.

=head1 VERSION

This document describes URI::geo version 0.06

=cut

our $VERSION = '0.06';

=head1 SYNOPSIS

  use URI;

  # GeoURI from textual uri
  my $guri = URI->new( 'geo:54.786989,-2.344214' );

  # From coordinates
  my $guri = URI::geo->new( 54.786989, -2.344214 );

  # Decode
  my ( $lat, $lon, $alt ) = $guri->location;
  my $latitude = $guri->latitude;

  # Update
  $guri->location( 55, -1 );
  $guri->longitude( -43.23 );
  
=head1 DESCRIPTION

From L<http://geouri.org/>:

  More and more protocols and data formats are being extended by methods
  to add geographic information. However, all of those options are tied
  to that specific protocol or data format.

  A dedicated Uniform Resource Identifier (URI) scheme for geographic
  locations would be independent from any protocol, usable by any
  software/data format that can handle generich URIs. Like a "mailto:"
  URI launches your favourite mail application today, a "geo:" URI could
  soon launch your favourite mapping service, or queue that location for
  a navigation device.

=cut

# Try hard to extract location information from something. We handle lat,
# lon, alt as scalars, arrays containing lat, lon, alt, hashes with
# suitably named keys and objects with suitably named methods.

sub _location_of_pointy_thing {
  my $class = shift;

  my @lat = ( 'lat', 'latitude' );
  my @lon = ( 'lon', 'long', 'longitude' );
  my @ele = ( 'ele', 'alt', 'elevation', 'altitude' );

  if ( ref $_[0] ) {
    my $pt = shift;

    croak "Too many arguments" if @_;

    if ( UNIVERSAL::can( $pt, 'can' ) ) {
      for my $m ( qw( location latlong ) ) {
        return $pt->$m() if $pt->can( $m );
      }

      my $can = sub {
        my ( $pt, @keys ) = @_;
        for my $key ( @keys ) {
          return $key if $pt->can( $key );
        }
        return;
      };

      my $latk = $can->( $pt, @lat );
      my $lonk = $can->( $pt, @lon );
      my $elek = $can->( $pt, @ele );

      if ( defined $latk && defined $lonk ) {
        return $pt->$latk(), $pt->$lonk(),
         defined $elek ? $pt->$elek() : undef;
      }
    }
    elsif ( 'ARRAY' eq ref $pt ) {
      return $class->_location_of_pointy_thing( @$pt );
    }
    elsif ( 'HASH' eq ref $pt ) {
      my $has = sub {
        my ( $pt, @keys ) = @_;
        for my $key ( @keys ) {
          return $key if exists $pt->{$key};
        }
        return;
      };

      my $latk = $has->( $pt, @lat );
      my $lonk = $has->( $pt, @lon );
      my $elek = $has->( $pt, @ele );

      if ( defined $latk && defined $lonk ) {
        return $pt->{$latk}, $pt->{$lonk},
         defined $elek ? $pt->{$elek} : undef;
      }
    }

    croak "Don't know how to convert point";
  }
  else {
    croak "Need lat, lon or lat, lon, alt"
     if @_ < 2 || @_ > 3;
    return my ( $lat, $lon, $alt ) = @_;
  }
}

sub _num {
  my ( $class, $n ) = @_;
  return '' unless defined $n;
  ( my $rep = sprintf '%f', $n ) =~ s/\.0*$//;
  return $rep;
}

=head1 INTERFACE 

=head2 C<< new >>

Create a new URI::geo. The arguments should be either

=over

=item * latitude, longitude and optionally altitude

=item * a reference to an array containing lat, lon, alt

=item * a reference to a hash with suitably named keys or

=item * a reference to an object with suitably named accessors

=back

To maximise the likelyhood that you can pass in some object that
represents a geographical location and have URI::geo do the right thing
we try a number of different accessor names.

If the object has a C<latlong> method (eg L<Geo::Point>) we'll use that.
If there's a C<location> method we call that. Otherwise we look for
accessors called C<lat>, C<latitude>, C<lon>, C<long>, C<longitude>,
C<ele>, C<alt>, C<elevation> or C<altitude> and use them.

Often if you have an object or hash reference that represents a point
you can pass it directly to C<new>; so for example this will work:

  use URI::geo;
  use Geo::Point;

  my $pt = Geo::Point->latlong( 48.208333, 16.372778 );
  my $guri = URI::geo->new( $pt );

As will this:

  my $guri = URI::geo->new( { lat => 55, lon => -1 } );

and this:

  my $guri = URI::geo->new( 55, -1 );

Note that you can also create a new C<URI::geo> by passing a GeoURI to
C<URI::new>:

  use URI;

  my $guri = URI->new( 'geo:55,-1' );

=cut

sub new {
  my $self  = shift;
  my $class = ref $self || $self;
  my $uri   = uri_join 'geo', undef, $class->_path( @_ );
  return bless \$uri, $class;
}

sub _init {
  my ( $class, $uri, $scheme ) = @_;

  my $self = $class->SUPER::_init( $uri, $scheme );

  # Normalise at poles.
  my $lat = $self->latitude;
  $self->longitude( 0 ) if $lat == 90 || $lat == -90;
  return $self;
}

=head2 C<location>

Get or set the location of this geo URI.

  my ( $lat, $lon, $alt ) = $guri->location;
  $guri->location( 55.3, -3.7, 120 );

When setting the location it is possible to pass any of the argument
types that can be passed to C<new>.

=cut

sub location {
  my $self = shift;

  if ( @_ ) {
    my ( $lat, $lon, $alt ) = @_;
    return $self->latitude( $lat )->longitude( $lon )->altitude( $alt );
  }

  return $self->latitude, $self->longitude, $self->altitude;
}

=head2 C<latitude>

Get or set the latitude of this geo URI.

=head2 C<longitude>

Get or set the longitude of this geo URI.

=head2 C<altitude>

Get or set the altitude of this geo URI. To delete the altitude set it
to C<undef>.

=head2 C<crs>

=head2 C<uncertainty>

=head2 C<field>

=cut

BEGIN {
  my @m = qw( latitude longitude altitude crs uncertainty );
  for my $meth ( @m ) {
    no strict 'refs';
    *{$meth} = sub { shift->field( $meth, @_ ) };
  }
}

sub field {
  my ( $self, $name ) = ( shift, shift );
  my ( $scheme, $auth, $v, $query, $frag ) = $self->_parse;

  croak "No such field: $name" unless exists $v->{$name};
  return $v->{$name} unless @_;
  $v->{$name} = shift;
  $$self = uri_join $scheme, $auth, $self->_format( $v ), $query, $frag;
  return $self;
}

{
  my $pnum = qr{\d+(?:\.\d+)?};
  my $num  = qr{-?$pnum};
  my $crsp = qr{(?:;crs=(\w+))};
  my $uncp = qr{(?:;u=($pnum))};
  my $parm = qr{(?:;\w+=[^;]*)+};

  sub _parse {
    my $self = shift;
    my ( $scheme, $auth, $path, $query, $frag ) = uri_split $$self;

    $path =~ m{^ ($num), ($num) (?: , ($num) ) ?
                   (?: $crsp ) ?
                   (?: $uncp ) ?
                   ( $parm ) ? 
                $}x or croak "Badly formed geo uri";

    # No named captures before 5.10.0
    return $scheme, $auth,
     {
      latitude    => $1,
      longitude   => $2,
      altitude    => $3,
      crs         => $4,
      uncertainty => $5,
      parameters  => ( defined $6 ? substr $6, 1 : undef ),
     },
     $query, $frag;
  }
}

sub _format {
  my ( $class, $v ) = @_;
  return join ';',
   (
    join ',',
    map { $class->_num( $_ ) } @{$v}{ 'latitude', 'longitude' },
    ( defined $v->{altitude} ? ( $v->{altitude} ) : () )
   ),
   ( defined $v->{crs} ? ( 'crs=' . $class->_num( $v->{crs} ) ) : () ),
   (
    defined $v->{uncertainty}
    ? ( 'u=' . $class->_num( $v->{uncertainty} ) )
    : ()
   ),
   ( defined $v->{parameters} ? ( $v->{parameters} ) : () );
}

sub _path {
  my $class = shift;
  my ( $lat, $lon, $alt ) = $class->_location_of_pointy_thing( @_ );
  croak "Latitude out of range"  if $lat < -90  || $lat > 90;
  croak "Longitude out of range" if $lon < -180 || $lon > 180;
  $lon = 0 if $lat == -90 || $lon == 90;
  return $class->_format(
    { latitude => $lat, longitude => $lon, altitude => $alt } );
}

1;

__END__

=head1 DEPENDENCIES

L<URI>

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-uri-geo@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009, Andy Armstrong C<< <andy@hexten.net> >>.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
