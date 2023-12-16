#!/bin/bash

# Global variable
PROJECT_PATH=$HOME

# Function to create a new sudo user
create_sudo_user() {
     # Ask for the new username
    read -p "Enter the new username: " NEW_USER

    # Check if the NEW_USER already exists
    if id "$NEW_USER" &>/dev/null; then
        echo "User $NEW_USER already exists. Skipping user creation."
        return
    fi

    # Ask for the user's password
    read -sp "Enter the password: " PASSWORD
    echo

    # Add the new user with /bin/bash as the default shell
    useradd -m -s /bin/bash $NEW_USER

    # Check if the user was created successfully
    if [ $? -eq 0 ]; then
        echo "User $NEW_USER created successfully."
        # Set the user's PASSWORD
        echo "$NEW_USER:$PASSWORD" | chpasswd
        # Add the user to the sudo group
        usermod -aG sudo $NEW_USER
    else
        echo "Failed to create user."
    fi


    # Create SSH directory for the new user
    mkdir -p /home/$NEW_USER/.ssh
    chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    chmod 700 /home/$NEW_USER/.ssh

    # Optionally, copy the authorized_keys from root to the new user
    if [ -f "/root/.ssh/authorized_keys" ]; then
        cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/
        chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/authorized_keys
        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
    fi
}

# Function to install s3cmd and configure it for DigitalOcean Spaces
install_and_configure_s3cmd() {
    echo "Installing s3cmd for DigitalOcean Spaces management..."

    # Install s3cmd
    sudo apt-get update
    sudo apt-get install -y s3cmd

    # Configuration details
    read -p "Enter your DigitalOcean Spaces Access Key: " DO_SPACES_ACCESS_KEY
    read -p "Enter your DigitalOcean Spaces Secret Key: " DO_SPACES_SECRET_KEY
    read -p "Enter your DigitalOcean Space Name: " DO_SPACE_NAME
    read -p "Enter your DigitalOcean Endpoint URL (e.g., nyc3.digitaloceanspaces.com): " DO_ENDPOINT_URL

    # Create the configuration file
    s3cmd --access_key=$DO_SPACES_ACCESS_KEY \
          --secret_key=$DO_SPACES_SECRET_KEY \
          --host=$DO_ENDPOINT_URL \
          --host-bucket="%(bucket)s.$DO_ENDPOINT_URL" \
          --bucket-location=us-east-1 \
          --no-encrypt \
	      --multipart-chunk-size-mb=1024 \
	      --dump-config 2>&1

    echo "s3cmd has been installed and configured."
}


# Function to set up SSH for GitHub
setup_ssh_for_github() {
    echo "Setting up SSH for GitHub..."

    # Prompt for the user's email address
    read -p "Enter your email address for the SSH key: " user_email

    # Define the SSH key path
    SSH_KEY="$HOME/.ssh/github_rsa"

    # Check if the SSH key already exists
    if [ -f "$SSH_KEY" ]; then
        echo "SSH key already exists at $SSH_KEY. Skipping key generation."
    else
        # Generate an SSH key for GitHub without a passphrase
        echo -e "\n" | ssh-keygen -t rsa -b 4096 -C "$user_email" -f $SSH_KEY
    fi

    # Start the ssh-agent in the background
    #eval "$(ssh-agent -s)"

    # Add SSH key to the ssh-agent
    #ssh-add ~/.ssh/github_rsa

    # Configure SSH to use the key for GitHub
    SSH_CONFIG="$HOME/.ssh/config"

    if ! grep -q "Host github.com" "$SSH_CONFIG"; then
        echo "Host github.com" >> "$SSH_CONFIG"
        echo "  IdentityFile $SSH_KEY" >> "$SSH_CONFIG"
        echo "  IdentitiesOnly yes" >> "$SSH_CONFIG"
        echo "SSH configuration for GitHub added to $SSH_CONFIG."
    else
        echo "GitHub configuration already exists in $SSH_CONFIG."
    fi

    # Output the public key and instruct the user to add it to GitHub
    echo "go to https://github.com/settings/ssh/new and copy the following SSH public key to add it to your GitHub account:"

    cat "${SSH_KEY}.pub"
    echo ""
}

# Function to install required dependencies
install_dependencies() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx git gnupg curl

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # Restart services
    sudo systemctl restart nginx
    sudo systemctl restart mongod

    # Ask for an additional IP address to bind MongoDB
    read -p "Enter an additional IP address to bind MongoDB (optional): " additional_ip
    if [ ! -z "$additional_ip" ]; then
        sudo sed -i "/^  bindIp:/ s/$/, $additional_ip/" /etc/mongod.conf
        sudo systemctl restart mongod
    fi

    # Ask if user wants to bind the server IP address
    read -p "Do you want to bind the server's IP address to MongoDB? [Y/n] " bind_server_ip
    if [[ $bind_server_ip =~ ^[Yy]$ ]]
    then
        # Get the primary IP address of the server
        server_ip=$(hostname -I | awk '{print $1}')

        if [ ! -z "$server_ip" ]; then
            echo "Binding server IP address ($server_ip) to MongoDB configuration..."
            sudo sed -i "/^  bindIp:/ s/$/, $server_ip/" /etc/mongod.conf
            sudo systemctl restart mongod
        else
            echo "Failed to retrieve server IP address."
        fi
    fi

    # Install Node.js and PM2
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    source ~/.bashrc
    nvm install --lts
    npm install pm2@latest -g
}


