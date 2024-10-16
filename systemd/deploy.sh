#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Default name
NAME="netbox"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift ;;
        *) error_exit "Unknown parameter: $1" ;;
    esac
    shift
done

# Set DESTINATION based on whether the user is root or not
if [ "$(id -u)" -eq 0 ]; then
    DESTINATION="/etc/containers/systemd"
else
    DESTINATION="${HOME}/.config/containers/systemd"
fi

# Check if the destination directory exists
if [ ! -d "$DESTINATION" ]; then
    error_exit "Destination directory $DESTINATION does not exist."
fi

# Check if the pod already exists
if podman pod exists "$NAME"; then
    error_exit "Pod $NAME already exists. Please configure it manually, or remove all configuration and restart the deployment procedure."
fi

# Create a pod with the specified name
podman pod create --name "$NAME" || error_exit "Failed to create pod '$NAME'"

echo "Pod '$NAME' created successfully. Configuration will be stored in $DESTINATION."

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
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
