# Frame cPanel Plugin Makefile
# Build automation for development and packaging

.PHONY: all build release test clean install uninstall upgrade rpm deb dev help \
        install-scripts install-daemon install-whm install-cpanel install-apache

# Configuration
CARGO := cargo
INSTALL_PREFIX := /usr/local
CPANEL_PREFIX := /usr/local/cpanel
WHM_DOCROOT := $(CPANEL_PREFIX)/whostmgr/docroot
CPANEL_FRONTEND := $(CPANEL_PREFIX)/base/frontend/jupiter
FRAME_VAR := /var/frame
FRAME_LOG := /var/log/frame
FRAME_ETC := /etc/frame
APACHE_CONF := /etc/apache2/conf.d

# Binary names
MANAGER_BIN := frame-manager

# Version
VERSION := 1.0.0

# Build targets
all: build

# Development build
build:
	@echo "Building Frame manager (debug)..."
	cd src/manager && $(CARGO) build

# Release build
release:
	@echo "Building Frame manager (release)..."
	cd src/manager && $(CARGO) build --release

# Run tests
test:
	@echo "Running tests..."
	cd src/manager && $(CARGO) test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cd src/manager && $(CARGO) clean
	rm -rf target/

# Format code
fmt:
	@echo "Formatting code..."
	cd src/manager && $(CARGO) fmt

# Lint code
lint:
	@echo "Running clippy..."
	cd src/manager && $(CARGO) clippy -- -D warnings

# Check code without building
check:
	@echo "Checking code..."
	cd src/manager && $(CARGO) check

# Development mode - build and run
dev: build
	@echo "Running Frame manager in development mode..."
	cd src/manager && $(CARGO) run --bin frame-manager -- --config ../../packaging/config/frame.conf

# ============================================================
# Installation Targets
# ============================================================

# Full installation (requires root)
install: release
	@echo "Installing Frame cPanel Plugin..."
	@./scripts/install.sh

# Install using shell script (recommended)
install-full: release
	@./scripts/install.sh

# Development installation (symlinks where possible)
install-dev: build
	@./scripts/install.sh --dev

# Uninstall
uninstall:
	@./scripts/uninstall.sh

# Uninstall but keep user data
uninstall-keep-data:
	@./scripts/uninstall.sh --keep-data

# Upgrade
upgrade: release
	@./scripts/upgrade.sh

# ============================================================
# Component Installation (for manual/partial installs)
# ============================================================

# Install just the daemon
install-daemon: release
	@echo "Installing Frame manager daemon..."
	@if [ "$$(id -u)" != "0" ]; then echo "Requires root"; exit 1; fi
	install -m 755 src/manager/target/release/$(MANAGER_BIN) /usr/local/bin/
	install -m 644 packaging/systemd/frame-manager.service /etc/systemd/system/
	mkdir -p $(FRAME_ETC)
	test -f $(FRAME_ETC)/frame.conf || install -m 644 packaging/config/frame.conf $(FRAME_ETC)/
	test -f $(FRAME_ETC)/limits.conf || install -m 644 packaging/config/limits.conf $(FRAME_ETC)/
	systemctl daemon-reload
	systemctl enable frame-manager
	@echo "Daemon installed. Run: systemctl start frame-manager"

