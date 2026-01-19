#!/usr/local/cpanel/3rdparty/bin/perl

# Frame cPanel Plugin - cPanel Dashboard
# Main entry point for cPanel user interface

use strict;
use warnings;

use CGI;
use JSON;
use Template;
use FindBin qw($Bin);

use lib "$Bin/lib";
use FrameCpanel;

my $cgi = CGI->new;
my $action = $cgi->param('action') || 'dashboard';

# Get current user
my $username = FrameCpanel::get_username();

# Initialize Template Toolkit
my $tt = Template->new({
    INCLUDE_PATH => "$Bin/views",
    ENCODING     => 'utf8',
}) or die "Template error: $Template::ERROR\n";

# Initialize Frame handler
my $frame = FrameCpanel->new($username);

# Route to appropriate action
my $template;
my $vars = {
    page_title => 'Frame Applications',
    action     => $action,
    username   => $username,
};

if ($action eq 'dashboard') {
    $template = 'dashboard.tt';

    my $status = $frame->get_status();
    my $apps = $frame->list_apps();

    $vars->{status} = $status;
    $vars->{apps} = $apps;
    $vars->{app_count} = scalar @$apps;

} elsif ($action eq 'apps') {
    $template = 'apps.tt';

    my $apps = $frame->list_apps();

    $vars->{apps} = $apps;
    $vars->{page_title} = 'My Applications';

} elsif ($action eq 'deploy') {
    $template = 'deploy.tt';
    $vars->{page_title} = 'Deploy Application';

} elsif ($action eq 'settings') {
    my $app_name = $cgi->param('app') || '';
    $template = 'settings.tt';

    if ($app_name) {
        my $app = $frame->get_app($app_name);
        my $env = $frame->get_env();
        my $domains = $frame->get_domains();

        $vars->{app} = $app;
        $vars->{env} = $env;
        $vars->{domains} = $domains;
        $vars->{page_title} = "Settings: $app_name";
    } else {
        # Redirect to apps if no app specified
        print $cgi->redirect('index.live.cgi?action=apps');
        exit;
    }

} elsif ($action eq 'logs') {
    $template = 'logs.tt';

    my $app_name = $cgi->param('app') || '';
    my $logs = $frame->get_logs($app_name);

    $vars->{app_name} = $app_name;
    $vars->{logs} = $logs;
    $vars->{page_title} = $app_name ? "Logs: $app_name" : 'Instance Logs';

} else {
    # Unknown action, redirect to dashboard
    print $cgi->redirect('index.live.cgi?action=dashboard');
    exit;
}

# Output page
print $cgi->header(
    -type    => 'text/html',
    -charset => 'utf-8',
);

$tt->process($template, $vars) or die $tt->error();
