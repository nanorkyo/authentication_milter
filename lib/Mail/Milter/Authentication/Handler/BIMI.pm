package Mail::Milter::Authentication::Handler::BIMI;
use strict;
use warnings;
use base 'Mail::Milter::Authentication::Handler';
use version; our $VERSION = version->declare('v1.1.2');

use Data::Dumper;
use English qw{ -no_match_vars };
use Mail::BIMI;
use Sys::Syslog qw{:standard :macros};

sub default_config {
    return {
    };
}

sub register_metrics {
    return {
        'bimi_total' => 'The number of emails processed for BIMI',
    };
}

sub header_callback {
    my ( $self, $header, $value ) = @_;
    return if ( $self->is_local_ip_address() );
    return if ( $self->is_trusted_ip_address() );
    return if ( $self->is_authenticated() );
    return if ( $self->{'failmode'} );
    if ( lc $header eq 'bimi-selector' ) {
        if ( exists $self->{'selector'} ) {
            $self->dbgout( 'BIMIFail', 'Multiple BIMI-Selector fields', LOG_INFO );
            $self->add_auth_header( 'bimi=fail (multiple BIMI-Selector fields in message)' );
            $self->metric_count( 'bimi_total', { 'result' => 'fail', 'reason' => 'bad_selector_header' } );
            $self->{'failmode'} = 1;
            return;
        }
        $self->{'selector'} = $value;
    }
    if ( lc $header eq 'from' ) {
        if ( exists $self->{'from_header'} ) {
            $self->dbgout( 'BIMIFail', 'Multiple RFC5322 from fields', LOG_INFO );
            $self->add_auth_header( 'bimi=fail (multiple RFC5322 from fields in message)' );
            $self->metric_count( 'bimi_total', { 'result' => 'fail', 'reason' => 'bad_from_header' } );
            $self->{'failmode'} = 1;
            return;
        }
        $self->{'from_header'} = $value;
    }
    ## ToDo remove/rename existing headers here
    return;
}

sub eom_requires {
    my ($self) = @_;
    my @requires = qw{ DMARC };
    return \@requires;
}

sub eom_callback {
    my ($self) = @_;
    my $config = $self->handler_config();
    return if ( $self->is_local_ip_address() );
    return if ( $self->is_trusted_ip_address() );
    return if ( $self->is_authenticated() );
    return if ( $self->{'failmode'} );
    eval {
        my $Domain = $self->get_domain_from( $self->{'from_header'} );
        my $Selector = $self->{ 'selector' } || 'default';
        $Selector = lc $Selector;
        my $BIMI = Mail::BIMI->new();

        my $DMARCResult = $self->get_object( 'dmarc_result' );

        if ( ! $DMARCResult ) {
            $self->log_error( 'BIMI Error No DMARC Results object');
            $self->add_auth_header('bimi=temperror (Internal DMARC error)');
            return;
        }

        $BIMI->set_resolver( $self->get_object( 'resolver' ) );
        $BIMI->set_dmarc_object( $DMARCResult );
        $BIMI->set_from_domain( $Domain );
        $BIMI->set_selector( $Selector );
        $BIMI->validate();

        my $Result = $BIMI->result();
        my $AuthResults = $Result->get_authentication_results();

        $self->add_auth_header( $AuthResults );
        my $Record = $BIMI->record();
        my $URLList = $Record->url_list();
        $self->prepend_header( 'BIMI-Location', join( "\n",
            'v=BIMI1;',
            '    l=' . join( ',', @$URLList ) ) );

        $self->metric_count( 'bimi_total', { 'result' => $Result->result() } );

    };
    if ( my $error = $@ ) {
        $self->log_error( 'BIMI Error ' . $error );
        $self->add_auth_header('bimi=temperror');
        return;
    }
    return;
}

sub close_callback {
    my ( $self ) = @_;
    delete $self->{'selector'};
    delete $self->{'from_header'};
    delete $self->{'failmode'};
    return;
}

1;

__END__

=head1 NAME

  Authentication Milter - BIMI Module

=head1 DESCRIPTION

Module implementing the BIMI standard checks.

This handler requires the DMARC handler and its dependencies to be installed and active.

=head1 CONFIGURATION

        "BIMI" : {                                      | Config for the BIMI Module
                                                        | Requires DMARC
        },

=head1 SYNOPSIS

=head1 AUTHORS

Marc Bradshaw E<lt>marc@marcbradshaw.netE<gt>

=head1 COPYRIGHT

Copyright 2017

This library is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.





        my $dmarc = $self->get_dmarc_object();
        return if ( $self->{'failmode'} );
        my $header_domain = $self->get_domain_from( $value );
        eval { $dmarc->header_from( $header_domain ) };
        if ( my $error = $@ ) {
            $self->log_error( 'DMARC Header From Error ' . $error );
            $self->add_auth_header('dmarc=temperror');
            $self->metric_count( 'dmarc_total', { 'result' => 'temperror' } );
            $self->{'failmode'} = 1;
            return;
        }

