# MERN Stack Setup Script Documentation (ADMIN & API )

## Overview

This script automates the setup of a MERN (MongoDB, Express, React, Node.js) stack on an Ubuntu server. It handles the creation of a new sudo user, installs necessary dependencies, clones project repositories, configures MongoDB and Nginx, sets up a firewall, and installs SSL certificates.

## Prerequisites

- An Ubuntu server with root access.
- Basic familiarity with terminal and command-line operations.

## Features

1. **Sudo User Creation**: Prompts to create a new user with sudo privileges.
2. **Dependency Installation**: Installs Nginx, MongoDB, Git, Node.js (using NVM), and PM2.
3. **Repository Cloning**: Clones backend, frontend, and server configuration repositories from Git.
4. **Configuration File Management**: Backs up original configuration files and copies new configurations for Nginx and MongoDB.
5. **Firewall Setup**: Configures UFW to allow essential traffic and enhance security.
6. **SSL Configuration**: Uses Certbot to install SSL certificates for Nginx.

## Usage Guide

### 1. Running the Script

- Log in to your server as the root user.
- Download or create the setup script on your server.
- Make the script executable:
  ```bash
  chmod +x setup_script.sh
  ```
- Run the script:
  ```bash
  ./setup_script.sh
  ```

### 2. User Interactions

- **New Sudo User**: Enter the desired username for the new sudo user.
- **SSH Key**: If prompted, enter details for SSH key generation.
- **Virtual Host Configuration**: Enter the filename for the Nginx virtual host (typically your domain name).
- **Database Restoration**: Enter the MongoDB details and the name of the backup file to restore.
- **SSL Setup**: Follow the interactive prompts by Certbot to configure SSL for your domain.

### 3. Post-Execution

- The script will automatically configure the firewall and restart necessary services.
- SSL certificates will be installed and configured for your domain.

## Notes

- **Domain Names**: Before running the SSL setup, ensure you have your domain names pointing to the server.
- **Manual Intervention**: The SSL setup step requires manual input of your domain names.
- **Security**: Always review scripts and understand their actions before running them, especially when they require root access.

## Troubleshooting

- If any step fails, refer to the console output for error messages.
- You can manually edit configuration files using the backups created by the script.

## Conclusion

This script provides a streamlined approach to setting up a MERN stack, automating many of the repetitive and error-prone steps involved in configuring a new server. It is designed for those who wish to quickly deploy a MERN application with standard configurations while maintaining essential security practices.
