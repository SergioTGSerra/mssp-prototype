#!/bin/bash

cd "$(dirname "$0")"
podman-compose -f compose.yaml up -d