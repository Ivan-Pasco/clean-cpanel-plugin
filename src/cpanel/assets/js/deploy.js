/**
 * Frame Applications - Deploy Page JavaScript
 * Handles application creation and file uploads
 */

(function() {
    'use strict';

    var selectedFiles = [];
    var dropZone = null;
    var fileInput = null;
    var fileList = null;
    var uploadBtn = null;

    /**
     * Initialize deploy page
     */
    function init() {
        // Create App Form
        var createForm = document.getElementById('create-app-form');
        if (createForm) {
            createForm.addEventListener('submit', handleCreateApp);
        }

        // Upload Form
        var uploadForm = document.getElementById('upload-form');
        if (uploadForm) {
            uploadForm.addEventListener('submit', handleUpload);
        }

        // File Input
        fileInput = document.getElementById('upload-file');
        if (fileInput) {
            fileInput.addEventListener('change', handleFileSelect);
        }

        // Drop Zone
        dropZone = document.getElementById('drop-zone');
        if (dropZone) {
            dropZone.addEventListener('click', function() {
                fileInput.click();
            });
            dropZone.addEventListener('dragover', handleDragOver);
            dropZone.addEventListener('dragleave', handleDragLeave);
            dropZone.addEventListener('drop', handleDrop);
        }

        // File list container
        fileList = document.getElementById('file-list');

        // Upload button
        uploadBtn = document.getElementById('upload-btn');
    }

    /**
     * Handle create app form submission
     * @param {Event} e - Submit event
     */
    function handleCreateApp(e) {
        e.preventDefault();

        var nameInput = document.getElementById('app-name');
        var domainInput = document.getElementById('app-domain');

        var name = nameInput.value.trim();
        var domain = domainInput ? domainInput.value.trim() : '';

        if (!name) {
            showNotification('Please enter an application name', 'error');
            return;
        }

        // Validate name format
        if (!/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/.test(name)) {
            showNotification('Invalid name format. Use lowercase letters, numbers, and hyphens.', 'error');
            return;
        }

        deployApp(name, domain, function(error, data) {
            if (!error) {
                nameInput.value = '';
                if (domainInput) domainInput.value = '';
                // Refresh app dropdown
                refreshAppDropdown();
            }
        });
    }

    /**
     * Handle file input change
     * @param {Event} e - Change event
     */
    function handleFileSelect(e) {
        addFiles(e.target.files);
    }

    /**
     * Handle drag over event
     * @param {Event} e - Drag event
     */
    function handleDragOver(e) {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.add('dragover');
    }

    /**
     * Handle drag leave event
     * @param {Event} e - Drag event
     */
    function handleDragLeave(e) {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.remove('dragover');
    }

    /**
     * Handle drop event
     * @param {Event} e - Drop event
     */
    function handleDrop(e) {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.remove('dragover');

        var files = e.dataTransfer.files;
        addFiles(files);
    }

    /**
     * Add files to the upload list
     * @param {FileList} files - Files to add
     */
    function addFiles(files) {
        for (var i = 0; i < files.length; i++) {
            var file = files[i];

            // Check file extension
            if (!file.name.endsWith('.cln') && !file.name.endsWith('.clean')) {
                showNotification('Invalid file type: ' + file.name + '. Only .cln and .clean files are allowed.', 'error');
                continue;
            }

            // Check for duplicates
            var exists = selectedFiles.some(function(f) {
                return f.name === file.name;
            });

            if (!exists) {
                selectedFiles.push(file);
            }
        }

        renderFileList();
        updateUploadButton();
    }

    /**
     * Remove a file from the upload list
     * @param {number} index - File index
     */
    window.removeFile = function(index) {
        selectedFiles.splice(index, 1);
        renderFileList();
        updateUploadButton();
    };

    /**
     * Render the file list
     */
    function renderFileList() {
        if (!fileList) return;

        if (selectedFiles.length === 0) {
            fileList.innerHTML = '';
            return;
        }

        var html = '';
        selectedFiles.forEach(function(file, index) {
            html += '<div class="file-item">' +
                '<div>' +
                '<span class="file-name">' + escapeHtml(file.name) + '</span>' +
                '<span class="file-size">' + formatBytes(file.size) + '</span>' +
                '</div>' +
                '<button type="button" class="btn btn-sm btn-danger" onclick="removeFile(' + index + ')">Remove</button>' +
                '</div>';
        });

        fileList.innerHTML = html;
    }

    /**
     * Update upload button state
     */
    function updateUploadButton() {
        if (!uploadBtn) return;

        var appSelect = document.getElementById('upload-app');
        var appSelected = appSelect && appSelect.value;

        uploadBtn.disabled = selectedFiles.length === 0 || !appSelected;
    }

    /**
     * Handle upload form submission
     * @param {Event} e - Submit event
     */
    function handleUpload(e) {
        e.preventDefault();

        var appSelect = document.getElementById('upload-app');
        var appName = appSelect.value;

        if (!appName) {
            showNotification('Please select an application', 'error');
            return;
        }

        if (selectedFiles.length === 0) {
            showNotification('Please select files to upload', 'error');
            return;
        }

        uploadFiles(appName, selectedFiles);
    }

    /**
     * Upload files to an application
     * @param {string} appName - Application name
     * @param {Array} files - Files to upload
     */
    function uploadFiles(appName, files) {
        uploadBtn.disabled = true;
        uploadBtn.innerHTML = '<span class="spinner"></span> Uploading...';

        var formData = new FormData();
        formData.append('app', appName);

        files.forEach(function(file) {
            formData.append('files[]', file);
        });

        var xhr = new XMLHttpRequest();
        xhr.open('POST', 'api.live.cgi?action=upload', true);

        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                var percent = Math.round((e.loaded / e.total) * 100);
                uploadBtn.innerHTML = '<span class="spinner"></span> Uploading... ' + percent + '%';
            }
        };

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                uploadBtn.disabled = false;
                uploadBtn.innerHTML = 'Upload Files';

                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            showNotification('Files uploaded successfully', 'success');
                            selectedFiles = [];
                            renderFileList();
                            updateUploadButton();

                            // Reset file input
                            if (fileInput) {
                                fileInput.value = '';
                            }
                        } else {
                            showNotification('Upload failed: ' + (response.error || 'Unknown error'), 'error');
                        }
                    } catch (err) {
                        showNotification('Invalid server response', 'error');
                    }
                } else {
                    showNotification('Upload failed: Server error', 'error');
                }
            }
        };

        xhr.send(formData);
    }

    /**
     * Refresh the application dropdown
     */
    function refreshAppDropdown() {
        var appSelect = document.getElementById('upload-app');
        if (!appSelect) return;

        apiRequest('list_apps', {}, function(error, data) {
            if (error) return;

            var currentValue = appSelect.value;
            var html = '<option value="">-- Select Application --</option>';

            if (data && data.apps) {
                data.apps.forEach(function(app) {
                    var selected = app.name === currentValue ? ' selected' : '';
                    html += '<option value="' + escapeHtml(app.name) + '"' + selected + '>' +
                            escapeHtml(app.name) + '</option>';
                });
            }

            appSelect.innerHTML = html;
            updateUploadButton();
        });
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

    // Initialize on app select change
    document.addEventListener('DOMContentLoaded', function() {
        init();

        var appSelect = document.getElementById('upload-app');
        if (appSelect) {
            appSelect.addEventListener('change', updateUploadButton);
        }
    });

})();
