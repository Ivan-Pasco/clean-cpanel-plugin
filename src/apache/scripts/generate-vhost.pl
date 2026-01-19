#!/usr/bin/perl
# Frame Applications - Virtual Host Configuration Generator
# Generates Apache virtual host configurations from templates
#
# Usage: generate-vhost.pl --user USERNAME --app APPNAME --domain DOMAIN --port PORT [options]

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use File::Path qw(make_path);
use Template;
use POSIX qw(strftime);

# Configuration
my $TEMPLATE_DIR = '/usr/local/cpanel/whostmgr/docroot/cgi/frame/templates/apache';
my $OUTPUT_DIR = '/etc/apache2/conf.d/frame';
my $SSL_CERT_DIR = '/var/cpanel/ssl/installed/certs';
my $SSL_KEY_DIR = '/var/cpanel/ssl/installed/keys';

# Command line options
my %opts = (
    user    => '',
    app     => '',
    domain  => '',
    port    => 0,
    ssl     => 0,
    aliases => '',
    remove  => 0,
    reload  => 1,
    help    => 0,
);

GetOptions(
    'user=s'    => \$opts{user},
    'app=s'     => \$opts{app},
    'domain=s'  => \$opts{domain},
    'port=i'    => \$opts{port},
    'ssl!'      => \$opts{ssl},
    'aliases=s' => \$opts{aliases},
    'remove'    => \$opts{remove},
    'reload!'   => \$opts{reload},
    'help'      => \$opts{help},
) or usage();

usage() if $opts{help};

# Validate required options
unless ($opts{user} && $opts{app}) {
    die "Error: --user and --app are required\n";
}

# Remove configuration if requested
if ($opts{remove}) {
    remove_config();
    exit 0;
}

# Validate additional required options for generation
unless ($opts{domain} && $opts{port}) {
    die "Error: --domain and --port are required for generation\n";
}

# Generate configuration
generate_config();

sub usage {
    print <<EOF;
Frame Virtual Host Configuration Generator

Usage: $0 --user USERNAME --app APPNAME --domain DOMAIN --port PORT [options]

Required:
  --user USERNAME     cPanel username
  --app APPNAME       Frame application name
  --domain DOMAIN     Domain name for the application
  --port PORT         Port number for the Frame instance

Options:
  --ssl               Generate SSL configuration (default: no)
  --aliases ALIASES   Comma-separated list of domain aliases
  --remove            Remove configuration instead of generating
  --no-reload         Don't reload Apache after changes
  --help              Show this help message

Examples:
  # Generate HTTP-only configuration
  $0 --user john --app myapp --domain myapp.example.com --port 30001

  # Generate SSL configuration
  $0 --user john --app myapp --domain myapp.example.com --port 30001 --ssl

  # Remove configuration
  $0 --user john --app myapp --remove

EOF
    exit 0;
}

sub generate_config {
    # Create output directories
    my $user_dir = "$OUTPUT_DIR/$opts{user}";
    my $domains_dir = "$OUTPUT_DIR/domains";

    make_path($user_dir) unless -d $user_dir;
    make_path($domains_dir) unless -d $domains_dir;

    # Initialize Template Toolkit
    my $tt = Template->new({
        INCLUDE_PATH => $TEMPLATE_DIR,
        INTERPOLATE  => 0,
        POST_CHOMP   => 1,
    }) or die "Template error: $Template::ERROR\n";

    # Prepare template variables
    my $vars = {
        username  => $opts{user},
        app_name  => $opts{app},
        domain    => $opts{domain},
        port      => $opts{port},
        aliases   => $opts{aliases},
        timestamp => strftime('%Y-%m-%d %H:%M:%S', localtime),
    };

    # Determine template and output file
    my ($template, $output_file);

    if ($opts{ssl}) {
        # Check for SSL certificates
        my ($ssl_cert, $ssl_key, $ssl_chain) = find_ssl_certs($opts{domain});

        unless ($ssl_cert && $ssl_key) {
            die "Error: SSL certificates not found for $opts{domain}\n";
        }

        $vars->{ssl_cert}  = $ssl_cert;
        $vars->{ssl_key}   = $ssl_key;
        $vars->{ssl_chain} = $ssl_chain if $ssl_chain;

        $template = 'vhost-ssl.conf.tmpl';
    } else {
        $template = 'vhost.conf.tmpl';
    }

    $output_file = "$domains_dir/$opts{domain}.conf";

    # Generate configuration
    my $config;
    $tt->process($template, $vars, \$config)
        or die "Template processing failed: " . $tt->error() . "\n";

    # Write configuration file
    open(my $fh, '>', $output_file) or die "Cannot write $output_file: $!\n";
    print $fh $config;
    close($fh);

    print "Generated: $output_file\n";

    # Also generate path-based config for user's main domain
    my $path_config;
    $tt->process('proxy-path.conf.tmpl', $vars, \$path_config)
        or die "Template processing failed: " . $tt->error() . "\n";

    my $path_file = "$user_dir/$opts{app}-path.conf";
    open($fh, '>', $path_file) or die "Cannot write $path_file: $!\n";
    print $fh $path_config;
    close($fh);

    print "Generated: $path_file\n";

    # Reload Apache if requested
    if ($opts{reload}) {
        reload_apache();
    }
}

