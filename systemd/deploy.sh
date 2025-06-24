#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to execute command and handle errors
execute_command() {
   local description="$1"
   local command="$2"

   echo "$description"
   if ! $command; then
       echo "Error: Command '$command' failed with exit code $?"
       exit 1
   fi
}

# Function to generate a random password
generate_password() {
    local length="${1:-16}"
    # Generate a random password using /dev/urandom
    # Using alphanumeric characters only to avoid shell escaping issues
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# Function to update password in env files
update_env_password() {
    local file="$1"
    local var_name="$2"
    local new_password="$3"

    if [ -f "$file" ]; then
        # Use sed to replace the password value
        sed -i "s/^${var_name}=.*/${var_name}=${new_password}/" "$file"
        echo "Updated ${var_name} in $(basename "$file")"
    else
        error_exit "File $file not found"
    fi
}

# Default name
NAME="netbox"
RESTORE_FILE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift ;;
        --restore) RESTORE_FILE="$2"; shift ;;
        *) error_exit "Unknown parameter: $1" ;;
    esac
    shift
done

SUSER=""
# Set DESTINATION based on whether the user is root or not
if [ "$(id -u)" -eq 0 ]; then
    DESTINATION="/etc/containers/systemd"
else
    DESTINATION="${HOME}/.config/containers/systemd"
    SUSER="--user"
fi

# Check if the destination directory exists
if [ ! -d "$DESTINATION" ]; then
    mkdir -p "$DESTINATION" || error_exit "Failed to create directory $DESTINATION"
fi

# Check if the pod already exists
if podman pod exists "$NAME"; then
    error_exit "Pod $NAME already exists. Please configure it manually, or remove all configuration and restart the deployment procedure."
fi

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# Get the netbox-docker main directory
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Copy .pod, .volume, .container, and .network files to the destination
echo "Copying quadlet files to $DESTINATION..."
if ! cp "$SCRIPT_DIR"/*.{pod,volume,container,network} "$DESTINATION" 2>/dev/null; then
    if [ $? -ne 1 ]; then
        error_exit "Failed to copy quadlet files to $DESTINATION."
    fi
    echo "No quadlet files found in $SCRIPT_DIR."
else
    echo "Quadlet files copied successfully from $SCRIPT_DIR to $DESTINATION."
fi

# Copy env directory with password generation if needed
echo "Copying env directory..."
if [ -d "$PARENT_DIR/env" ]; then
    # Check if env directory already exists at destination
    if [ -d "$DESTINATION/env" ]; then
        echo "env directory already exists at $DESTINATION. Skipping password generation."
    else
        # Copy env directory
        cp -r "$PARENT_DIR/env" "$DESTINATION/" || error_exit "Failed to copy env directory to $DESTINATION."
        echo "env directory copied successfully to $DESTINATION."

        # Generate random passwords
        echo "Generating random passwords for new installation..."

        # Generate PostgreSQL password
        POSTGRES_PASS=$(generate_password 20)
        echo "Generated new PostgreSQL password"

        # Generate Redis passwords
        REDIS_PASS=$(generate_password 20)
        REDIS_CACHE_PASS=$(generate_password 20)
        echo "Generated new Redis passwords"

        # Update PostgreSQL password in both files
        update_env_password "$DESTINATION/env/postgres.env" "POSTGRES_PASSWORD" "$POSTGRES_PASS"
        update_env_password "$DESTINATION/env/netbox.env" "DB_PASSWORD" "$POSTGRES_PASS"

        # Update Redis password
        update_env_password "$DESTINATION/env/redis.env" "REDIS_PASSWORD" "$REDIS_PASS"
        update_env_password "$DESTINATION/env/netbox.env" "REDIS_PASSWORD" "$REDIS_PASS"

        # Update Redis cache password
        update_env_password "$DESTINATION/env/redis-cache.env" "REDIS_PASSWORD" "$REDIS_CACHE_PASS"
        update_env_password "$DESTINATION/env/netbox.env" "REDIS_CACHE_PASSWORD" "$REDIS_CACHE_PASS"

        # Also generate a new SECRET_KEY for Django
        SECRET_KEY=$(generate_password 50)
        update_env_password "$DESTINATION/env/netbox.env" "SECRET_KEY" "'$SECRET_KEY'"
        echo "Generated new Django SECRET_KEY"

        echo "Password generation complete. Passwords have been securely randomized."
    fi
else
    echo "env directory not found in $PARENT_DIR."
fi

# Copy and rename configuration directory
echo "Copying and renaming configuration directory..."
if [ -d "$PARENT_DIR/configuration" ]; then
    cp -r "$PARENT_DIR/configuration" "$DESTINATION/$NAME-configuration" || error_exit "Failed to copy configuration directory to $DESTINATION/$NAME-configuration."
    echo "configuration directory copied successfully to $DESTINATION/$NAME-configuration."
else
    echo "configuration directory not found in $PARENT_DIR."
fi


# Execute commands
execute_command "Reloading quadlet files" "systemctl $SUSER daemon-reload"
execute_command "Starting $NAME network..." "systemctl $SUSER start ${NAME}-network"
execute_command "Starting $NAME pod..." "systemctl $SUSER start ${NAME}-pod"
# Starting volumes
execute_command "Starting $NAME postgresql data..." "systemctl $SUSER start ${NAME}-postgres-data-volume"
execute_command "Starting $NAME redis cache data..." "systemctl $SUSER start ${NAME}-redis-cache-data-volume"
execute_command "Starting $NAME redis data..." "systemctl $SUSER start ${NAME}-redis-data-volume"
execute_command "Starting $NAME configuration volume..." "systemctl $SUSER start ${NAME}-configuration-volume"
execute_command "Starting $NAME reports volume." "systemctl $SUSER start ${NAME}-reports-files-volume"
execute_command "Starting $NAME scripts volume..." "systemctl $SUSER start ${NAME}-scripts-files-volume"
execute_command "Starting $NAME media files volume..." "systemctl $SUSER start ${NAME}-media-files-volume"

#Starting containers
execute_command "Starting $NAME postgresql container..." "systemctl $SUSER start ${NAME}-postgres"
# Checking if backup are required
# Add after the postgresql container start:
if [ -n "$RESTORE_FILE" ]; then
    if [ ! -f "$RESTORE_FILE" ]; then
        error_exit "Restore file $RESTORE_FILE does not exist"
    fi
    echo "Restoring database from $RESTORE_FILE..."
    sleep 5  # Wait for PostgreSQL to be ready
    if ! cat $RESTORE_FILE|  podman exec -i "${NAME}-postgres" psql -U netbox netbox; then
        error_exit "Database restore failed"
    fi
    echo "Database restored successfully"
fi
execute_command "Starting $NAME redis container..." "systemctl $SUSER start ${NAME}-redis"
execute_command "Starting $NAME redis-cache container..." "systemctl $SUSER start ${NAME}-redis-cache"
execute_command "Starting $NAME netbox container..." "systemctl $SUSER start ${NAME}-netbox"
execute_command "Starting $NAME netbox container..." "systemctl $SUSER start ${NAME}-housekeeping"
execute_command "Starting $NAME netbox container..." "systemctl $SUSER start ${NAME}-worker"