# Install WHM interface
install-whm:
	@echo "Installing WHM interface..."
	@if [ "$$(id -u)" != "0" ]; then echo "Requires root"; exit 1; fi
	mkdir -p $(WHM_DOCROOT)/cgi/frame/{templates/apache,assets/css,assets/js,lib}
	cp src/whm/index.cgi $(WHM_DOCROOT)/cgi/frame/
	cp src/whm/api.cgi $(WHM_DOCROOT)/cgi/frame/
	chmod 755 $(WHM_DOCROOT)/cgi/frame/*.cgi
	cp src/whm/lib/FrameWHM.pm $(WHM_DOCROOT)/cgi/frame/lib/
	cp src/whm/templates/*.tmpl $(WHM_DOCROOT)/cgi/frame/templates/
	cp src/whm/assets/css/*.css $(WHM_DOCROOT)/cgi/frame/assets/css/
	cp src/whm/assets/js/*.js $(WHM_DOCROOT)/cgi/frame/assets/js/
	mkdir -p $(CPANEL_PREFIX)/Whostmgr/API/1
	cp src/api/whm/Frame.pm $(CPANEL_PREFIX)/Whostmgr/API/1/
	cp src/whm/plugin/icons/frame-icon.svg $(WHM_DOCROOT)/themes/x/icons/frame.svg
	@echo "WHM interface installed."

# Install cPanel interface
install-cpanel:
	@echo "Installing cPanel interface..."
	@if [ "$$(id -u)" != "0" ]; then echo "Requires root"; exit 1; fi
	mkdir -p $(CPANEL_FRONTEND)/frame/{views,assets/css,assets/js,lib}
	cp src/cpanel/index.live.cgi $(CPANEL_FRONTEND)/frame/
	cp src/cpanel/api.live.cgi $(CPANEL_FRONTEND)/frame/
	chmod 755 $(CPANEL_FRONTEND)/frame/*.cgi
	cp src/cpanel/lib/FrameCpanel.pm $(CPANEL_FRONTEND)/frame/lib/
	cp src/cpanel/views/*.tt $(CPANEL_FRONTEND)/frame/views/
	cp src/cpanel/assets/css/*.css $(CPANEL_FRONTEND)/frame/assets/css/
	cp src/cpanel/assets/js/*.js $(CPANEL_FRONTEND)/frame/assets/js/
	cp src/cpanel/plugin/icons/frame-icon.svg $(CPANEL_FRONTEND)/frame/
	mkdir -p $(CPANEL_PREFIX)/Cpanel/API
	cp src/api/cpanel/Frame.pm $(CPANEL_PREFIX)/Cpanel/API/
	mkdir -p $(CPANEL_FRONTEND)/dynamicui
	cp src/cpanel/plugin/dynamicui/frame.conf $(CPANEL_FRONTEND)/dynamicui/
	@echo "cPanel interface installed."

# Install Apache configuration
install-apache:
	@echo "Installing Apache configuration..."
	@if [ "$$(id -u)" != "0" ]; then echo "Requires root"; exit 1; fi
	mkdir -p $(APACHE_CONF)/frame/domains
	mkdir -p /var/www/frame-error
	cp src/apache/conf/frame.conf $(APACHE_CONF)/
	cp src/apache/templates/*.tmpl $(WHM_DOCROOT)/cgi/frame/templates/apache/
	cp src/apache/error-pages/*.html /var/www/frame-error/
	cp src/apache/scripts/generate-vhost.pl $(WHM_DOCROOT)/cgi/frame/
	cp src/apache/scripts/frame-apache-ctl.sh /usr/local/bin/
	chmod 755 $(WHM_DOCROOT)/cgi/frame/generate-vhost.pl
	chmod 755 /usr/local/bin/frame-apache-ctl.sh
	@echo "Apache configuration installed."

# Install hooks
install-hooks:
	@echo "Installing cPanel hooks..."
	@if [ "$$(id -u)" != "0" ]; then echo "Requires root"; exit 1; fi
	mkdir -p $(CPANEL_PREFIX)/scripts/postwwwacct
	mkdir -p $(CPANEL_PREFIX)/scripts/prekillacct
	mkdir -p $(CPANEL_PREFIX)/scripts/postacctremove
	cp src/hooks/postwwwacct $(CPANEL_PREFIX)/scripts/postwwwacct/frame
	cp src/hooks/prekillacct $(CPANEL_PREFIX)/scripts/prekillacct/frame
	cp src/hooks/postacctremove $(CPANEL_PREFIX)/scripts/postacctremove/frame
	chmod 755 $(CPANEL_PREFIX)/scripts/postwwwacct/frame
	chmod 755 $(CPANEL_PREFIX)/scripts/prekillacct/frame
	chmod 755 $(CPANEL_PREFIX)/scripts/postacctremove/frame
	@echo "Hooks installed."

# ============================================================
# Packaging
# ============================================================

# Build RPM package
rpm: release
	@echo "Building RPM package..."
	@if ! command -v rpmbuild >/dev/null 2>&1; then \
		echo "rpmbuild not found. Install rpm-build package."; \
		exit 1; \
	fi
	mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	cp packaging/rpm/frame-cpanel.spec ~/rpmbuild/SPECS/
	tar -czf ~/rpmbuild/SOURCES/frame-cpanel-$(VERSION).tar.gz \
		--transform 's,^,frame-cpanel-$(VERSION)/,' \
		src/manager/target/release/$(MANAGER_BIN) \
		src/whm src/cpanel src/hooks src/api src/apache \
		packaging/config packaging/systemd \
		scripts README.md LICENSE
	rpmbuild -ba ~/rpmbuild/SPECS/frame-cpanel.spec
	@echo "RPM package built in ~/rpmbuild/RPMS/"

# Build tarball for distribution
tarball: release
	@echo "Building tarball..."
	mkdir -p dist
	tar -czf dist/frame-cpanel-$(VERSION).tar.gz \
		--transform 's,^,frame-cpanel-$(VERSION)/,' \
		src/manager/target/release/$(MANAGER_BIN) \
		src/whm src/cpanel src/hooks src/api src/apache \
		packaging scripts Makefile README.md LICENSE
	@echo "Tarball created: dist/frame-cpanel-$(VERSION).tar.gz"

# Build DEB package (future)
deb: release
	@echo "DEB packaging not yet implemented"

# ============================================================
# Utility Targets
# ============================================================

# Create initial directories (for development)
init-dirs:
	mkdir -p $(FRAME_VAR)/instances
	mkdir -p $(FRAME_LOG)
	mkdir -p $(FRAME_ETC)

# Validate installation
validate:
	@echo "Validating installation..."
	@test -f /usr/local/bin/frame-manager && echo "✓ Daemon installed" || echo "✗ Daemon missing"
	@test -f /etc/systemd/system/frame-manager.service && echo "✓ Systemd service installed" || echo "✗ Systemd service missing"
	@test -d $(WHM_DOCROOT)/cgi/frame && echo "✓ WHM interface installed" || echo "✗ WHM interface missing"
	@test -d $(CPANEL_FRONTEND)/frame && echo "✓ cPanel interface installed" || echo "✗ cPanel interface missing"
	@test -f $(APACHE_CONF)/frame.conf && echo "✓ Apache config installed" || echo "✗ Apache config missing"
	@systemctl is-active --quiet frame-manager && echo "✓ Service running" || echo "✗ Service not running"

# Show help
help:
	@echo "Frame cPanel Plugin - Build Targets"
	@echo ""
	@echo "Build:"
	@echo "  make build      - Build debug version"
	@echo "  make release    - Build release version"
	@echo "  make test       - Run tests"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make fmt        - Format code"
	@echo "  make lint       - Run clippy linter"
	@echo "  make check      - Check code without building"
	@echo "  make dev        - Build and run in development mode"
	@echo ""
	@echo "Installation (requires root):"
	@echo "  make install    - Full installation"
	@echo "  make install-dev- Development installation"
	@echo "  make uninstall  - Remove from system"
	@echo "  make upgrade    - Upgrade existing installation"
	@echo "  make validate   - Validate installation"
	@echo ""
	@echo "Component installation:"
	@echo "  make install-daemon  - Install daemon only"
	@echo "  make install-whm     - Install WHM interface"
	@echo "  make install-cpanel  - Install cPanel interface"
	@echo "  make install-apache  - Install Apache configuration"
	@echo "  make install-hooks   - Install cPanel hooks"
	@echo ""
	@echo "Packaging:"
	@echo "  make rpm        - Build RPM package"
	@echo "  make tarball    - Build distribution tarball"
	@echo "  make deb        - Build DEB package (not implemented)"
	@echo ""
