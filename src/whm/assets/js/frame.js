/**
 * Frame Manager - WHM Interface JavaScript
 * Main functionality for WHM admin interface
 */

(function() {
    'use strict';

    // API base URL
    var API_URL = 'api.cgi';

    // Notification timeout
    var NOTIFICATION_TIMEOUT = 5000;

    /**
     * Make an API request
     * @param {string} action - API action
     * @param {Object} params - Additional parameters
     * @param {Function} callback - Callback function(error, data)
     */
    window.apiRequest = function(action, params, callback) {
        params = params || {};
        params.action = action;

        var url = API_URL + '?' + serializeParams(params);

        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.setRequestHeader('Accept', 'application/json');

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            callback(null, response.data);
                        } else {
                            callback(response.error || 'Unknown error', null);
                        }
                    } catch (e) {
                        callback('Invalid JSON response', null);
                    }
                } else {
                    callback('Request failed: ' + xhr.status, null);
                }
            }
        };

        xhr.send();
    };

    /**
     * Make a POST API request
     * @param {string} action - API action
     * @param {Object} data - POST data
     * @param {Function} callback - Callback function(error, data)
     */
    window.apiPost = function(action, data, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', API_URL + '?action=' + encodeURIComponent(action), true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('Accept', 'application/json');

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            callback(null, response.data);
                        } else {
                            callback(response.error || 'Unknown error', null);
                        }
                    } catch (e) {
                        callback('Invalid JSON response', null);
                    }
                } else {
                    callback('Request failed: ' + xhr.status, null);
                }
            }
        };

        xhr.send(JSON.stringify(data));
    };

    /**
     * Serialize parameters for URL
     * @param {Object} params - Parameters object
     * @returns {string} Serialized string
     */
    function serializeParams(params) {
        var parts = [];
        for (var key in params) {
            if (params.hasOwnProperty(key)) {
                parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
            }
        }
        return parts.join('&');
    }

    /**
     * Show a notification
     * @param {string} message - Notification message
     * @param {string} type - Type: 'success', 'error', 'info'
     */
    window.showNotification = function(message, type) {
        type = type || 'info';

        // Remove existing notifications
        var existing = document.querySelectorAll('.notification');
        existing.forEach(function(el) {
            el.remove();
        });

        var notification = document.createElement('div');
        notification.className = 'notification notification-' + type;
        notification.textContent = message;
        document.body.appendChild(notification);

        setTimeout(function() {
            notification.style.opacity = '0';
            notification.style.transform = 'translateX(100%)';
            setTimeout(function() {
                notification.remove();
            }, 300);
        }, NOTIFICATION_TIMEOUT);
    };

    /**
     * Start the Frame manager service
     */
    window.startService = function() {
        showNotification('Starting Frame Manager...', 'info');
        apiPost('start_service', {}, function(error, data) {
            if (error) {
                showNotification('Failed to start: ' + error, 'error');
            } else {
                showNotification('Frame Manager started', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Stop the Frame manager service
     */
    window.stopService = function() {
        if (!confirm('Are you sure you want to stop the Frame Manager? All user instances will be stopped.')) {
            return;
        }
        showNotification('Stopping Frame Manager...', 'info');
        apiPost('stop_service', {}, function(error, data) {
            if (error) {
                showNotification('Failed to stop: ' + error, 'error');
            } else {
                showNotification('Frame Manager stopped', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Restart the Frame manager service
     */
    window.restartService = function() {
        showNotification('Restarting Frame Manager...', 'info');
        apiPost('restart_service', {}, function(error, data) {
            if (error) {
                showNotification('Failed to restart: ' + error, 'error');
            } else {
                showNotification('Frame Manager restarted', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Start a user's Frame instance
     * @param {string} username - cPanel username
     */
    window.startInstance = function(username) {
        showNotification('Starting instance for ' + username + '...', 'info');
        apiPost('start_instance', { user: username }, function(error, data) {
            if (error) {
                showNotification('Failed to start instance: ' + error, 'error');
            } else {
                showNotification('Instance started for ' + username, 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Stop a user's Frame instance
     * @param {string} username - cPanel username
     */
    window.stopInstance = function(username) {
        if (!confirm('Stop Frame instance for ' + username + '?')) {
            return;
        }
        showNotification('Stopping instance for ' + username + '...', 'info');
        apiPost('stop_instance', { user: username }, function(error, data) {
            if (error) {
                showNotification('Failed to stop instance: ' + error, 'error');
            } else {
                showNotification('Instance stopped for ' + username, 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Restart a user's Frame instance
     * @param {string} username - cPanel username
     */
    window.restartInstance = function(username) {
        showNotification('Restarting instance for ' + username + '...', 'info');
        apiPost('restart_instance', { user: username }, function(error, data) {
            if (error) {
                showNotification('Failed to restart instance: ' + error, 'error');
            } else {
                showNotification('Instance restarted for ' + username, 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * View logs for a user
     * @param {string} username - cPanel username
     */
    window.viewUserLogs = function(username) {
        window.location.href = 'index.cgi?view=logs&user=' + encodeURIComponent(username);
    };

    /**
     * Edit settings for a user
     * @param {string} username - cPanel username
     */
    window.editUserSettings = function(username) {
        window.location.href = 'index.cgi?view=user&user=' + encodeURIComponent(username);
    };

    /**
     * Save global settings
     * @param {HTMLFormElement} form - Settings form
     */
    window.saveSettings = function(form) {
        var formData = new FormData(form);
        var settings = {};

        formData.forEach(function(value, key) {
            settings[key] = value;
        });

        showNotification('Saving settings...', 'info');
        apiPost('save_settings', settings, function(error, data) {
            if (error) {
                showNotification('Failed to save: ' + error, 'error');
            } else {
                showNotification('Settings saved successfully', 'success');
            }
        });

        return false; // Prevent form submission
    };

    /**
     * Create a new hosting package
     * @param {HTMLFormElement} form - Package form
     */
    window.createPackage = function(form) {
        var formData = new FormData(form);
        var pkg = {};

        formData.forEach(function(value, key) {
            pkg[key] = value;
        });

        showNotification('Creating package...', 'info');
        apiPost('create_package', pkg, function(error, data) {
            if (error) {
                showNotification('Failed to create package: ' + error, 'error');
            } else {
                showNotification('Package created successfully', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });

        return false;
    };

    /**
     * Delete a hosting package
     * @param {string} packageName - Package name
     */
    window.deletePackage = function(packageName) {
        if (!confirm('Are you sure you want to delete the package "' + packageName + '"?')) {
            return;
        }

        showNotification('Deleting package...', 'info');
        apiPost('delete_package', { name: packageName }, function(error, data) {
            if (error) {
                showNotification('Failed to delete package: ' + error, 'error');
            } else {
                showNotification('Package deleted', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Filter instances table
     */
    window.filterInstances = function() {
        var search = document.getElementById('instance-search');
        var status = document.getElementById('instance-status');

        if (!search || !status) return;

        var searchTerm = search.value.toLowerCase();
        var statusFilter = status.value;

        var rows = document.querySelectorAll('.instance-row');
        rows.forEach(function(row) {
            var user = row.getAttribute('data-user').toLowerCase();
            var rowStatus = row.getAttribute('data-status');

            var matchesSearch = user.indexOf(searchTerm) !== -1;
            var matchesStatus = !statusFilter || rowStatus === statusFilter;

            row.style.display = (matchesSearch && matchesStatus) ? '' : 'none';
        });
    };

    /**
     * Refresh log viewer
     * @param {string} username - Optional username filter
     */
    window.refreshLogs = function(username) {
        var params = {};
        if (username) {
            params.user = username;
        }

        var logViewer = document.getElementById('log-viewer');
        if (!logViewer) return;

        showNotification('Refreshing logs...', 'info');
        apiRequest('logs', params, function(error, data) {
            if (error) {
                showNotification('Failed to refresh logs: ' + error, 'error');
                return;
            }

            if (data && data.logs) {
                var html = '';
                data.logs.forEach(function(line) {
                    var className = 'log-line';
                    if (line.indexOf('ERROR') !== -1) {
                        className += ' log-error';
                    } else if (line.indexOf('WARN') !== -1) {
                        className += ' log-warn';
                    } else if (line.indexOf('DEBUG') !== -1) {
                        className += ' log-debug';
                    }
                    html += '<div class="' + className + '">' + escapeHtml(line) + '</div>';
                });
                logViewer.innerHTML = html;
                logViewer.scrollTop = logViewer.scrollHeight;
                showNotification('Logs refreshed', 'success');
            }
        });
    };

    /**
     * Download logs
     * @param {string} username - Optional username filter
     */
    window.downloadLogs = function(username) {
        var params = { action: 'download_logs' };
        if (username) {
            params.user = username;
        }

        window.location.href = API_URL + '?' + serializeParams(params);
    };

    /**
     * Escape HTML special characters
     * @param {string} str - String to escape
     * @returns {string} Escaped string
     */
    function escapeHtml(str) {
        var div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    /**
     * Format bytes to human readable
     * @param {number} bytes - Bytes
     * @returns {string} Formatted string
     */
    window.formatBytes = function(bytes) {
        if (bytes === 0) return '0 Bytes';
        var k = 1024;
        var sizes = ['Bytes', 'KB', 'MB', 'GB'];
        var i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    };

    /**
     * Format uptime
     * @param {number} seconds - Uptime in seconds
     * @returns {string} Formatted string
     */
    window.formatUptime = function(seconds) {
        var days = Math.floor(seconds / 86400);
        var hours = Math.floor((seconds % 86400) / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);

        var parts = [];
        if (days > 0) parts.push(days + 'd');
        if (hours > 0) parts.push(hours + 'h');
        if (minutes > 0 || parts.length === 0) parts.push(minutes + 'm');

        return parts.join(' ');
    };

    // Auto-refresh status if enabled
    var autoRefreshStatus = false;
    var statusRefreshInterval = null;

    window.toggleAutoRefresh = function(enable) {
        autoRefreshStatus = enable;
        if (enable) {
            statusRefreshInterval = setInterval(function() {
                refreshStatus();
            }, 10000);
        } else if (statusRefreshInterval) {
            clearInterval(statusRefreshInterval);
            statusRefreshInterval = null;
        }
    };

    function refreshStatus() {
        apiRequest('status', {}, function(error, data) {
            if (error) return;

            // Update status values
            if (data.status) {
                var statusEl = document.querySelector('[data-status-field="status"]');
                if (statusEl) {
                    statusEl.textContent = data.status;
                    statusEl.className = 'status-value ' + (data.status === 'running' ? 'status-running' : 'status-stopped');
                }
            }

            if (data.instances !== undefined) {
                var instancesEl = document.querySelector('[data-status-field="instances"]');
                if (instancesEl) {
                    instancesEl.textContent = data.instances;
                }
            }

            if (data.memory_mb !== undefined) {
                var memoryEl = document.querySelector('[data-status-field="memory"]');
                if (memoryEl) {
                    memoryEl.textContent = data.memory_mb + ' MB';
                }
            }

            if (data.uptime !== undefined) {
                var uptimeEl = document.querySelector('[data-status-field="uptime"]');
                if (uptimeEl) {
                    uptimeEl.textContent = formatUptime(data.uptime);
                }
            }
        });
    }

    // Initialize on DOM ready
    document.addEventListener('DOMContentLoaded', function() {
        // Set up filter handlers
        var searchInput = document.getElementById('instance-search');
        var statusSelect = document.getElementById('instance-status');

        if (searchInput) {
            searchInput.addEventListener('keyup', filterInstances);
        }
        if (statusSelect) {
            statusSelect.addEventListener('change', filterInstances);
        }

        // Set up settings form
        var settingsForm = document.getElementById('settings-form');
        if (settingsForm) {
            settingsForm.addEventListener('submit', function(e) {
                e.preventDefault();
                saveSettings(this);
            });
        }

        // Set up package form
        var packageForm = document.getElementById('package-form');
        if (packageForm) {
            packageForm.addEventListener('submit', function(e) {
                e.preventDefault();
                createPackage(this);
            });
        }
    });

})();
