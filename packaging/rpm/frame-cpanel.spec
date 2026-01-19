%define name frame-cpanel
%define version 1.0.0
%define release 1
%define _prefix /usr/local

Name:           %{name}
Version:        %{version}
Release:        %{release}%{?dist}
Summary:        Frame Applications cPanel Plugin

License:        MIT
URL:            https://cleanlanguage.dev
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc
Requires:       cpanel
Requires:       perl-Template-Toolkit
Requires:       perl-JSON
Requires:       perl-CGI
Requires:       httpd
Requires:       mod_proxy_html

%description
Frame cPanel Plugin enables hosting providers to offer Clean Language/Frame
application hosting through cPanel/WHM. It provides a complete platform for
deploying, managing, and monitoring WebAssembly-based applications.

Features:
- WHM admin interface for server-wide management
- cPanel user interface for application deployment
- Automatic port allocation and process management
- Apache reverse proxy configuration
- Resource limits and monitoring

%prep
%setup -q

%build
cd src/manager
cargo build --release

%install
rm -rf %{buildroot}

# Create directories
mkdir -p %{buildroot}/usr/local/bin
mkdir -p %{buildroot}/etc/systemd/system
mkdir -p %{buildroot}/etc/frame
mkdir -p %{buildroot}/var/frame/instances
mkdir -p %{buildroot}/var/log/frame
mkdir -p %{buildroot}/etc/apache2/conf.d/frame/domains
mkdir -p %{buildroot}/var/www/frame-error

# cPanel directories
mkdir -p %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/views
mkdir -p %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/assets/css
mkdir -p %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/assets/js
mkdir -p %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/lib
mkdir -p %{buildroot}/usr/local/cpanel/base/frontend/jupiter/dynamicui
mkdir -p %{buildroot}/usr/local/cpanel/Cpanel/API

# WHM directories
mkdir -p %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/templates/apache
mkdir -p %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/assets/css
mkdir -p %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/assets/js
mkdir -p %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/lib
mkdir -p %{buildroot}/usr/local/cpanel/whostmgr/docroot/themes/x/icons
mkdir -p %{buildroot}/usr/local/cpanel/Whostmgr/API/1

# Hook directories
mkdir -p %{buildroot}/usr/local/cpanel/scripts/postwwwacct
mkdir -p %{buildroot}/usr/local/cpanel/scripts/prekillacct
mkdir -p %{buildroot}/usr/local/cpanel/scripts/postacctremove

# Install daemon
install -m 755 target/release/frame-manager %{buildroot}/usr/local/bin/

# Install systemd service
install -m 644 packaging/systemd/frame-manager.service %{buildroot}/etc/systemd/system/

# Install configuration
install -m 644 packaging/config/frame.conf %{buildroot}/etc/frame/
install -m 644 packaging/config/limits.conf %{buildroot}/etc/frame/

# Install hooks
install -m 755 src/hooks/postwwwacct %{buildroot}/usr/local/cpanel/scripts/postwwwacct/frame
install -m 755 src/hooks/prekillacct %{buildroot}/usr/local/cpanel/scripts/prekillacct/frame
install -m 755 src/hooks/postacctremove %{buildroot}/usr/local/cpanel/scripts/postacctremove/frame

