#!/bin/bash

# Change working directory :
cd crdb-cluster/ > /dev/null

function start_crdb_nodes() {
  docker compose start roach-0
  docker compose start roach-1 roach-2 lb
}

function stop_crdb_nodes() {
  docker compose -p crdb-cluster down --remove-orphans
}

function stop_crdb_nodes_if_running() {
  regex="(lb)|(roach*)"
  if [[ $(docker ps -f status=running --format "{{.Names}}") =~ $regex ]] ; then
    echo "Cockroach cluster is already running, stoping before starting in console/backup mode..."
    stop_crdb_nodes
  fi
}

# Checking if the CDRB certs volume exists. If not, the cluster in not initialized:
function is_initialized() {
  [[ $(docker volume ls -f name=certs --format "{{.Name}}") =~ crdb-cluster_certs ]]
}

if is_initialized && [[ $1 == "sql" ]]	; then
  stop_crdb_nodes_if_running
  if [[ $2 == "backup" ]] ; then
    echo "Starting CRDB cluster and open a console in backup/restore mode..."
    # in backup mode, mount the backup folder to the docker roach-0 container.
    # if we want to restore a backup, we can open a shell in the docker roach-0 container to copy the backup from backup/ to cockroach-data/extern/backup
    docker compose -f docker-compose.yml -f docker-compose.backup.yml up --no-start
    start_crdb_nodes
    # Open SQL console to backup OR restore, then remove container
    docker compose -f docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  else
    echo "Starting CRDB cluster and open a console..."
    docker compose -f docker-compose.yml up --no-start
    start_crdb_nodes
    docker compose -f docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  fi

elif is_initialized; then
    echo "Cluster already initialized, starting CRDB cluster..."
    docker compose -f docker-compose.yml up --no-start
    start_crdb_nodes
else
    echo "Certificate volume not found, initializing cockroach..."
    docker compose -f docker-compose.yml -f docker-compose.init.yml up --no-start
    # Generate certificates :
    docker compose start roach-cert
    sleep 3 # Wait for certificates to be generated

    # Start cockroach :
    start_crdb_nodes

    # Initializing cockroach cluster :
    docker compose start roach-init

    # echo "Cockroach cluster initialized, certificates generated and copied to ./certs/ \n"
    echo "✅ Cockroach cluster initialized"
    echo "🗑 Cleaning up..."
    docker compose stop roach-cert
    sleep 5 # Wait for roch-init to finish before cleaning up
    docker container prune -f
    echo "Done 🎉"
fi
