package Mail::Milter::Authentication::Handler::TLS;
use strict;
use warnings;
use base 'Mail::Milter::Authentication::Handler';
# VERSION

use Sys::Syslog qw{:standard :macros};
use Mail::AuthenticationResults::Header::Entry;
use Mail::AuthenticationResults::Header::SubEntry;
use Mail::AuthenticationResults::Header::Comment;

sub default_config {
    return {};
}

sub grafana_rows {
    my ( $self ) = @_;
    my @rows;
    push @rows, $self->get_json( 'TLS_metrics' );
    return \@rows;
}

sub register_metrics {
    return {
        'tls_connect_total' => 'The number of connections which were enctypted',
    };
}

sub pre_loop_setup {
    my ( $self ) = @_;
    my $protocol = Mail::Milter::Authentication::Config::get_config()->{'protocol'};
    if ( $protocol eq 'smtp' ) {
        warn 'When in smtp mode, the TLS handler requires the MTA to write TLS data into the first Received header.';
    }
    return;
}

sub envfrom_callback {
    my ( $self, $env_from ) = @_;

    delete $self->{'first_header_read'};

    my $protocol = Mail::Milter::Authentication::Config::get_config()->{'protocol'};
    return if $protocol ne 'milter';

    my $version = $self->get_symbol('{tls_version}');
    my $cipher  = $self->get_symbol('{cipher}');
    my $bits    = $self->get_symbol('{cipher_bits}');
    # on postfix the macro is empty on untrusted connections
    my $trusted = $self->get_symbol('{cert_issuer}') ? ', trusted' : '';

    if ($version) {
        $self->dbgout( 'EncryptedAs', "$version, $cipher, $bits bits$trusted", LOG_INFO );

        my $metric_data = {};
        my $header = Mail::AuthenticationResults::Header::Entry->new()->set_key( 'x-tls' )->safe_set_value( 'pass' );
        $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'version' )->safe_set_value( $version ) );

        if ( $cipher ) {
            $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'cipher' )->safe_set_value( $cipher ) );
            $metric_data->{ 'cipher' } = $cipher;
        }
        if ( $bits ) {
            $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'bits' )->safe_set_value( $bits ) );
            $metric_data->{ 'bits' } = $bits;
        }
        $metric_data->{ 'trusted' } = $trusted ? 1 : 0;

        $self->metric_count( 'tls_connect_total', $metric_data );

        $self->add_auth_header( $header );
    }
    return;
}

sub header_callback {
    my ( $self, $header, $value ) = @_;

    return if lc $header ne 'received';
    return if ( exists( $self->{'first_header_read'} ) );
    $self->{'first_header_read'} = 1;


    my $protocol = Mail::Milter::Authentication::Config::get_config()->{'protocol'};
    return if $protocol ne 'smtp';

    # Try and parse the first received header, this should be something like...
    # Received: from mail-ua0-f173.google.com (mail-ua0-f173.google.com [209.85.217.173])
    #           (using TLSv1.2 with cipher ECDHE-RSA-AES128-GCM-SHA256 (128/128 bits))
    #           (No client certificate requested)
    #           by mx5.messagingengine.com (Postfix) with ESMTPS
    #           for <marcmctest@fastmail.com>; Thu,  1 Dec 2016 22:35:06 -0500 (EST)

    # Future, extend to check for client certificates

    $value =~ m/using ([^ ]*) with cipher ([^ ]+) \(([^ ]+) bits\)/;
    my $version = $1;
    my $cipher  = $2;
    my $bits    = $3;

    if ($version) {
        $self->dbgout( 'EncryptedAs', "$version, $cipher, $bits bits", LOG_INFO );

        my $metric_data = {};
        my $header = Mail::AuthenticationResults::Header::Entry->new()->set_key( 'x-tls' )->safe_set_value( 'pass' );
        $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'version' )->safe_set_value( $version ) );

        if ( $cipher ) {
            $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'cipher' )->safe_set_value( $cipher ) );
            $metric_data->{ 'cipher' } = $cipher;
        }
        if ( $bits ) {
            $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'bits' )->safe_set_value( $bits ) );
            $metric_data->{ 'bits' } = $bits;
        }

        $self->metric_count( 'tls_connect_total', $metric_data );

        $self->add_auth_header( $header );
    }

    return;
}

sub close_callback {
    my ( $self ) = @_;
    delete $self->{'first_header_read'};
    return;
}

1;

__END__

=head1 DESCRIPTION

Identify TLS protected connections.

=head1 CONFIGURATION

No configuration options exist for this handler.

