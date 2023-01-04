#!/bin/bash

GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
END='\033[0m'
BLOCK='\033[1;37m'

# highlight the next step
success() { log "${GRN}$1${END}"; }
info() { log "${BLU}$@${END}"; }
warn() { log "${YEL}$1${END}"; }

# output a "log" line with bold leading >>>
log() { >&2 printf "${BLOCK}>>>${END} $1\n"; }

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
    info "Cockroach cluster is already running, stoping before starting in console/backup mode..."
    stop_crdb_nodes
  fi
}

function copy_backup_from_host_to_node() {
  read -p $'\033[1;37m>>>\033[0m \033[1;33m'"⚠️  Do you want to copy the content from ./backup to roach-0 ? [y/n] > "$'\033[0m' -r -n 1 choice
  case "$choice" in
    y|Y )
      echo $'\n'
      echo "Copying backup from host to node..."
      tar -xvf ./backup/extern.zip -C ./backup/
      docker cp ./backup roach-0:/cockroach/cockroach-data/extern
      echo $'\n'
      success "Backup copied to node"
      cat <<EOF
Cheatsheet:
  Show databases:
    SHOW DATABASES;
  Show backups:
    SHOW BACKUPS IN 'nodelocal://0/backup';
    SHOW BACKUP FROM latest IN 'nodelocal://0/backup';
  Restore backup:
    - latest backup:
    RESTORE DATABASE backup_database_name FROM LATEST in 'nodelocal://0/backup';
    - specific backup:
    RESTORE DATABASE backup_database_name FROM '/2021/12/14-190909.83' in 'nodelocal://0/backup';
  Make backup:
    BACKUP DATABASE database_name INTO 'nodelocal://0/backup' AS OF SYSTEM TIME '-10s';
EOF
      echo $'\n'
      return 0
      ;;
    n|N )
      echo $'\n'
      echo "Skipping..."
      return 0
      ;;
    * )
      echo $'\n'
      echo "Invalid Choice. Type y or n."
      copy_backup_from_host_to_node # restart process on invalid choice
      ;;
  esac
}


# Checking if the CDRB certs volume exists. If not, the cluster in not initialized:
function is_initialized() {
  [[ $(docker volume ls -f name=certs --format "{{.Name}}") =~ crdb-cluster_certs ]]
}

eval clear

if is_initialized && [[ $1 == "sql" ]]	; then
  stop_crdb_nodes_if_running
  if [[ $2 == "backup" ]] ; then
    info "Starting CRDB cluster and opening a console in backup/restore mode..."
    copy_backup_from_host_to_node
    # in backup mode, mount the backup folder to the docker roach-0 container.
    # if we want to restore a backup, we can open a shell in the docker roach-0 container to copy the backup from backup/ to cockroach-data/extern/backup
    docker compose -f docker-compose.yml -f docker-compose.backup.yml up --no-start
    start_crdb_nodes
    # Open SQL console to backup OR restore, then remove container
    docker compose -f docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  else
    info "Starting CRDB cluster and opening a console..."
    docker compose -f docker-compose.yml up --no-start
    start_crdb_nodes
    docker compose -f docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  fi

elif is_initialized; then
    success "Cluster already initialized, starting CRDB cluster..."
    docker compose -f docker-compose.yml up --no-start
    start_crdb_nodes
else
    info "Certificate volume not found, initializing cockroach..."
    docker compose -f docker-compose.yml -f docker-compose.init.yml up --no-start
    # Generate certificates :
    docker compose -p crdb-cluster start roach-cert
    sleep 3 # Wait for certificates to be generated

    # Start cockroach :
    start_crdb_nodes

    # Initializing cockroach cluster :
    docker compose -p crdb-cluster start roach-init

    success "✅ Cockroach cluster initialized"
    info "🗑  Cleaning up..."
    docker compose -p crdb-cluster stop roach-cert
    sleep 5 # Wait for roch-init to finish before cleaning up
    docker container prune -f
    success "Done 🎉"
fi
