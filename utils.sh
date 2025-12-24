#!/bin/bash

# Function to load environment variables from .env file
load_env() {
    local env_file="${1:-.env}"
    if [ -f "$env_file" ]; then
        echo "Loading environment variables from $env_file..."
        # Export each line that is not a comment or empty
        export $(grep -v '^#' "$env_file" | xargs)
    else
        echo "Warning: $env_file not found."
    fi
}

# Function to update or create environment variables in .env file
update_or_create_env() {
    local key="$1"
    local value="$2"
    local env_file="${3:-.env}"

    if [ ! -f "$env_file" ]; then
        touch "$env_file"
    fi

    if grep -q "^${key}=" "$env_file"; then
        # Update existing key
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        # Append new key
        echo "${key}=${value}" >> "$env_file"
    fi
}
