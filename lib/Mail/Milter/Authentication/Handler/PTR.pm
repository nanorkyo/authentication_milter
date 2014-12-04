package Mail::Milter::Authentication::Handler::PTR;

use strict;
use warnings;

our $VERSION = 0.5;

use base 'Mail::Milter::Authentication::Handler::Generic';

use Sys::Syslog qw{:standard :macros};

sub callbacks {
    return {
        'connect' => undef,
        'helo'    => 20,
        'envfrom' => undef,
        'envrcpt' => undef,
        'header'  => undef,
        'eoh'     => undef,
        'body'    => undef,
        'eom'     => undef,
        'abort'   => undef,
        'close'   => undef,
    };
}

sub helo_callback {

    # On HELO
    my ( $self, $helo_host ) = @_;
    my $CONFIG = $self->config();
    return if ( !$CONFIG->{'check_ptr'} );
    return if ( $self->is_local_ip_address() );
    return if ( $self->is_trusted_ip_address() );
    return if ( $self->is_authenticated() );

    my $iprev_handler = $self->get_handler('IPRev');
    my $domain =
      exists( $iprev_handler->{'verified_ptr'} )
      ? $iprev_handler->{'verified_ptr'}
      : q{};
    my $helo_name = $self->helo_name();

    if ( lc $domain eq lc $helo_name ) {
        $self->dbgout( 'PTRMatch', 'pass', LOG_DEBUG );
        $self->add_c_auth_header(
                $self->format_header_entry( 'x-ptr',        'pass' ) . q{ }
              . $self->format_header_entry( 'x-ptr-helo',   $helo_name ) . q{ }
              . $self->format_header_entry( 'x-ptr-lookup', $domain ) );
    }
    else {
        $self->dbgout( 'PTRMatch', 'fail', LOG_DEBUG );
        $self->add_c_auth_header(
                $self->format_header_entry( 'x-ptr',        'fail' ) . q{ }
              . $self->format_header_entry( 'x-ptr-helo',   $helo_name ) . q{ }
              . $self->format_header_entry( 'x-ptr-lookup', $domain ) );
    }
}

1;
