#!/usr/local/cpanel/3rdparty/bin/perl

# Frame cPanel Plugin - WHM Dashboard
# Main entry point for WHM admin interface

use strict;
use warnings;

use CGI;
use JSON;
use Template;
use FindBin qw($Bin);

use lib "$Bin/lib";
use FrameWHM;

# Security check - require WHM access
FrameWHM::require_whm_access();

my $cgi = CGI->new;
my $action = $cgi->param('action') || 'dashboard';

# Initialize Template Toolkit
my $tt = Template->new({
    INCLUDE_PATH => "$Bin/templates",
    ENCODING     => 'utf8',
}) or die "Template error: $Template::ERROR\n";

# Get Frame status
my $frame = FrameWHM->new();

# Route to appropriate action
my $template;
my $vars = {
    page_title => 'Frame Server Management',
    action     => $action,
};

if ($action eq 'dashboard') {
    $template = 'index.tmpl';

    # Get service status
    my $status = $frame->get_status();
    my $instances = $frame->get_instances();
    my $ports = $frame->get_ports();

    $vars->{status} = $status;
    $vars->{instances} = $instances;
    $vars->{ports} = $ports;
    $vars->{running_count} = scalar grep { $_->{status} eq 'running' } @{$instances || []};
    $vars->{total_count} = scalar @{$instances || []};

} elsif ($action eq 'settings') {
    $template = 'settings.tmpl';

    my $settings = $frame->get_settings();
    my $packages = $frame->get_packages();

    $vars->{settings} = $settings;
    $vars->{packages} = $packages;
    $vars->{page_title} = 'Frame Settings';

} elsif ($action eq 'instances') {
    $template = 'instances.tmpl';

    my $instances = $frame->get_instances();

    $vars->{instances} = $instances;
    $vars->{page_title} = 'Frame Instances';

} elsif ($action eq 'logs') {
    $template = 'logs.tmpl';

    my $username = $cgi->param('user') || '';
    my $logs = $username ? $frame->get_logs($username) : [];

    $vars->{username} = $username;
    $vars->{logs} = $logs;
    $vars->{page_title} = $username ? "Logs: $username" : 'Service Logs';

} else {
    # Unknown action, redirect to dashboard
    print $cgi->redirect('index.cgi?action=dashboard');
    exit;
}

# Output page
print $cgi->header(
    -type    => 'text/html',
    -charset => 'utf-8',
);

$tt->process($template, $vars) or die $tt->error();
