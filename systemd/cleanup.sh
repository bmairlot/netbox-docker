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

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift ;;
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

# Execute commands
systemctl $SUSER stop "${NAME}"-netbox
systemctl $SUSER stop "${NAME}"-redis-cache
systemctl $SUSER stop "${NAME}"-redis
systemctl $SUSER stop "${NAME}"-postgres
systemctl $SUSER stop "${NAME}"-pod
systemctl $SUSER stop "${NAME}"-network

podman pod rm "${NAME}"
podman network rm -f "${NAME}"

echo Removing all quadlet file from systemd
rm -rf "${DESTINATION}/$NAME-*"

# Execute commands
execute_command "Reloading quadlet files" "systemctl $SUSER daemon-reload"

