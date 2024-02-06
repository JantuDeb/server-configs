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

    if [ -f "$HOME/.s3cfg" ]; then
        echo "s3cmd is already configured."
        return
    fi
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
	      --dump-config 2>&1 | tee .s3cfg

    echo "s3cmd has been installed and configured."
}


# Function to set up SSH for GitHub
setup_ssh_for_github() {
    echo "Setting up SSH for GitHub..."

    # Prompt for the user's email address

    # Define the SSH key path
    SSH_KEY="$HOME/.ssh/github_rsa"

    # Check if the SSH key already exists
    if [ -f "$SSH_KEY" ]; then
        echo "SSH key already exists at $SSH_KEY. Skipping key generation."
    else
        read -p "Enter your email address for the SSH key: " user_email     
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

    # Pause the script and wait for the user to type 'continue'
    read -p "Type 'continue' to proceed with the remaining setup: " input
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]') # Convert input to lowercase

    if [ "$input" != "continue" ]; then
        echo "Exiting script. Please run again and type 'continue' when prompted."
        exit 1
    fi
}


# Function to install required dependencies
install_dependencies() {
    sudo apt update && sudo apt upgrade -y

    # Check and Install Nginx
    if nginx -v > /dev/null 2>&1; then
        read -p "Nginx is already installed. Do you want to reinstall it? [Y/n] " reinstall_nginx
        if [[ $reinstall_nginx =~ ^[Yy]$ ]]; then
            sudo apt-get install --reinstall nginx
        fi
    else
        sudo apt install -y nginx
    fi

    # Check and Install GnuPG
    if gpg --version > /dev/null 2>&1; then
        read -p "GnuPG is already installed. Do you want to reinstall it? [Y/n] " reinstall_gnupg
        if [[ $reinstall_gnupg =~ ^[Yy]$ ]]; then
            sudo apt-get install --reinstall gnupg
        fi
    else
        sudo apt install -y gnupg
    fi

    # MongoDB Installation
    if mongod --version > /dev/null 2>&1; then
        read -p "MongoDB is already installed. Do you want to reinstall it? [Y/n] " reinstall_mongodb
        if [[ $reinstall_mongodb =~ ^[Yy]$ ]]; then
            sudo apt-get install --reinstall mongodb-org
        fi
    else
        # Proceed with MongoDB installation commands
        curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
        sudo apt-get update
        sudo apt-get install -y mongodb-org
    fi


    # MongoDB Configuration
    configure_mongodb

    # Check and Install NVM and Node.js
    install_nvm_and_node

    # Check and install pm2
    instal_pm2
}

configure_mongodb() {
    read -p "Do you want to configure MongoDB? [Y/n] " configure_mongo
    if [[ $configure_mongo =~ ^[Yy]$ ]]; then
        MONGO_CONFIG_FILE=/etc/mongod.conf
        # Ask for an additional IP address to bind MongoDB
        read -p "Enter an additional IP address to bind MongoDB (optional): " additional_ip
        if [ ! -z "$additional_ip" ]; then
            sudo sed -i "/^  bindIp:/ s/$/, $additional_ip/" $MONGO_CONFIG_FILE
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
                sudo sed -i "/^  bindIp:/ s/$/, $server_ip/" $MONGO_CONFIG_FILE
                sudo systemctl restart mongod
            else
                echo "Failed to retrieve server IP address."
            fi
        fi
    else
        echo "MongoDB configuration skipped."
    fi
}

