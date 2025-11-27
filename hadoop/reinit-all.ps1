#!/bin/bash
# Stop and remove all containers, networks, and volumes
docker-compose down -v

# Start the containers in detached mode
docker-compose up -d
