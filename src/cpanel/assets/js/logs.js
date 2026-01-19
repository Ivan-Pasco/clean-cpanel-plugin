/**
 * Frame Applications - Log Viewer JavaScript
 * Handles real-time log viewing and filtering
 */

(function() {
    'use strict';

    var logViewer = null;
    var searchInput = null;
    var levelSelect = null;
    var autoRefreshCheckbox = null;
    var refreshInterval = null;
    var allLogLines = [];

    // Auto-refresh interval in milliseconds
    var REFRESH_INTERVAL = 5000;

    /**
     * Initialize log viewer
     */
    function init() {
        logViewer = document.getElementById('log-viewer');
        searchInput = document.getElementById('log-search');
        levelSelect = document.getElementById('log-level');
        autoRefreshCheckbox = document.getElementById('auto-refresh');

        if (autoRefreshCheckbox) {
            autoRefreshCheckbox.addEventListener('change', handleAutoRefreshChange);
        }

        // Store initial log lines
        if (logViewer) {
            var lines = logViewer.querySelectorAll('.log-line');
            lines.forEach(function(line) {
                allLogLines.push(line.textContent);
            });

            // Scroll to bottom
            logViewer.scrollTop = logViewer.scrollHeight;
        }
    }

    /**
     * Refresh logs from server
     */
    window.refreshLogs = function() {
        var params = {};
        if (window.currentApp) {
            params.app = currentApp;
        }

        showNotification('Refreshing logs...', 'info');

        apiRequest('logs', params, function(error, data) {
            if (error) {
                showNotification('Failed to refresh logs: ' + error, 'error');
                return;
            }

            if (data && data.logs) {
                allLogLines = data.logs;
                renderLogs();
                showNotification('Logs refreshed', 'success');
            }
        });
    };

    /**
     * Filter logs based on search and level
     */
    window.filterLogs = function() {
        renderLogs();
    };

    /**
     * Render logs with current filters
     */
    function renderLogs() {
        if (!logViewer) return;

        var searchTerm = searchInput ? searchInput.value.toLowerCase() : '';
        var levelFilter = levelSelect ? levelSelect.value : '';

        var filteredLines = allLogLines.filter(function(line) {
            // Apply search filter
            if (searchTerm && line.toLowerCase().indexOf(searchTerm) === -1) {
                return false;
            }

            // Apply level filter
            if (levelFilter && line.indexOf(levelFilter) === -1) {
                return false;
            }

            return true;
        });

        if (filteredLines.length === 0) {
            logViewer.innerHTML = '<p class="no-data">No logs match your filters.</p>';
            return;
        }

        var html = '';
        filteredLines.forEach(function(line) {
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
    }

    /**
     * Handle auto-refresh checkbox change
     */
    function handleAutoRefreshChange() {
        if (autoRefreshCheckbox.checked) {
            startAutoRefresh();
        } else {
            stopAutoRefresh();
        }
    }

    /**
     * Start auto-refresh timer
     */
    function startAutoRefresh() {
        if (refreshInterval) {
            clearInterval(refreshInterval);
        }

        refreshInterval = setInterval(function() {
            fetchNewLogs();
        }, REFRESH_INTERVAL);
    }

    /**
     * Stop auto-refresh timer
     */
    function stopAutoRefresh() {
        if (refreshInterval) {
            clearInterval(refreshInterval);
            refreshInterval = null;
        }
    }

    /**
     * Fetch new logs silently (without notification)
     */
    function fetchNewLogs() {
        var params = { since: allLogLines.length };
        if (window.currentApp) {
            params.app = currentApp;
        }

        apiRequest('logs', params, function(error, data) {
            if (error) return;

            if (data && data.logs && data.logs.length > 0) {
                // If we got new logs, append them
                if (data.append) {
                    data.logs.forEach(function(line) {
                        allLogLines.push(line);
                    });
                } else {
                    // Full refresh
                    allLogLines = data.logs;
                }
                renderLogs();
            }
        });
    }

    /**
     * Download logs as a file
     */
    window.downloadLogs = function() {
        var content = allLogLines.join('\n');
        var filename = 'frame-logs';
        if (window.currentApp) {
            filename += '-' + currentApp;
        }
        filename += '-' + formatDateForFilename(new Date()) + '.txt';

        downloadTextFile(content, filename);
        showNotification('Logs downloaded', 'success');
    };

    /**
     * Download text content as a file
     * @param {string} content - Text content
     * @param {string} filename - File name
     */
    function downloadTextFile(content, filename) {
        var blob = new Blob([content], { type: 'text/plain' });
        var url = URL.createObjectURL(blob);

        var a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);

        URL.revokeObjectURL(url);
    }

    /**
     * Format date for filename
     * @param {Date} date - Date object
     * @returns {string} Formatted date string
     */
    function formatDateForFilename(date) {
        var year = date.getFullYear();
        var month = String(date.getMonth() + 1).padStart(2, '0');
        var day = String(date.getDate()).padStart(2, '0');
        var hours = String(date.getHours()).padStart(2, '0');
        var minutes = String(date.getMinutes()).padStart(2, '0');
        return year + month + day + '-' + hours + minutes;
    }

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

    // Polyfill for padStart
    if (!String.prototype.padStart) {
        String.prototype.padStart = function(targetLength, padString) {
            targetLength = targetLength >> 0;
            padString = String(typeof padString !== 'undefined' ? padString : ' ');
            if (this.length >= targetLength) {
                return String(this);
            }
            targetLength = targetLength - this.length;
            if (targetLength > padString.length) {
                padString += padString.repeat(targetLength / padString.length);
            }
            return padString.slice(0, targetLength) + String(this);
        };
    }

    // Initialize on DOM ready
    document.addEventListener('DOMContentLoaded', init);

    // Cleanup on page unload
    window.addEventListener('beforeunload', function() {
        stopAutoRefresh();
    });

})();
