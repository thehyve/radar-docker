#!/bin/bash
# Check whether services are healthy. If not, restart them and notify the maintainer.

. ./util.sh
. ./.env

unhealthy=()

# get all human-readable service names
# see last line of loop
while read service; do
    # check if a container was started for the service
    container=$(sudo-linux docker-compose ps -q $service)
    if [ -z "${container}" ]; then
        # no container means no running service
        continue
    fi
    health=$(sudo-linux docker inspect --format '{{.State.Health.Status}}' $container 2>/dev/null || echo "null")
    if [ "$health" = "unhealthy" ]; then
        echo "Service $service is unhealthy. Restarting."
        unhealthy+=("${service}")
        sudo-linux docker-compose restart ${service}
    fi
done <<< "$(sudo-linux docker-compose config --services)"

if [ "${#unhealthy[@]}" -eq 0 ]; then
    echo "All services are healthy"
else
    echo "$unhealthy services were unhealthy and have been restarted."

    # Send notification to MAINTAINER
    # start up the mail container if not already started
    sudo-linux docker-compose up -d smtp
    # save the container, so that we can use exec to send an email later
    container=$(sudo-linux docker-compose ps -q smtp)
    SAVEIFS=$IFS
    IFS=, 
    display_services="[${unhealthy[*]}]"
    IFS=$SAVEIFS
    display_host="${SERVER_NAME} ($(hostname -f), $(curl -s http://ipecho.net/plain))"
    body="Services on $display_host are unhealthy. Services $display_services have been restarted. Please log in for further information."
    echo "Sent notification to $MAINTAINER_EMAIL"
    echo "$body" | sudo-linux docker exec -i ${container} mail -aFrom:$FROM_EMAIL "-s[RADAR] Services on ${SERVER_NAME} unhealthy" $MAINTAINER_EMAIL
    exit 1
fi