sub remove_config {
    my $domains_dir = "$OUTPUT_DIR/domains";
    my $user_dir = "$OUTPUT_DIR/$opts{user}";

    # Find and remove domain config
    my @domain_files = glob("$domains_dir/*.conf");
    for my $file (@domain_files) {
        if (config_belongs_to_app($file, $opts{user}, $opts{app})) {
            unlink($file);
            print "Removed: $file\n";
        }
    }

    # Remove path-based config
    my $path_file = "$user_dir/$opts{app}-path.conf";
    if (-f $path_file) {
        unlink($path_file);
        print "Removed: $path_file\n";
    }

    # Reload Apache if requested
    if ($opts{reload}) {
        reload_apache();
    }
}

sub config_belongs_to_app {
    my ($file, $user, $app) = @_;

    open(my $fh, '<', $file) or return 0;
    while (<$fh>) {
        if (/^# User: \Q$user\E$/ || /^# Generated for: \Q$app\E$/) {
            close($fh);
            # Verify both match
            seek($fh, 0, 0);
            my $content = do { local $/; <$fh> };
            close($fh);
            return ($content =~ /# User: \Q$user\E/ && $content =~ /# Generated for: \Q$app\E/);
        }
    }
    close($fh);
    return 0;
}

sub find_ssl_certs {
    my ($domain) = @_;

    my $cert = "$SSL_CERT_DIR/$domain.crt";
    my $key = "$SSL_KEY_DIR/$domain.key";
    my $chain = "$SSL_CERT_DIR/${domain}_chain.crt";

    # Check if files exist
    $cert = undef unless -f $cert;
    $key = undef unless -f $key;
    $chain = undef unless -f $chain;

    # Try wildcard domain if specific domain not found
    unless ($cert && $key) {
        my @parts = split(/\./, $domain);
        if (@parts > 2) {
            shift @parts;
            my $wildcard = '*.' . join('.', @parts);
            my $wild_cert = "$SSL_CERT_DIR/$wildcard.crt";
            my $wild_key = "$SSL_KEY_DIR/$wildcard.key";

            $cert = $wild_cert if -f $wild_cert;
            $key = $wild_key if -f $wild_key;
        }
    }

    return ($cert, $key, $chain);
}

sub reload_apache {
    print "Reloading Apache...\n";

    # Test configuration first
    my $test = system('/usr/sbin/apachectl', 'configtest');
    if ($test != 0) {
        die "Apache configuration test failed. Not reloading.\n";
    }

    # Graceful reload
    system('/usr/sbin/apachectl', 'graceful');
    print "Apache reloaded successfully.\n";
}

__END__

=head1 NAME

generate-vhost.pl - Frame Applications Virtual Host Configuration Generator

=head1 SYNOPSIS

  generate-vhost.pl --user USERNAME --app APPNAME --domain DOMAIN --port PORT [options]

=head1 DESCRIPTION

This script generates Apache virtual host configurations for Frame applications.
It uses Template Toolkit to process template files and create proper proxy
configurations for routing traffic to Frame instances.

=head1 OPTIONS

=over 4

=item --user USERNAME

The cPanel username owning the application.

=item --app APPNAME

The name of the Frame application.

=item --domain DOMAIN

The domain name to configure.

=item --port PORT

The port number where the Frame instance is running.

=item --ssl

Generate SSL/HTTPS configuration. Requires SSL certificates to be installed.

=item --aliases ALIASES

Comma-separated list of additional domain aliases.

=item --remove

Remove the configuration instead of generating it.

=item --no-reload

Don't reload Apache after making changes.

=item --help

Display help message.

=back

=head1 AUTHOR

Clean Language Team

=cut
