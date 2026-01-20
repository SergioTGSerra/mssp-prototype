#!/bin/bash

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
