package Cpanel::API::Frame;

# Frame cPanel Plugin - cPanel UAPI Module
# Provides UAPI endpoints for Frame application management

use strict;
use warnings;

use JSON;
use HTTP::Tiny;
use Cpanel::PwCache ();

# Manager daemon API endpoint
our $MANAGER_API = 'http://127.0.0.1:30000';

# Helper: Get current username
sub _get_username {
    return $Cpanel::user || $ENV{'REMOTE_USER'} || Cpanel::PwCache::getusername();
}

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
            errors => ["API error: " . ($response->{reason} || 'Unknown error')],
        };
    }
}

# UAPI: status - Get user's instance status
sub status {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $response = _manager_request('GET', "/frame/instances/$username/status");

    if ($response->{status}) {
        $result->data($response->{data});
        return 1;
    } else {
        $result->error($response->{errors}[0] || 'Unknown error');
        return 0;
    }
}

# UAPI: start - Start user's instance
sub start {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $response = _manager_request('POST', "/frame/instances/$username/start");

    if ($response->{status}) {
        $result->data({ message => 'Instance started' });
        return 1;
    } else {
        $result->error($response->{errors}[0] || 'Failed to start instance');
        return 0;
    }
}

# UAPI: stop - Stop user's instance
sub stop {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $response = _manager_request('POST', "/frame/instances/$username/stop");

    if ($response->{status}) {
        $result->data({ message => 'Instance stopped' });
        return 1;
    } else {
        $result->error($response->{errors}[0] || 'Failed to stop instance');
        return 0;
    }
}

# UAPI: restart - Restart user's instance
sub restart {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $response = _manager_request('POST', "/frame/instances/$username/restart");

    if ($response->{status}) {
        $result->data({ message => 'Instance restarted' });
        return 1;
    } else {
        $result->error($response->{errors}[0] || 'Failed to restart instance');
        return 0;
    }
}

# UAPI: list_apps - List user's applications
sub list_apps {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $apps_dir = "/var/frame/instances/$username/apps";

    my @apps;
    if (-d $apps_dir) {
        opendir(my $dh, $apps_dir) or do {
            $result->error("Cannot read apps directory");
            return 0;
        };

        while (my $entry = readdir($dh)) {
            next if $entry =~ /^\./;
            next unless -d "$apps_dir/$entry";

            my $config_file = "$apps_dir/$entry/app.json";
            my $app_info = { name => $entry, status => 'unknown' };

            if (-f $config_file) {
                if (open(my $fh, '<', $config_file)) {
                    local $/;
                    my $content = <$fh>;
                    close($fh);
                    eval {
                        my $config = decode_json($content);
                        $app_info->{domain} = $config->{domain} if $config->{domain};
                        $app_info->{created_at} = $config->{created_at} if $config->{created_at};
                    };
                }
            }

            push @apps, $app_info;
        }
        closedir($dh);
    }

    $result->data(\@apps);
    return 1;
}

# UAPI: deploy_app - Deploy a new application
sub deploy_app {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $app_name = $args->get('name');

    unless ($app_name) {
        $result->error('Application name is required');
        return 0;
    }

    # Validate app name (alphanumeric and hyphens only)
    unless ($app_name =~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/i) {
        $result->error('Invalid application name. Use alphanumeric characters and hyphens.');
        return 0;
    }

    my $apps_dir = "/var/frame/instances/$username/apps";
    my $app_dir = "$apps_dir/$app_name";

    if (-d $app_dir) {
        $result->error("Application '$app_name' already exists");
        return 0;
    }

    # Create app directory
    mkdir $app_dir or do {
        $result->error("Failed to create application directory");
        return 0;
    };

    # Create app config
    my $config = {
        name       => $app_name,
        created_at => time(),
        domain     => $args->get('domain') || '',
        env_vars   => {},
    };

    if (open(my $fh, '>', "$app_dir/app.json")) {
        print $fh encode_json($config);
        close($fh);
    }

    $result->data({
        message => "Application '$app_name' created",
        name    => $app_name,
    });
    return 1;
}

# UAPI: remove_app - Remove an application
sub remove_app {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $app_name = $args->get('name');

    unless ($app_name) {
        $result->error('Application name is required');
        return 0;
    }

    my $app_dir = "/var/frame/instances/$username/apps/$app_name";

    unless (-d $app_dir) {
        $result->error("Application '$app_name' not found");
        return 0;
    }

    # Remove app directory recursively
    system('rm', '-rf', $app_dir);

    if (-d $app_dir) {
        $result->error("Failed to remove application directory");
        return 0;
    }

    $result->data({ message => "Application '$app_name' removed" });
    return 1;
}

