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

# Copy env directory
echo "Copying env directory..."
if [ -d "$PARENT_DIR/env" ]; then
    cp -r "$PARENT_DIR/env" "$DESTINATION/" || error_exit "Failed to copy env directory to $DESTINATION."
    echo "env directory copied successfully to $DESTINATION."
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
    if ! podman exec "${NAME}-postgres" pg_restore -U postgres -d netbox < "$RESTORE_FILE"; then
        error_exit "Database restore failed"
    fi
    echo "Database restored successfully"
fi
