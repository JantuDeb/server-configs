#!/bin/bash

# Global variable for SSH key path
SSH_KEY_PATH="/home"

# Function to create a new sudo user
create_sudo_user() {
    read -p "Enter the new sudo username: " NEW_USER
    read -s -p "Enter a password for the new user: " PASSWORD
    echo

    SSH_KEY="$SSH_KEY_PATH/$NEW_USER/.ssh/id_rsa"
    PROJECT_PATH="/home/$NEW_USER"

    echo "Creating a new user: $NEW_USER"
    adduser --disabled-password --gecos "" $NEW_USER
    echo "$NEW_USER:$PASSWORD" | chpasswd
    usermod -aG sudo $NEW_USER

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
    s3cmd --configure \
          --access_key=$DO_SPACES_ACCESS_KEY \
          --secret_key=$DO_SPACES_SECRET_KEY \
          --host=$DO_ENDPOINT_URL \
          --host-bucket="%(bucket)s.$DO_ENDPOINT_URL" \
          --bucket-location=us-east-1 \
          --no-encrypt \
          --signature-v2 \
          --guess-mime-type \
          --no-check-certificate \
          --save --config=~/.s3cfg

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
    eval "$(ssh-agent -s)"

    # Add SSH key to the ssh-agent
    ssh-add $SSH_KEY

    # Output the public key and instruct the user to add it to GitHub
    echo "go to https://github.com/settings/ssh/new and copy the following SSH public key to add it to your GitHub account:"

    cat "${SSH_KEY}.pub"
    echo ""
}

# Function to install required dependencies
install_dependencies() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx mongodb git

    # Install NVM (Node Version Manager)
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

    # Source NVM script to use it in the current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Install the latest LTS version of Node.js
    nvm install --lts

    # Install PM2
    npm install pm2@latest -g
}


# Function to clone repositories and set up directories
clone_repositories() {
    mkdir -p ${PROJECT_PATH}/{backend,frontend,server-configs,backups}
    git clone git@github.com:JantuDeb/studypath-api-v2.git ${PROJECT_PATH}/backend
    git clone git@github.com:JantuDeb/studypath-api-admin.git ${PROJECT_PATH}/frontend
    git clone git@github.com:username/repo-for-server-configs.git ${PROJECT_PATH}/server-configs
}


# Function to copy configurations from server-config repo and create backups
copy_configurations() {
    echo "Please enter the virtual host configuration file name (e.g., domainname.com):"
    read VIRTUAL_HOST

    # Backup original configuration files
    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    sudo cp /etc/mongod.conf /etc/mongod.conf.bak

    # Backup and replace specific Nginx virtual host configuration
    if [ -f "/etc/nginx/sites-available/$VIRTUAL_HOST" ]; then
        sudo cp /etc/nginx/sites-available/$VIRTUAL_HOST /etc/nginx/sites-available/$VIRTUAL_HOST.bak
    fi
    sudo cp ${PROJECT_PATH}/server-config/nginx.conf /etc/nginx/
    sudo cp ${PROJECT_PATH}/server-config/sites-available/$VIRTUAL_HOST /etc/nginx/sites-available/
    sudo cp ${PROJECT_PATH}/server-config/mongo.conf /etc/mongod.conf
    # ... other configurations ...
}

# Function to sync data from DigitalOcean Spaces to the local backups directory
sync_do_spaces_to_backups() {
    echo "Syncing data from DigitalOcean Spaces..."

    # Prompt for the DigitalOcean Spaces path
    read -p "Enter the path in your DigitalOcean Space (e.g., spacename/path/): " do_space_path

    # Define the local backup directory
    local_backup_dir="${PROJECT_PATH}/backups"

    # Perform the sync operation
    s3cmd sync s3://${do_space_path} ${local_backup_dir}/

    echo "Sync operation completed."
}


# Function to configure the firewall
configure_firewall() {
    echo "Configuring UFW Firewall..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow OpenSSH
    sudo ufw allow 'Nginx Full'
    sudo ufw --force enable
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

# Main function to coordinate the setup
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi

    create_sudo_user
    su - $NEW_USER -c "install_dependencies"
    su - $NEW_USER -c "clone_repositories"
    su - $NEW_USER -c "copy_configurations"
    su - $NEW_USER -c "restore_database"
    su - $NEW_USER -c "build_and_run_app"
    configure_firewall
    install_ssl

    echo "Setup completed successfully."
}

# Execute main function
main