install_nvm_and_node() {
  # Check and Install NVM
    if [ -d "$HOME/.nvm" ]; then
        read -p "NVM is already installed. Do you want to reinstall it? [Y/n] " reinstall_nvm
        if [[ $reinstall_nvm =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.nvm"
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
        fi
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    fi

    source "$HOME/.nvm/nvm.sh"
    # Check and Install Node.js
    if nvm ls > /dev/null 2>&1; then
        read -p "Node.js is already installed. Do you want to reinstall it? [Y/n] " reinstall_node
        if [[ $reinstall_node =~ ^[Yy]$ ]]; then
            nvm install --lts --reinstall-packages-from=current
        fi
    else
        nvm install --lts
    fi

}

instal_pm2(){
    if pm2 -v > /dev/null 2>&1; then
        read -p "PM2 is already installed. Do you want to reinstall it? [Y/n] " reinstall_pm2
        if [[ $reinstall_pm2 =~ ^[Yy]$ ]]; then
            npm install pm2@latest -g
        fi
    else
        npm install pm2@latest -g
    fi
}

create_mongo_admin_user() {
    mongosh <<EOF
    use admin
    db.createUser({
    user: "$ADMIN_USER",
    pwd: "$ADMIN_PWD",
    roles: [ { role: "readWriteAnyDatabase", db: "admin" }, { role: "userAdminAnyDatabase", db: "admin" },{ role: 'dbAdminAnyDatabase', db: 'admin' } ]
    })
EOF
}

# Function to create a new database user
create_new_user() {
    mongosh --authenticationDatabase "admin" -u "$ADMIN_USER" -p "$ADMIN_PWD" <<EOF
    use $NEW_DB
    db.createUser({
    user: "$NEW_USER",
    pwd: "$NEW_PWD",
    roles: [{ role: "dbAdmin", db: "$NEW_DB" }, { role: "readWrite", db: "$NEW_DB" }, { role: "userAdmin", db: "$NEW_DB" }]
    })
EOF
}

# Function to enable authentication in MongoDB configuration
enable_authentication() {
# Check if 'security' line is commented out and uncomment it
    sudo sed -i '/^#security:/s/^#//' /etc/mongod.conf
# Check if 'authorization: enabled' is present; if not, add it under 'security'
    if ! grep -q 'authorization: enabled' /etc/mongod.conf; then
        sudo sed -i '/^security:/a\  authorization: enabled' /etc/mongod.conf
    fi
# Restart MongoDB to apply changes
    sudo systemctl restart mongod
}


# Function to restore database from backup archive
restore_from_backup() {
    mongorestore --uri="mongodb://$NEW_USER:$NEW_PWD@localhost:27017/$NEW_DB" --nsInclude="*" --archive="$BACKUP_PATH" --gzip
}

setup_mongodb(){
    echo "Enter MongoDB Admin User Credentials"
    read -p "Admin Username: " ADMIN_USER
    while true; do
        read -sp "Admin Password: " ADMIN_PWD
        echo
        read -sp "Confirm Admin Password: " ADMIN_PWD_CONFIRM
        echo
        [ "$ADMIN_PWD" = "$ADMIN_PWD_CONFIRM" ] && break
        echo "Passwords do not match. Please try again."
    done

    echo "Checking if MongoDB authentication is already enabled..."
    AUTH_ENABLED=$(awk '/^security:/{flag=1;next}/^$/{flag=0}flag && /authorization: *enabled/{print "yes"; exit}' /etc/mongod.conf)
    if [ "$AUTH_ENABLED" != "yes" ]; then
    	AUTH_ENABLED="no"
    fi

    if [ "$AUTH_ENABLED" = "no" ]; then
        echo "MongoDB authentication is not enabled. Setting up admin user..."
        create_mongo_admin_user
        enable_authentication
        sudo systemctl restart mongod
        sleep 5  # Wait for MongoDB to restart
    else
        echo "MongoDB authentication is already enabled. Using provided admin credentials."
    fi

    # echo "MongoDB setup and restore complete."
    while true; do
        # Enter New Database and User Credentials
        read -p "New Database Name: " NEW_DB
        read -p "New Username: " NEW_USER

        while true; do
            read -sp "New Password: " NEW_PWD
            echo
            read -sp "Confirm New Password: " NEW_PWD_CONFIRM
            echo
            [ "$NEW_PWD" = "$NEW_PWD_CONFIRM" ] && break
            echo "Passwords do not match. Please try again."
        done

        BACKUP_PATH=""

        while [ ! -f "$BACKUP_PATH" ]; do
            read -p "Enter the backup file name (it should be in /home/user/backups/) to restore: " backup_file_path
            BACKUP_PATH="$PROJECT_PATH/backups/$backup_file_path"

            if [ ! -f "$BACKUP_PATH" ]; then
                echo "Backup file $BACKUP_PATH does not exist. Please try again."
            fi
        done

        create_new_user
        restore_from_backup

        # Ask if the user wants to restore another database
        read -p "Do you want to restore another database? (yes/no): " answer
        case $answer in
            [Yy]* ) continue;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

    echo "All operations completed."
    echo "MongoDB setup and restore complete."
}


# Function to clone repositories and set up directories
clone_repositories() {
    mkdir -p ${PROJECT_PATH}/{backend,frontend,server-configs,backups}
    git clone git@github.com:JantuDeb/studypath-api-v2.git ${PROJECT_PATH}/backend/studypath-api-v2
    git clone git@github.com:JantuDeb/studypath-api.git ${PROJECT_PATH}/backend/studypath-api
    git clone git@github.com:JantuDeb/studypath-admin-v2.git ${PROJECT_PATH}/frontend/studypath-admin-v2
    git clone git@github.com:JantuDeb/studypath-api-admin.git ${PROJECT_PATH}/frontend/studypath-admin
    git clone git@github.com:JantuDeb/server-configs.git ${PROJECT_PATH}/server-configs
}


# Function to copy configurations from server-config repo and create backups
copy_configurations() {
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
    sudo cp ${PROJECT_PATH}/server-configs/api-server-configs/example.com.conf /etc/nginx/sites-available/$VIRTUAL_HOST

     # Prompt user to enter a new server name
    read -p "Please enter the new server name for the Nginx configuration (e.g., example.com): " NEW_SERVER_NAME

    NEW_ROOT_PATH=/var/www/$NEW_SERVER_NAME
    # Update the server_name in the Nginx configuration
    sudo sed -i "s/server_name .*;/server_name $NEW_SERVER_NAME;/" /etc/nginx/sites-available/$VIRTUAL_HOST
    sudo sed -i "s/example\.com/$NEW_SERVER_NAME/g" /etc/nginx/sites-available/$VIRTUAL_HOST
    # Update the root in the Nginx configuration
    sudo sed -i "s|root .*;|root $NEW_ROOT_PATH;|" /etc/nginx/sites-available/$VIRTUAL_HOST

    if [ -L "/etc/nginx/sites-enabled/$VIRTUAL_HOST" ]; then
    	sudo rm /etc/nginx/sites-enabled/$VIRTUAL_HOST
    fi
    
    # sudo cp ${PROJECT_PATH}/server-configs/api-server-configs/mongod.conf /etc/

    # Reload Nginx to apply new configurations
    sudo nginx -t && sudo systemctl reload nginx
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
    sudo ufw allow 27017
    sudo ufw enable
}

# Function to install and configure SSL
install_ssl() {
    # Ask user if they want to install SSL
    read -p "Do you want to install SSL (You can do manual install and editing virtualhost config) ? (y/n): " install_ssl_answer

    # Check if the user's answer is 'y' or 'Y'
    if [[ $install_ssl_answer == [Yy] ]]; then
        # Install Certbot and its Nginx plugin
        sudo apt install -y certbot python3-certbot-nginx
        # Install the certificate without modifying Nginx configuration
        sudo certbot certonly --nginx -d "$NEW_SERVER_NAME"
        sudo service nginx restart
	sleep 5
 	sudo ln -s /etc/nginx/sites-available/$VIRTUAL_HOST /etc/nginx/sites-enabled/
    else
        echo "SSL installation skipped."
    fi
}



# Function to build and run the application
build_and_run_app() {
    cd ${PROJECT_PATH}/frontend/studypath-admin-v2 && npm install && npm run build
    cd ${PROJECT_PATH}/backend/studypath-api-v2 && npm install
    sudo cp ${PROJECT_PATH}/frontend/studypath-admin-v2/dist/ ${NEW_ROOT_PATH}/
    pm2 start index.js
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
    install_and_configure_s3cmd
    setup_ssh_for_github
    install_dependencies
    clone_repositories
    copy_configurations
    # sync_do_spaces_to_backups
    configure_firewall
    setup_mongodb
    build_and_run_app
    install_ssl

    echo "Setup completed successfully."
}



main() {
    if [ `whoami` != 'root' ];then
	    if sudo -l &> /dev/null; then
                continue_as_sudo_user
        else
                echo "Please run this script as root to create a new sudo user or a user with sudo prev."
        fi
    else
	    create_sudo_user
    fi
}

# Execute main function
main



