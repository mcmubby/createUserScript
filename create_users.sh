#!/bin/bash

# FLogger
log_with_timestamp() {
    local message=$1
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp : $message" | tee -a "$log_file"
}

# Root permission check
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Log files
log_file="/var/log/user_management.log"
password_file="/var/secure/user_passwords.csv"

# Directories and files check
log_dir=$(dirname "$log_file")
if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    log_with_timestamp "Created log directory: $log_dir"
fi

if [ ! -f "$log_file" ]; then
    touch "$log_file"
    log_with_timestamp "Created log file: $log_file"
fi

secure_dir=$(dirname "$password_file")
if [ ! -d "$secure_dir" ]; then
    mkdir -p "$secure_dir"
    log_with_timestamp "Created secure directory: $secure_dir"
fi

if [ ! -f "$password_file" ]; then
    touch "$password_file"
    chmod 600 "$password_file"
    log_with_timestamp "Created password file: $password_file with restricted permissions."
fi

# Parameter check - a text file name is required
if [ $# -eq 0 ]; then
    log_with_timestamp "Error: No file name provided. Please provide a text file as an argument."
    exit 1
fi

# File check - ensure file name parsed is actually a file
file="$1"
if ! [ -f "$file" ]; then
    log_with_timestamp "Error: $file is not a valid file."
    exit 1
fi

# Generate a random password
generate_password() {
    openssl rand -base64 12
}

# Create user
create_user() {
    local username=$1
    local group_array=("${@:2}")

    log_with_timestamp "Creating user '$username'..."

    # Check if user already exists
    if id "$username" &>/dev/null; then
        log_with_timestamp "User '$username' already exists. Skipping creation."
        return
    fi

    # Create user
    useradd -m "$username" -s /bin/bash
    log_with_timestamp "User '$username' created."

    # Generate a random password
    password=$(generate_password)
    
    # Set password for the user
    echo "$username:$password" | chpasswd
    log_with_timestamp "Password for user '$username' set."
    
    # Log password to secure file
    echo "$username,$password" >> "$password_file"
    log_with_timestamp "Generated password for '$username' stored securely in '$password_file'."

    # Add user to additional groups
    for group in "${group_array[@]}"; do
        # Check if group already exists
        if grep -q "^$group:" /etc/group; then
            usermod -aG "$group" "$username"
            log_with_timestamp "User '$username' added to existing group '$group'."
        else
            groupadd "$group"
            usermod -aG "$group" "$username"
            log_with_timestamp "Group '$group' created and user '$username' added."
        fi
    done

    # Set ownership of user's home directory
    chown -R "$username:$username" "/home/$username"
    chmod 700 "/home/$username"
    log_with_timestamp "Home directory permissions set for user '$username'."
}

# Read the file content and process each line
log_with_timestamp "Reading file: $file"
while IFS= read -r line; do
    
    # Skip lines starting with a comment (#) or empty lines
    [[ "$line" = \#* || -z "$line" ]] && continue

    log_with_timestamp "Processing line: $line"
    
    # Remove leading and trailing whitespaces
    line=$(echo "$line" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')

    # Split the line into user and groups
    IFS=';' read -r username groups <<< "$line"
    
    # Trim whitespaces from username and groups
    username=$(echo "$username" | tr -d '[:space:]')
    groups=$(echo "$groups" | tr -d '[:space:]')

    # Split groups by comma into an array
    IFS=',' read -ra group_array <<< "$groups"

    # Log the parsed username and groups
    log_with_timestamp "Parsed username: '$username', groups: '${group_array[*]}'"

    # Call function to create user and groups
    create_user "$username" "${group_array[@]}"

done < "$file"

