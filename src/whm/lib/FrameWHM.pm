package FrameWHM;

# Frame cPanel Plugin - WHM Utilities
# Shared functions for WHM interface

use strict;
use warnings;

use JSON;
use HTTP::Tiny;

our $MANAGER_API = 'http://127.0.0.1:30000';

# Security: Require WHM access
sub require_whm_access {
    # Check for WHM environment variables
    unless ($ENV{'REMOTE_USER'} && $ENV{'REMOTE_USER'} eq 'root') {
        # Also allow resellers with proper permissions
        unless ($ENV{'WHM_RESELLER'}) {
            print "Status: 403 Forbidden\r\n";
            print "Content-Type: text/plain\r\n\r\n";
            print "Access denied. WHM root or reseller access required.\n";
            exit;
        }
    }
}

sub new {
    my $class = shift;
    return bless {
        http => HTTP::Tiny->new(timeout => 30),
    }, $class;
}

# Make request to Frame manager API
sub _request {
    my ($self, $method, $path, $data) = @_;

    my $url = $MANAGER_API . $path;
    my $options = {
        headers => { 'Content-Type' => 'application/json' },
    };

    if ($data && ($method eq 'POST' || $method eq 'PUT')) {
        $options->{content} = encode_json($data);
    }

    my $response;
    if ($method eq 'GET') {
        $response = $self->{http}->get($url, $options);
    } elsif ($method eq 'POST') {
        $response = $self->{http}->post($url, $options);
    } elsif ($method eq 'PUT') {
        $response = $self->{http}->put($url, $options);
    }

    if ($response->{success}) {
        return decode_json($response->{content});
    } else {
        return {
            status => 0,
            errors => ["API error: " . ($response->{reason} || 'Connection failed')],
        };
    }
}

# Get service status
sub get_status {
    my ($self) = @_;
    my $result = $self->_request('GET', '/frame/status');
    return $result->{data} if $result->{status};
    return {
        service_status   => 'unknown',
        instances_running => 0,
        instances_total   => 0,
        memory_usage_mb   => 0,
        port_range        => 'N/A',
    };
}

# Restart service
sub restart_service {
    my ($self) = @_;
    return $self->_request('POST', '/frame/restart');
}

# Get all instances
sub get_instances {
    my ($self) = @_;
    my $result = $self->_request('GET', '/frame/instances');
    return $result->{data} || [];
}

# Start instance
sub start_instance {
    my ($self, $username) = @_;
    return $self->_request('POST', "/frame/instances/$username/start");
}

# Stop instance
sub stop_instance {
    my ($self, $username) = @_;
    return $self->_request('POST', "/frame/instances/$username/stop");
}

# Restart instance
sub restart_instance {
    my ($self, $username) = @_;
    return $self->_request('POST', "/frame/instances/$username/restart");
}

# Get logs
sub get_logs {
    my ($self, $username) = @_;
    my $result = $self->_request('GET', "/frame/instances/$username/logs");
    return $result->{data} || [];
}

# Get settings
sub get_settings {
    my ($self) = @_;
    my $result = $self->_request('GET', '/frame/settings');
    return $result->{data} || {};
}

# Update settings
sub update_settings {
    my ($self, $settings) = @_;
    # Remove undefined values
    my %clean = map { $_ => $settings->{$_} } grep { defined $settings->{$_} } keys %$settings;
    return $self->_request('PUT', '/frame/settings', \%clean);
}

# Get packages
sub get_packages {
    my ($self) = @_;
    my $result = $self->_request('GET', '/frame/packages');
    return $result->{data} || [];
}

# Update package
sub update_package {
    my ($self, $name, $settings) = @_;
    my %clean = map { $_ => $settings->{$_} } grep { defined $settings->{$_} } keys %$settings;
    return $self->_request('PUT', "/frame/packages/$name", \%clean);
}

# Get ports
sub get_ports {
    my ($self) = @_;
    my $result = $self->_request('GET', '/frame/ports');
    return $result->{data} || {};
}

1;
