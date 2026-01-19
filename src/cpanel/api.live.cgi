#!/usr/local/cpanel/3rdparty/bin/perl

# Frame cPanel Plugin - cPanel API Proxy
# Handles AJAX requests from cPanel interface

use strict;
use warnings;

use CGI;
use JSON;
use FindBin qw($Bin);

use lib "$Bin/lib";
use FrameCpanel;

my $cgi = CGI->new;
my $action = $cgi->param('action') || '';

# Get current user
my $username = FrameCpanel::get_username();

# Initialize Frame handler
my $frame = FrameCpanel->new($username);

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

} elsif ($action eq 'start') {
    my $result = $frame->start();
    json_response($result);

} elsif ($action eq 'stop') {
    my $result = $frame->stop();
    json_response($result);

} elsif ($action eq 'restart') {
    my $result = $frame->restart();
    json_response($result);

} elsif ($action eq 'list_apps') {
    my $apps = $frame->list_apps();
    json_response({ status => 1, data => $apps });

} elsif ($action eq 'deploy_app') {
    my $name = $cgi->param('name') or json_response({ status => 0, errors => ['Application name required'] });
    my $domain = $cgi->param('domain') || '';

    my $result = $frame->deploy_app($name, $domain);
    json_response($result);

} elsif ($action eq 'remove_app') {
    my $name = $cgi->param('name') or json_response({ status => 0, errors => ['Application name required'] });

    my $result = $frame->remove_app($name);
    json_response($result);

} elsif ($action eq 'update_app') {
    my $name = $cgi->param('name') or json_response({ status => 0, errors => ['Application name required'] });
    my $domain = $cgi->param('domain');

    my $result = $frame->update_app($name, { domain => $domain });
    json_response($result);

} elsif ($action eq 'get_logs') {
    my $app_name = $cgi->param('app') || '';
    my $lines = $cgi->param('lines') || 100;

    my $logs = $frame->get_logs($app_name, $lines);
    json_response({ status => 1, data => { logs => $logs } });

} elsif ($action eq 'get_env') {
    my $env = $frame->get_env();
    json_response({ status => 1, data => $env });

} elsif ($action eq 'set_env') {
    my $key = $cgi->param('key') or json_response({ status => 0, errors => ['Key required'] });
    my $value = $cgi->param('value');

    my $result = $frame->set_env($key, $value);
    json_response($result);

} elsif ($action eq 'get_domains') {
    my $domains = $frame->get_domains();
    json_response({ status => 1, data => $domains });

} elsif ($action eq 'set_domain') {
    my $app = $cgi->param('app') or json_response({ status => 0, errors => ['App name required'] });
    my $domain = $cgi->param('domain') or json_response({ status => 0, errors => ['Domain required'] });

    my $result = $frame->set_domain($app, $domain);
    json_response($result);

} elsif ($action eq 'upload') {
    # Handle file upload
    my $app_name = $cgi->param('app') or json_response({ status => 0, errors => ['Application name required'] });
    my $upload = $cgi->upload('file');

    unless ($upload) {
        json_response({ status => 0, errors => ['No file uploaded'] });
    }

    my $result = $frame->upload_file($app_name, $upload);
    json_response($result);

} else {
    json_response({ status => 0, errors => ['Unknown action'] });
}