# Function to clone repositories and set up directories
clone_repositories() {
    mkdir -p ${PROJECT_PATH}/{backend,frontend,server-configs,backups}
    git clone git@github.com:JantuDeb/studypath-api-v2.git ${PROJECT_PATH}/backend
    git clone git@github.com:JantuDeb/studypath-api-admin.git ${PROJECT_PATH}/frontend
    git clone git@github.com:JantuDeb/server-configs.git ${PROJECT_PATH}/server-configs
}


# Function to copy configurations from server-config repo and create backups
copy_configurations() {
    NEW_ROOT_PATH=${PROJECT_PATH}/frontend/studypath-admin-v2/build
    # Prompt user for the virtual host configuration file name
    read -p "Please enter the virtual host configuration file name (e.g., domainname.com): " VIRTUAL_HOST

    # Backup original configuration files
    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    sudo cp /etc/mongod.conf /etc/mongod.conf.bak

    # Backup and replace specific Nginx virtual host configuration
    if [ -f "/etc/nginx/sites-available/$VIRTUAL_HOST" ]; then
        sudo cp /etc/nginx/sites-available/$VIRTUAL_HOST /etc/nginx/sites-available/$VIRTUAL_HOST.bak
    fi

    sudo cp ${PROJECT_PATH}/server-configs/api-server-configs/api_server.conf /etc/nginx/conf.d/
    sudo cp ${PROJECT_PATH}/server-configs/api-server-configs/$VIRTUAL_HOST /etc/nginx/sites-available/

     # Prompt user to enter a new server name
    read -p "Please enter the new server name for the Nginx configuration (e.g., example.com): " NEW_SERVER_NAME

    # Update the server_name in the Nginx configuration
    sudo sed -i "s/server_name .*;/server_name $NEW_SERVER_NAME;/" /etc/nginx/sites-available/$VIRTUAL_HOST
    # Update the root in the Nginx configuration
    sudo sed -i "s|root .*;|root $NEW_ROOT_PATH;|" /etc/nginx/sites-available/$VIRTUAL_HOST

    sudo sed -i "s|if (\$host = v2.thestudypath.com)|if (\$host = $NEW_SERVER_NAME)|" /etc/nginx/sites-available/$VIRTUAL_HOST

    if [ -L "/etc/nginx/sites-enabled/$VIRTUAL_HOST" ]; then
    	sudo rm /etc/nginx/sites-enabled/$VIRTUAL_HOST
    fi
    
    # sudo cp ${PROJECT_PATH}/server-configs/api-server-configs/mongod.conf /etc/
    sudo ln -s /etc/nginx/sites-available/$VIRTUAL_HOST /etc/nginx/sites-enabled/

    # Reload Nginx to apply new configurations
    #sudo nginx -t && sudo systemctl reload nginx
}

# Function to sync data from DigitalOcean Spaces to the local backups directory
sync_do_spaces_to_backups() {
    echo "Syncing data from DigitalOcean Spaces..."

    # Prompt for the DigitalOcean Spaces path
    read -p "Enter the path of backup in your DigitalOcean Space (e.g., mongo-database-backups/v2/): " DO_SPACES_PATH

    # Define the local backup directory
    local_backup_dir="${PROJECT_PATH}/backups"

    # Perform the sync operation
    s3cmd sync s3://${DO_SPACES_PATH} ${local_backup_dir}/

    echo "Sync operation completed."
}


# Function to configure the firewall
configure_firewall() {
    echo "Configuring UFW Firewall..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow OpenSSH
    sudo ufw allow 'Nginx Full'
    sudo ufw enable
}

# Function to install and configure SSL
install_ssl() {
    sudo apt install -y certbot python3-certbot-nginx
    # The following command requires manual domain input
    sudo certbot --nginx
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
}

# Function to restore the database
restore_database() {
    read -p "Enter MongoDB database name: " db_name
    read -p "Enter MongoDB username: " db_user
    read -p "Enter MongoDB password: " db_pass
    read -p "Enter the backup file name to restore: " backup_file
    BACKUP_PATH="${PROJECT_PATH}/backups/$backup_file"

    if [ ! -f "$BACKUP_PATH" ]; then
        echo "Backup file $BACKUP_PATH does not exist. Exiting."
        exit 1
    fi

    mongorestore --uri "mongodb://$db_user:$db_pass@localhost:27017/$db_name" --gzip --archive=$BACKUP_PATH
}

# Function to build and run the application
build_and_run_app() {
    cd ${PROJECT_PATH}/frontend && npm install && npm run build
    cd ${PROJECT_PATH}/backend && npm install
    pm2 start app.js
    pm2 save
    pm2 startup
}

# Function to continue script execution as sudo user
continue_as_sudo_user() {
    # Check if the user exists
    if id "$USER" &>/dev/null; then
        echo "Continuing as user $USER..."
    else
        echo "User $USER does not exist. Please create a user first."
        exit 1
    fi

    install_dependencies
    clone_repositories
    copy_configurations
    restore_database
    build_and_run_app
    configure_firewall
    install_ssl

    echo "Setup completed successfully."
}



main() {
    # Check if the script is executed with sudo by a non-root user
    if [ -n "$SUDO_USER" ]; then
        continue_as_sudo_user
    elif [ "$(id -u)" -eq 0 ]; then
        create_sudo_user
    else
        echo "Please run this script as root or with 'sudo'."
        exit 1
    fi
}

# Execute main function
main
