# Custom Nginx Configuration Guide

This guide explains how to use a custom configuration file in the `/etc/nginx/conf.d` directory for Nginx.

### Creating the Configuration File

1.  **Navigate to the `conf.d` Directory**:
    Open a terminal and navigate to the `/etc/nginx/conf.d` directory.

    ```bash
    cd /etc/nginx/conf.d

    ```

2.  **Create a New Configuration File:**
    Use a text editor to create a new file named custom_settings.conf.

        ```bash
        #create a conf file with nano
        sudo nano custom_settings.conf

3.  **Add Custom Directives:**
    In the custom_settings.conf file, add the following directives:

    ```bash
    # Custom Nginx Configuration

    # Client Max Body Size
    client_max_body_size 512M;

    # Underscores in Headers
    underscores_in_headers on;

    # Add any additional custom directives here
    ```

4.  Save and Exit:
    Save the file and exit the text editor.

### Testing and Applying the Configuration

1. Test the Configuration:
   Before applying the changes, test the Nginx configuration for syntax errors.

   ```bash
       sudo nginx -t
   ```

2. Reload Nginx:
   If the test is successful, reload Nginx to apply the changes.

   ```bash
   sudo systemctl reload nginx
   ```

# Virtual Host Configuration

### Nginx Virtual host Configuration for `v2.thestudypath.com`

<i> **Note:** this can be any valid domain points to the server which will be used to host admin and api. **v2.thestudypath.com** is used in all Android Apps.</i>

This document details the Nginx server configuration for the `v2.thestudypath.com` domain.

## Configuration Details

The configuration sets up an HTTPS server for hosting a web application and redirects all HTTP traffic to HTTPS. It also includes a proxy setup for API requests.

### HTTPS Server Configuration

The HTTPS server block is configured to serve the web application from a specific directory and handle SSL encryption.

```nginx
server {
    # the username jantu can be change in cat `v2.thestudypath.com.conf` file
    # location of local frontend repo `/home/jantu/FRONTEND/studypath-admin-v2/`
    root /home/jantu/FRONTEND/studypath-admin-v2/build;
    server_name v2.thestudypath.com;

    location / {
        try_files $uri /index.html;
    }

    location /api {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/v2.thestudypath.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/v2.thestudypath.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
```

### HTTP Server Configuration (Redirect to HTTPS)

The HTTP server block is configured to redirect all traffic to the HTTPS server.

```nginx
server {
    if ($host = v2.thestudypath.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    server_name v2.thestudypath.com;
    listen 80;
    return 404; # managed by Certbot
}
```

## Deployment Instructions

1. **Create the Configuration File**:

   - Place the above configuration in a file inside `/etc/nginx/sites-available/`.
   - You can use any text editor to create and edit the file. For example:
     ```bash
     sudo nano /etc/nginx/sites-available/v2.thestudypath.com
     ```

2. **Enable the Site**:

   - Create a symbolic link to this file in the `/etc/nginx/sites-enabled/` directory.
     ```bash
     sudo ln -s /etc/nginx/sites-available/v2.thestudypath.com /etc/nginx/sites-enabled/
     ```

3. **Test the Configuration**:

   - Always test the Nginx configuration for syntax errors before applying.
     ```bash
     sudo nginx -t
     ```

4. **Reload Nginx**:
   - If the configuration test is successful, reload Nginx to apply the changes.
     ```bash
     sudo systemctl reload nginx
     ```

## Important Considerations

- Ensure that the SSL certificates are properly set up and renewed regularly, typically managed by Certbot.
- The API server should be operational and accessible on the specified port (`localhost:4000`) for the proxy settings to function correctly.
- The Nginx user (typically `www-data`) needs read access to the specified root directory and its contents.

```
This document provides a comprehensive guide to setting up the Nginx configuration for `v2.thestudypath.com`, including handling HTTPS, SSL certificates, and proxying API requests. It also includes instructions for deploying the configuration.
```


# MongoDB Configuration Guide

This document outlines the MongoDB configuration based on the provided `mongod.conf` file. The configuration includes settings for data storage, system logging, network interfaces, process management, and security.

## Configuration File: `mongod.conf`

The `mongod.conf` file contains settings that define how MongoDB operates. Below are the key components of the configuration:

### Storage

- **Data Storage Path (`dbPath`)**: Specifies the directory where MongoDB stores database files.
- **Journaling (`journal`)**: Enables journaling for write operations to enhance data integrity.

```yaml
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
```

### System Log

- **Destination**: Defines the output destination for log data.
- **Log Append**: Allows appending to the log file (as opposed to overwriting).
- **Log Path**: Specifies the path to the log file.

```yaml
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
```

### Network Interfaces

- **Port**: The port on which MongoDB listens for connections.
- **Bind IP**: Specifies the IP addresses MongoDB listens on, allowing connections from localhost and a specific public IP ( in this case 139.59.18.205) where the mongo is hosted.

```yaml
net:
  port: 27017
  bindIp: 127.0.0.1,139.59.18.205
```

### Process Management

- **Time Zone Info**: Sets the time zone database for time-related operations in MongoDB.

```yaml
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
```

### Security

- **Authorization**: Enables role-based access control to enforce user and role management.

```yaml
security:
  authorization: enabled
```

## Applying the Configuration

1. **Edit the Configuration File**:
   - Modify the `mongod.conf` file located at `/etc/mongod.conf` or the relevant path for your MongoDB installation.
   - Use a text editor to make changes, for example:
     ```bash
     sudo nano /etc/mongod.conf
     ```

2. **Restart MongoDB**:
   - After making changes, restart the MongoDB service to apply the new configuration.
     ```bash
     sudo systemctl restart mongod
     ```

3. **Verify the Changes**:
   - Check the MongoDB logs or use MongoDB shell commands to verify that the new settings are active.

## Security Considerations

- **Restrict Network Access**: Be cautious with `bindIp` settings. Limit MongoDB exposure to the internet.
- **Enable Authentication**: With `authorization: enabled`, ensure you have set up user accounts with appropriate permissions.
- **Regular Updates and Monitoring**: Keep MongoDB updated and monitor logs for any unusual activities.

## Additional Notes

- Always back up your database and configuration files before making significant changes.
- Consult the [MongoDB Documentation](http://docs.mongodb.org/manual/reference/configuration-options/) for detailed information on each configuration option.
