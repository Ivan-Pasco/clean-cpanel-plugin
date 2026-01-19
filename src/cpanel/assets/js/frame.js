/**
 * Frame Applications - cPanel Interface JavaScript
 * Main functionality shared across all pages
 */

(function() {
    'use strict';

    // API base URL
    var API_URL = 'api.live.cgi';

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
     * Start the Frame instance
     */
    window.startInstance = function() {
        showNotification('Starting instance...', 'info');
        apiRequest('start', {}, function(error, data) {
            if (error) {
                showNotification('Failed to start: ' + error, 'error');
            } else {
                showNotification('Instance started successfully', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Stop the Frame instance
     */
    window.stopInstance = function() {
        if (!confirm('Are you sure you want to stop the Frame instance?')) {
            return;
        }
        showNotification('Stopping instance...', 'info');
        apiRequest('stop', {}, function(error, data) {
            if (error) {
                showNotification('Failed to stop: ' + error, 'error');
            } else {
                showNotification('Instance stopped', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Restart the Frame instance
     */
    window.restartInstance = function() {
        showNotification('Restarting instance...', 'info');
        apiRequest('restart', {}, function(error, data) {
            if (error) {
                showNotification('Failed to restart: ' + error, 'error');
            } else {
                showNotification('Instance restarted successfully', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Deploy/create a new application
     * @param {string} name - Application name
     * @param {string} domain - Optional domain
     * @param {Function} callback - Optional callback
     */
    window.deployApp = function(name, domain, callback) {
        if (typeof domain === 'function') {
            callback = domain;
            domain = null;
        }

        var params = { name: name };
        if (domain) {
            params.domain = domain;
        }

        showNotification('Creating application...', 'info');
        apiPost('deploy', params, function(error, data) {
            if (error) {
                showNotification('Failed to create app: ' + error, 'error');
                if (callback) callback(error);
            } else {
                showNotification('Application created successfully', 'success');
                if (callback) {
                    callback(null, data);
                } else {
                    setTimeout(function() {
                        window.location.href = 'index.live.cgi?action=apps';
                    }, 1000);
                }
            }
        });
    };

    /**
     * Delete an application
     * @param {string} name - Application name
     * @param {Function} callback - Optional callback
     */
    window.deleteApp = function(name, callback) {
        if (!confirm('Are you sure you want to delete "' + name + '"? This cannot be undone.')) {
            return;
        }

        showNotification('Deleting application...', 'info');
        apiPost('delete', { name: name }, function(error, data) {
            if (error) {
                showNotification('Failed to delete: ' + error, 'error');
                if (callback) callback(error);
            } else {
                showNotification('Application deleted', 'success');
                if (callback) {
                    callback(null);
                } else {
                    setTimeout(function() {
                        location.reload();
                    }, 1000);
                }
            }
        });
    };

    /**
     * Update application domain
     * @param {string} appName - Application name
     * @param {string} domain - New domain
     */
    window.updateDomain = function(appName, domain) {
        showNotification('Updating domain...', 'info');
        apiPost('update_domain', { name: appName, domain: domain }, function(error, data) {
            if (error) {
                showNotification('Failed to update domain: ' + error, 'error');
            } else {
                showNotification('Domain updated successfully', 'success');
                setTimeout(function() {
                    location.reload();
                }, 1000);
            }
        });
    };

    /**
     * Add an environment variable
     * @param {string} key - Variable name
     * @param {string} value - Variable value
     */
    window.addEnvVar = function(key, value) {
        if (!window.currentApp) {
            showNotification('No application selected', 'error');
            return;
        }

        apiPost('set_env', { name: currentApp, key: key, value: value }, function(error, data) {
            if (error) {
                showNotification('Failed to add variable: ' + error, 'error');
            } else {
                showNotification('Environment variable added', 'success');
                location.reload();
            }
        });
    };

    /**
     * Remove an environment variable
     * @param {string} key - Variable name
     */
    window.removeEnvVar = function(key) {
        if (!window.currentApp) {
            showNotification('No application selected', 'error');
            return;
        }

        if (!confirm('Remove environment variable "' + key + '"?')) {
            return;
        }

        apiPost('remove_env', { name: currentApp, key: key }, function(error, data) {
            if (error) {
                showNotification('Failed to remove variable: ' + error, 'error');
            } else {
                showNotification('Environment variable removed', 'success');
                location.reload();
            }
        });
    };

    /**
     * Format bytes to human readable size
     * @param {number} bytes - Size in bytes
     * @returns {string} Formatted size
     */
    window.formatBytes = function(bytes) {
        if (bytes === 0) return '0 Bytes';
        var k = 1024;
        var sizes = ['Bytes', 'KB', 'MB', 'GB'];
        var i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    };

    /**
     * Format timestamp to locale string
     * @param {number} timestamp - Unix timestamp
     * @returns {string} Formatted date
     */
    window.formatDate = function(timestamp) {
        if (!timestamp) return 'N/A';
        return new Date(timestamp * 1000).toLocaleString();
    };

    /**
     * Debounce function calls
     * @param {Function} func - Function to debounce
     * @param {number} wait - Wait time in ms
     * @returns {Function} Debounced function
     */
    window.debounce = function(func, wait) {
        var timeout;
        return function() {
            var context = this;
            var args = arguments;
            clearTimeout(timeout);
            timeout = setTimeout(function() {
                func.apply(context, args);
            }, wait);
        };
    };

    // Initialize on DOM ready
    document.addEventListener('DOMContentLoaded', function() {
        // Format all timestamps
        var timestamps = document.querySelectorAll('[data-timestamp]');
        timestamps.forEach(function(el) {
            var ts = parseInt(el.getAttribute('data-timestamp'));
            if (ts) {
                el.textContent = formatDate(ts);
            }
        });
    });

})();