# Install WHM interface
install -m 755 src/whm/index.cgi %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/
install -m 755 src/whm/api.cgi %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/
install -m 644 src/whm/lib/FrameWHM.pm %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/lib/
install -m 644 src/whm/templates/*.tmpl %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/templates/
install -m 644 src/whm/assets/css/*.css %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/assets/css/
install -m 644 src/whm/assets/js/*.js %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/assets/js/
install -m 644 src/api/whm/Frame.pm %{buildroot}/usr/local/cpanel/Whostmgr/API/1/
install -m 644 src/whm/plugin/icons/frame-icon.svg %{buildroot}/usr/local/cpanel/whostmgr/docroot/themes/x/icons/frame.svg

# Install cPanel interface
install -m 755 src/cpanel/index.live.cgi %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/
install -m 755 src/cpanel/api.live.cgi %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/
install -m 644 src/cpanel/lib/FrameCpanel.pm %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/lib/
install -m 644 src/cpanel/views/*.tt %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/views/
install -m 644 src/cpanel/assets/css/*.css %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/assets/css/
install -m 644 src/cpanel/assets/js/*.js %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/assets/js/
install -m 644 src/api/cpanel/Frame.pm %{buildroot}/usr/local/cpanel/Cpanel/API/
install -m 644 src/cpanel/plugin/icons/frame-icon.svg %{buildroot}/usr/local/cpanel/base/frontend/jupiter/frame/
install -m 644 src/cpanel/plugin/dynamicui/frame.conf %{buildroot}/usr/local/cpanel/base/frontend/jupiter/dynamicui/

# Install Apache configuration
install -m 644 src/apache/conf/frame.conf %{buildroot}/etc/apache2/conf.d/
install -m 644 src/apache/templates/*.tmpl %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/templates/apache/
install -m 644 src/apache/error-pages/*.html %{buildroot}/var/www/frame-error/
install -m 755 src/apache/scripts/generate-vhost.pl %{buildroot}/usr/local/cpanel/whostmgr/docroot/cgi/frame/
install -m 755 src/apache/scripts/frame-apache-ctl.sh %{buildroot}/usr/local/bin/

%files
%defattr(-,root,root,-)
%doc README.md
%license LICENSE

# Binaries
/usr/local/bin/frame-manager
/usr/local/bin/frame-apache-ctl.sh

# Systemd
/etc/systemd/system/frame-manager.service

# Configuration (marked as config to preserve on upgrade)
%config(noreplace) /etc/frame/frame.conf
%config(noreplace) /etc/frame/limits.conf

# Data directories
%dir /var/frame
%dir /var/frame/instances
%dir /var/log/frame

# Apache configuration
%config(noreplace) /etc/apache2/conf.d/frame.conf
%dir /etc/apache2/conf.d/frame
%dir /etc/apache2/conf.d/frame/domains
/var/www/frame-error/*

# Hooks
/usr/local/cpanel/scripts/postwwwacct/frame
/usr/local/cpanel/scripts/prekillacct/frame
/usr/local/cpanel/scripts/postacctremove/frame

# WHM interface
/usr/local/cpanel/whostmgr/docroot/cgi/frame/*
/usr/local/cpanel/whostmgr/docroot/themes/x/icons/frame.svg
/usr/local/cpanel/Whostmgr/API/1/Frame.pm

# cPanel interface
/usr/local/cpanel/base/frontend/jupiter/frame/*
/usr/local/cpanel/base/frontend/jupiter/dynamicui/frame.conf
/usr/local/cpanel/Cpanel/API/Frame.pm

%pre
# Pre-installation script
if systemctl is-active --quiet frame-manager 2>/dev/null; then
    systemctl stop frame-manager
fi

%post
# Post-installation script
systemctl daemon-reload
systemctl enable frame-manager
systemctl start frame-manager

# Initialize Apache configuration
/usr/local/bin/frame-apache-ctl.sh init || true

# Rebuild cPanel sprites
/usr/local/cpanel/bin/rebuild_sprites 2>/dev/null || true

echo "Frame cPanel Plugin installed successfully!"
echo "Access WHM > Plugins > Frame Manager to configure."

%preun
# Pre-uninstallation script
if [ $1 -eq 0 ]; then
    # Complete uninstall (not upgrade)
    if systemctl is-active --quiet frame-manager 2>/dev/null; then
        systemctl stop frame-manager
    fi
    systemctl disable frame-manager 2>/dev/null || true
fi

%postun
# Post-uninstallation script
if [ $1 -eq 0 ]; then
    # Complete uninstall (not upgrade)
    systemctl daemon-reload

    # Clean up Apache configuration
    /usr/local/bin/frame-apache-ctl.sh cleanup 2>/dev/null || true

    # Reload Apache
    apachectl graceful 2>/dev/null || true
fi

%changelog
* Mon Jan 01 2026 Clean Language Team <team@cleanlanguage.dev> - 1.0.0-1
- Initial release
- WHM admin interface for Frame management
- cPanel user interface for application deployment
- Apache reverse proxy configuration
- Automatic port allocation
- Process health monitoring
- cPanel account hooks integration
