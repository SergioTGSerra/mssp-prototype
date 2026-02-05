#!/bin/bash

# Load env
set -a; source .env; set +a

podman-compose -f $PWD/guacamole/compose.yaml up -d
