#!/bin/bash

WORK_DIR=./crdb-cluster/

if [[ "$(ls -a ./certs)" ]] && [[ $1 == "sql" ]]	; then
  if [[ $2 == "backup" ]] ; then
    echo "lauching cockroach and open a console in backup mode..."
    # in backup mode, mount the backup folder to the docker roach-0 container.
    # if we want to restore a backup, we can open a shell in the docker roach-0 container to copy the backup from backup/ to cockroach-data/extern/backup
    docker compose -f ${WORK_DIR}/docker-compose.yml -f ${WORK_DIR}/docker-compose.backup.yml up --no-start
    docker compose start roach-0

    sleep 5

    docker compose start roach-1
    docker compose start roach-2
    docker compose start lb

    sleep 5

    # Open SQL console to backup OR restore, then remove container
    docker compose -f ${WORK_DIR}/docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  else
    echo "lauching cockroach and open a console..."
    docker compose -f ${WORK_DIR}/docker-compose.yml up --no-start
    docker compose start roach-0

    sleep 5

    docker compose start roach-1
    docker compose start roach-2
    docker compose start lb

    sleep 5

    docker compose -f ${WORK_DIR}/docker-compose.shell.yml run -it --rm --entrypoint='./cockroach sql' roach-shell
  fi

elif [[ "$(ls -a ./certs)" ]]; then
    echo "Certificates found, lauching cockroach..."
    docker compose -f ${WORK_DIR}/docker-compose.yml up --no-start
    docker compose start roach-0

    sleep 5

    docker compose start roach-1
    docker compose start roach-2
    docker compose start lb
else
    echo "Certificates not found, initialise cockroach..."
    docker compose -f ${WORK_DIR}/docker-compose.yml -f ${WORK_DIR}/docker-compose.init.yml up --no-start
    # Generate certificates :
    docker compose start roach-cert

    sleep 20 # Wait for certificates to be generated

    docker compose start roach-0

    sleep 5

    docker compose start roach-1
    docker compose start roach-2
    docker compose start lb

    sleep 10 # Wait for cockroach to be ready

    # Initialise cockroach cluster :
    docker compose start roach-init

    sleep 10

    # Retrieve certificates :
    docker cp roach-cert:/.cockroach-certs/ca.crt ./certs/
    docker cp roach-cert:/.cockroach-certs/client.root.crt ./certs/
    docker cp roach-cert:/.cockroach-certs/client.root.key ./certs/
    docker cp roach-cert:/.cockroach-certs/client.root.key.pk8 ./certs/
fi
