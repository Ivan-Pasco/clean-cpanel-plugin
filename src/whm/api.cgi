#!/usr/local/cpanel/3rdparty/bin/perl

# Frame cPanel Plugin - WHM API Proxy
# Handles AJAX requests from WHM interface

use strict;
use warnings;

use CGI;
use JSON;
use FindBin qw($Bin);

use lib "$Bin/lib";
use FrameWHM;

# Security check
FrameWHM::require_whm_access();

my $cgi = CGI->new;
my $action = $cgi->param('action') || '';

# Initialize Frame handler
my $frame = FrameWHM->new();

# JSON response helper
sub json_response {
    my ($data) = @_;
    print $cgi->header(
        -type    => 'application/json',
        -charset => 'utf-8',
    );
    print encode_json($data);
    exit;
}

# Route actions
if ($action eq 'status') {
    my $status = $frame->get_status();
    json_response({ status => 1, data => $status });

} elsif ($action eq 'restart_service') {
    my $result = $frame->restart_service();
    json_response($result);

} elsif ($action eq 'instances') {
    my $instances = $frame->get_instances();
    json_response({ status => 1, data => $instances });

} elsif ($action eq 'start_instance') {
    my $username = $cgi->param('username') or json_response({ status => 0, errors => ['Username required'] });
    my $result = $frame->start_instance($username);
    json_response($result);

} elsif ($action eq 'stop_instance') {
    my $username = $cgi->param('username') or json_response({ status => 0, errors => ['Username required'] });
    my $result = $frame->stop_instance($username);
    json_response($result);

} elsif ($action eq 'restart_instance') {
    my $username = $cgi->param('username') or json_response({ status => 0, errors => ['Username required'] });
    my $result = $frame->restart_instance($username);
    json_response($result);

} elsif ($action eq 'instance_logs') {
    my $username = $cgi->param('username') or json_response({ status => 0, errors => ['Username required'] });
    my $logs = $frame->get_logs($username);
    json_response({ status => 1, data => { logs => $logs } });

} elsif ($action eq 'settings') {
    my $settings = $frame->get_settings();
    json_response({ status => 1, data => $settings });

} elsif ($action eq 'update_settings') {
    my $enabled = $cgi->param('enabled');
    my $auto_start = $cgi->param('auto_start');
    my $health_interval = $cgi->param('health_check_interval');

    my $result = $frame->update_settings({
        enabled               => $enabled,
        auto_start            => $auto_start,
        health_check_interval => $health_interval,
    });
    json_response($result);

} elsif ($action eq 'packages') {
    my $packages = $frame->get_packages();
    json_response({ status => 1, data => $packages });

} elsif ($action eq 'update_package') {
    my $name = $cgi->param('name') or json_response({ status => 0, errors => ['Package name required'] });

    my $result = $frame->update_package($name, {
        memory_limit => $cgi->param('memory_limit'),
        cpu_limit    => $cgi->param('cpu_limit'),
        max_apps     => $cgi->param('max_apps'),
        disk_quota   => $cgi->param('disk_quota'),
    });
    json_response($result);

} elsif ($action eq 'ports') {
    my $ports = $frame->get_ports();
    json_response({ status => 1, data => $ports });

} else {
    json_response({ status => 0, errors => ['Unknown action'] });
}