# UAPI: update_app - Update application settings
sub update_app {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $app_name = $args->get('name');

    unless ($app_name) {
        $result->error('Application name is required');
        return 0;
    }

    my $app_dir = "/var/frame/instances/$username/apps/$app_name";
    my $config_file = "$app_dir/app.json";

    unless (-d $app_dir) {
        $result->error("Application '$app_name' not found");
        return 0;
    }

    # Load existing config
    my $config = {};
    if (-f $config_file && open(my $fh, '<', $config_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $config = decode_json($content); };
    }

    # Update fields
    $config->{domain} = $args->get('domain') if defined $args->get('domain');
    $config->{updated_at} = time();

    # Save config
    if (open(my $fh, '>', $config_file)) {
        print $fh encode_json($config);
        close($fh);
    } else {
        $result->error("Failed to save application configuration");
        return 0;
    }

    $result->data({ message => "Application '$app_name' updated" });
    return 1;
}

# UAPI: get_logs - Get application logs
sub get_logs {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $app_name = $args->get('name') || '';
    my $lines = $args->get('lines') || 100;

    my $log_file;
    if ($app_name) {
        $log_file = "/var/frame/instances/$username/apps/$app_name/logs/app.log";
    } else {
        $log_file = "/var/frame/instances/$username/logs/frame.log";
    }

    unless (-f $log_file) {
        $result->data({ logs => [] });
        return 1;
    }

    my @log_lines;
    if (open(my $fh, '<', $log_file)) {
        @log_lines = <$fh>;
        close($fh);
    }

    # Get last N lines
    my $start = @log_lines > $lines ? @log_lines - $lines : 0;
    @log_lines = @log_lines[$start .. $#log_lines];
    chomp(@log_lines);

    $result->data({ logs => \@log_lines });
    return 1;
}

# UAPI: get_env - Get environment variables
sub get_env {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $env_file = "/var/frame/instances/$username/env.json";

    my $env = {};
    if (-f $env_file && open(my $fh, '<', $env_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $env = decode_json($content); };
    }

    $result->data($env);
    return 1;
}

# UAPI: set_env - Set environment variables
sub set_env {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $env_file = "/var/frame/instances/$username/env.json";

    # Load existing env
    my $env = {};
    if (-f $env_file && open(my $fh, '<', $env_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $env = decode_json($content); };
    }

    # Update with new values
    my $key = $args->get('key');
    my $value = $args->get('value');

    if ($key) {
        if (defined $value && $value ne '') {
            $env->{$key} = $value;
        } else {
            delete $env->{$key};
        }
    }

    # Save env
    if (open(my $fh, '>', $env_file)) {
        print $fh encode_json($env);
        close($fh);
    } else {
        $result->error("Failed to save environment variables");
        return 0;
    }

    $result->data({ message => 'Environment updated' });
    return 1;
}

# UAPI: get_domains - Get domain mappings
sub get_domains {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $domains_file = "/var/frame/instances/$username/domains.json";

    my $domains = {};
    if (-f $domains_file && open(my $fh, '<', $domains_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $domains = decode_json($content); };
    }

    $result->data($domains);
    return 1;
}

# UAPI: set_domains - Set domain mappings
sub set_domains {
    my ($args, $result) = @_;

    my $username = _get_username();
    my $domains_file = "/var/frame/instances/$username/domains.json";

    my $app_name = $args->get('app');
    my $domain = $args->get('domain');

    unless ($app_name && $domain) {
        $result->error('Application name and domain are required');
        return 0;
    }

    # Load existing domains
    my $domains = {};
    if (-f $domains_file && open(my $fh, '<', $domains_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $domains = decode_json($content); };
    }

    # Update mapping
    $domains->{$app_name} = $domain;

    # Save domains
    if (open(my $fh, '>', $domains_file)) {
        print $fh encode_json($domains);
        close($fh);
    } else {
        $result->error("Failed to save domain mappings");
        return 0;
    }

    $result->data({ message => 'Domain mapping updated' });
    return 1;
}

1;

__END__

=head1 NAME

Cpanel::API::Frame - cPanel UAPI for Frame Application Management

=head1 SYNOPSIS

    # Via cPanel UAPI
    uapi Frame status
    uapi Frame list_apps
    uapi Frame deploy_app name=myapp
    uapi Frame remove_app name=myapp

=head1 DESCRIPTION

This module provides cPanel UAPI endpoints for managing Frame applications.
Each user can only manage their own applications.

=head1 API FUNCTIONS

=head2 status

Returns the user's Frame instance status.

=head2 start

Starts the user's Frame instance.

=head2 stop

Stops the user's Frame instance.

=head2 restart

Restarts the user's Frame instance.

=head2 list_apps

Lists all applications for the user.

=head2 deploy_app

Deploys a new application.

=head2 remove_app

Removes an application.

=head2 update_app

Updates application settings.

=head2 get_logs

Gets application or instance logs.

=head2 get_env

Gets environment variables.

=head2 set_env

Sets environment variables.

=head2 get_domains

Gets domain mappings.

=head2 set_domains

Sets domain mappings.

=cut
