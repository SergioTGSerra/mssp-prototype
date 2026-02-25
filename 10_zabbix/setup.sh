#!/bin/bash
source utils.sh; script_init;

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml up -d
