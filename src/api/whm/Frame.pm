package Whostmgr::API::1::Frame;

# Frame cPanel Plugin - WHM API Module
# Provides WHM API endpoints for Frame service management

use strict;
use warnings;

use JSON;
use HTTP::Tiny;

# Manager daemon API endpoint
our $MANAGER_API = 'http://127.0.0.1:30000';

# API function metadata
our %API = (
    status => {
        func   => 'api_status',
        engine => 'json',
    },
    restart => {
        func   => 'api_restart',
        engine => 'json',
    },
    instances => {
        func   => 'api_instances',
        engine => 'json',
    },
    instance_start => {
        func   => 'api_instance_start',
        engine => 'json',
    },
    instance_stop => {
        func   => 'api_instance_stop',
        engine => 'json',
    },
    instance_restart => {
        func   => 'api_instance_restart',
        engine => 'json',
    },
    instance_logs => {
        func   => 'api_instance_logs',
        engine => 'json',
    },
    instance_status => {
        func   => 'api_instance_status',
        engine => 'json',
    },
    settings => {
        func   => 'api_settings',
        engine => 'json',
    },
    update_settings => {
        func   => 'api_update_settings',
        engine => 'json',
    },
    packages => {
        func   => 'api_packages',
        engine => 'json',
    },
    update_package => {
        func   => 'api_update_package',
        engine => 'json',
    },
    ports => {
        func   => 'api_ports',
        engine => 'json',
    },
);

# Helper: Make request to Frame manager API
sub _manager_request {
    my ($method, $path, $data) = @_;

    my $http = HTTP::Tiny->new(timeout => 30);
    my $url = $MANAGER_API . $path;

    my $options = {
        headers => { 'Content-Type' => 'application/json' },
    };

    if ($data && ($method eq 'POST' || $method eq 'PUT')) {
        $options->{content} = encode_json($data);
    }

    my $response;
    if ($method eq 'GET') {
        $response = $http->get($url, $options);
    } elsif ($method eq 'POST') {
        $response = $http->post($url, $options);
    } elsif ($method eq 'PUT') {
        $response = $http->put($url, $options);
    } elsif ($method eq 'DELETE') {
        $response = $http->delete($url, $options);
    }

    if ($response->{success}) {
        return decode_json($response->{content});
    } else {
        return {
            status => 0,
            errors => ["Manager API error: " . ($response->{reason} || 'Unknown error')],
        };
    }
}

# GET /frame/status - Service status
sub api_status {
    my ($args) = @_;
    return _manager_request('GET', '/frame/status');
}

# POST /frame/restart - Restart service
sub api_restart {
    my ($args) = @_;
    return _manager_request('POST', '/frame/restart');
}

# GET /frame/instances - List all instances
sub api_instances {
    my ($args) = @_;
    return _manager_request('GET', '/frame/instances');
}

# POST /frame/instances/{user}/start - Start user instance
sub api_instance_start {
    my ($args) = @_;
    my $username = $args->{username} or return { status => 0, errors => ['Username required'] };
    return _manager_request('POST', "/frame/instances/$username/start");
}

# POST /frame/instances/{user}/stop - Stop user instance
sub api_instance_stop {
    my ($args) = @_;
    my $username = $args->{username} or return { status => 0, errors => ['Username required'] };
    return _manager_request('POST', "/frame/instances/$username/stop");
}

# POST /frame/instances/{user}/restart - Restart user instance
sub api_instance_restart {
    my ($args) = @_;
    my $username = $args->{username} or return { status => 0, errors => ['Username required'] };
    return _manager_request('POST', "/frame/instances/$username/restart");
}

# GET /frame/instances/{user}/logs - Get instance logs
sub api_instance_logs {
    my ($args) = @_;
    my $username = $args->{username} or return { status => 0, errors => ['Username required'] };
    return _manager_request('GET', "/frame/instances/$username/logs");
}

# GET /frame/instances/{user}/status - Get instance status
sub api_instance_status {
    my ($args) = @_;
    my $username = $args->{username} or return { status => 0, errors => ['Username required'] };
    return _manager_request('GET', "/frame/instances/$username/status");
}

# GET /frame/settings - Get settings
sub api_settings {
    my ($args) = @_;
    return _manager_request('GET', '/frame/settings');
}

# PUT /frame/settings - Update settings
sub api_update_settings {
    my ($args) = @_;
    my $data = {
        enabled               => $args->{enabled},
        auto_start            => $args->{auto_start},
        health_check_interval => $args->{health_check_interval},
    };
    # Remove undefined values
    delete $data->{$_} for grep { !defined $data->{$_} } keys %$data;
    return _manager_request('PUT', '/frame/settings', $data);
}

# GET /frame/packages - List packages
sub api_packages {
    my ($args) = @_;
    return _manager_request('GET', '/frame/packages');
}

# PUT /frame/packages/{name} - Update package
sub api_update_package {
    my ($args) = @_;
    my $name = $args->{name} or return { status => 0, errors => ['Package name required'] };
    my $data = {
        memory_limit => $args->{memory_limit},
        cpu_limit    => $args->{cpu_limit},
        max_apps     => $args->{max_apps},
        disk_quota   => $args->{disk_quota},
    };
    delete $data->{$_} for grep { !defined $data->{$_} } keys %$data;
    return _manager_request('PUT', "/frame/packages/$name", $data);
}

# GET /frame/ports - List port allocations
sub api_ports {
    my ($args) = @_;
    return _manager_request('GET', '/frame/ports');
}

1;

__END__

=head1 NAME

Whostmgr::API::1::Frame - WHM API for Frame cPanel Plugin

=head1 SYNOPSIS

    # Via WHM API
    whmapi1 Frame::status
    whmapi1 Frame::instances
    whmapi1 Frame::instance_start username=testuser
    whmapi1 Frame::instance_stop username=testuser

=head1 DESCRIPTION

This module provides WHM API endpoints for managing the Frame service
and user instances. All operations require root/reseller access.

=head1 API FUNCTIONS

=head2 status

Returns the overall Frame service status.

=head2 restart

Restarts the Frame service.

=head2 instances

Lists all Frame instances and their status.

=head2 instance_start

Starts a specific user's Frame instance.

=head2 instance_stop

Stops a specific user's Frame instance.

=head2 instance_restart

Restarts a specific user's Frame instance.

=head2 instance_logs

Retrieves logs for a specific user's Frame instance.

=head2 settings

Returns the current Frame service settings.

=head2 update_settings

Updates Frame service settings.

=head2 packages

Lists Frame package configurations.

=head2 update_package

Updates a specific package's Frame limits.

=head2 ports

Lists all port allocations.

=cut
