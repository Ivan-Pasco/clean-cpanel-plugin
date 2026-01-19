package FrameCpanel;

# Frame cPanel Plugin - cPanel Utilities
# Shared functions for cPanel user interface

use strict;
use warnings;

use JSON;
use HTTP::Tiny;
use File::Path qw(make_path);
use File::Copy;

our $MANAGER_API = 'http://127.0.0.1:30000';

# Get current username
sub get_username {
    return $ENV{'REMOTE_USER'} || $Cpanel::user || (getpwuid($>))[0];
}

sub new {
    my ($class, $username) = @_;
    return bless {
        username    => $username,
        http        => HTTP::Tiny->new(timeout => 30),
        instance_dir => "/var/frame/instances/$username",
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

# Get instance status
sub get_status {
    my ($self) = @_;
    my $result = $self->_request('GET', "/frame/instances/$self->{username}/status");
    return $result->{data} if $result->{status};
    return {
        status         => 'unknown',
        port           => 0,
        memory_usage_mb => 0,
        cpu_usage      => 0,
        app_count      => 0,
    };
}

# Start instance
sub start {
    my ($self) = @_;
    return $self->_request('POST', "/frame/instances/$self->{username}/start");
}

# Stop instance
sub stop {
    my ($self) = @_;
    return $self->_request('POST', "/frame/instances/$self->{username}/stop");
}

# Restart instance
sub restart {
    my ($self) = @_;
    return $self->_request('POST', "/frame/instances/$self->{username}/restart");
}

# List applications
sub list_apps {
    my ($self) = @_;
    my $apps_dir = "$self->{instance_dir}/apps";

    my @apps;
    return \@apps unless -d $apps_dir;

    opendir(my $dh, $apps_dir) or return \@apps;

    while (my $entry = readdir($dh)) {
        next if $entry =~ /^\./;
        next unless -d "$apps_dir/$entry";

        my $app_info = {
            name   => $entry,
            status => 'unknown',
        };

        my $config_file = "$apps_dir/$entry/app.json";
        if (-f $config_file && open(my $fh, '<', $config_file)) {
            local $/;
            my $content = <$fh>;
            close($fh);
            eval {
                my $config = decode_json($content);
                $app_info->{domain} = $config->{domain} if $config->{domain};
                $app_info->{created_at} = $config->{created_at} if $config->{created_at};
            };
        }

        push @apps, $app_info;
    }
    closedir($dh);

    return \@apps;
}

# Get app details
sub get_app {
    my ($self, $app_name) = @_;
    my $app_dir = "$self->{instance_dir}/apps/$app_name";
    my $config_file = "$app_dir/app.json";

    return undef unless -d $app_dir;

    my $app = { name => $app_name };

    if (-f $config_file && open(my $fh, '<', $config_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $app = { %$app, %{decode_json($content)} }; };
    }

    return $app;
}

# Deploy new app
sub deploy_app {
    my ($self, $name, $domain) = @_;

    # Validate name
    unless ($name =~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/i) {
        return { status => 0, errors => ['Invalid application name'] };
    }

    my $app_dir = "$self->{instance_dir}/apps/$name";

    if (-d $app_dir) {
        return { status => 0, errors => ["Application '$name' already exists"] };
    }

    eval { make_path($app_dir); };
    if ($@) {
        return { status => 0, errors => ['Failed to create application directory'] };
    }

    my $config = {
        name       => $name,
        domain     => $domain || '',
        created_at => time(),
        env_vars   => {},
    };

    if (open(my $fh, '>', "$app_dir/app.json")) {
        print $fh encode_json($config);
        close($fh);
    }

    return { status => 1, data => { message => "Application '$name' created", name => $name } };
}

# Remove app
sub remove_app {
    my ($self, $name) = @_;
    my $app_dir = "$self->{instance_dir}/apps/$name";

    unless (-d $app_dir) {
        return { status => 0, errors => ["Application '$name' not found"] };
    }

    system('rm', '-rf', $app_dir);

    if (-d $app_dir) {
        return { status => 0, errors => ['Failed to remove application'] };
    }

    return { status => 1, data => { message => "Application '$name' removed" } };
}

# Update app
sub update_app {
    my ($self, $name, $updates) = @_;
    my $app_dir = "$self->{instance_dir}/apps/$name";
    my $config_file = "$app_dir/app.json";

    unless (-d $app_dir) {
        return { status => 0, errors => ["Application '$name' not found"] };
    }

    my $config = {};
    if (-f $config_file && open(my $fh, '<', $config_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $config = decode_json($content); };
    }

    $config->{$_} = $updates->{$_} for grep { defined $updates->{$_} } keys %$updates;
    $config->{updated_at} = time();

    if (open(my $fh, '>', $config_file)) {
        print $fh encode_json($config);
        close($fh);
    } else {
        return { status => 0, errors => ['Failed to save configuration'] };
    }

    return { status => 1, data => { message => "Application '$name' updated" } };
}

# Get logs
sub get_logs {
    my ($self, $app_name, $lines) = @_;
    $lines ||= 100;

    my $log_file;
    if ($app_name) {
        $log_file = "$self->{instance_dir}/apps/$app_name/logs/app.log";
    } else {
        $log_file = "$self->{instance_dir}/logs/frame.log";
    }

    return [] unless -f $log_file;

    my @log_lines;
    if (open(my $fh, '<', $log_file)) {
        @log_lines = <$fh>;
        close($fh);
    }

    my $start = @log_lines > $lines ? @log_lines - $lines : 0;
    @log_lines = @log_lines[$start .. $#log_lines];
    chomp(@log_lines);

    return \@log_lines;
}

# Get environment variables
sub get_env {
    my ($self) = @_;
    my $env_file = "$self->{instance_dir}/env.json";

    my $env = {};
    if (-f $env_file && open(my $fh, '<', $env_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $env = decode_json($content); };
    }

    return $env;
}

# Set environment variable
sub set_env {
    my ($self, $key, $value) = @_;
    my $env_file = "$self->{instance_dir}/env.json";

    my $env = $self->get_env();

    if (defined $value && $value ne '') {
        $env->{$key} = $value;
    } else {
        delete $env->{$key};
    }

    if (open(my $fh, '>', $env_file)) {
        print $fh encode_json($env);
        close($fh);
    } else {
        return { status => 0, errors => ['Failed to save environment'] };
    }

    return { status => 1, data => { message => 'Environment updated' } };
}

# Get domain mappings
sub get_domains {
    my ($self) = @_;
    my $domains_file = "$self->{instance_dir}/domains.json";

    my $domains = {};
    if (-f $domains_file && open(my $fh, '<', $domains_file)) {
        local $/;
        my $content = <$fh>;
        close($fh);
        eval { $domains = decode_json($content); };
    }

    return $domains;
}

# Set domain mapping
sub set_domain {
    my ($self, $app, $domain) = @_;
    my $domains_file = "$self->{instance_dir}/domains.json";

    my $domains = $self->get_domains();
    $domains->{$app} = $domain;

    if (open(my $fh, '>', $domains_file)) {
        print $fh encode_json($domains);
        close($fh);
    } else {
        return { status => 0, errors => ['Failed to save domain mapping'] };
    }

    return { status => 1, data => { message => 'Domain mapping updated' } };
}

# Upload file to app
sub upload_file {
    my ($self, $app_name, $upload_fh) = @_;
    my $app_dir = "$self->{instance_dir}/apps/$app_name";

    unless (-d $app_dir) {
        return { status => 0, errors => ["Application '$app_name' not found"] };
    }

    # Read uploaded file
    my $filename = $upload_fh;
    $filename =~ s/.*[\/\\]//;  # Remove path

    # Validate file extension
    unless ($filename =~ /\.(cln|clean)$/i) {
        return { status => 0, errors => ['Only .cln and .clean files are allowed'] };
    }

    my $dest = "$app_dir/$filename";

    if (open(my $out, '>', $dest)) {
        while (<$upload_fh>) {
            print $out $_;
        }
        close($out);
    } else {
        return { status => 0, errors => ['Failed to save uploaded file'] };
    }

    return { status => 1, data => { message => "File '$filename' uploaded", filename => $filename } };
}

1;
