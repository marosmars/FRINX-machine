#!/bin/bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
cd ${DIR}

# Common functions
script="startup.sh"

function example {
    echo -e "example: $script"
}

function usage {
 echo -e "usage: $script [OPTION]  \n"
}

function help {
  usage
    echo -e "OPTION:"
    echo -e "  -s | --skip      Skips health check."
    echo -e "\n"
  example
}

function check_success {
  if [[ $? -ne 0 ]]
  then
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  printf "${RED}System is not healthy. Shutting down.\n${NC}"
  echo "Removing containers."
  ./teardown.sh
  exit
fi
}

function start_container {
  sudo docker-compose up -d --scale "$1"=$2 "$1"
}

function start_containers {
local containers_to_start=("dynomite" "elasticsearch" "logstash" "conductor-server" "odl" "sample-topology" "uniconfig-ui" "kibana" "micros")

# In case scale is >1 for a service, make sure to remove its container_name parameter from docker-compose.yml ... A service to be scaled by docker, cannot have a static container name
declare -A containers_scale=( ["micros"]="1")

for i in "${containers_to_start[@]}"; do

scale="${containers_scale[`echo "$i"`]}"
if [ -z "$scale" ]
then
  scale="1"
fi
start_container $i $scale
scale=""

if [ "$skip" = false ]; then
  ./health_check.sh $i
  check_success $?
fi
echo "################"
done

}

function import_workflows {
sudo docker exec frinx-machine_micros_1 bash -c "cd /home/app && newman run netinfra_utils/postman.json --folder 'TASKS' -e netinfra_utils/postman_environment.json"
if [ "$skip" = false ]; then
  check_success $?
fi

sudo docker exec frinx-machine_micros_1 bash -c "cd /home/app && newman run netinfra_utils/postman.json --folder 'SETUP' -e netinfra_utils/postman_environment.json"
if [ "$skip" = false ]; then
  check_success $?
fi

}

function import_devices {
sudo docker exec frinx-machine_micros_1 bash -c "cd /home/app && newman run netinfra_utils/devices/device_import.postman_collection.json -d netinfra_utils/devices/device_data.csv"
if [ "$skip" = false ]; then
  check_success $?
fi

}


# Loop arguments
skip=false
import=false
while [ "$1" != "" ];
do
case $1 in
    -s | --skip)
    skip=true
    shift
    ;;
    -h | --help )
    help
    exit
    ;;
    *)    # unknown option
    echo "$script: illegal option $1"
    exit 1 #error
    ;;
esac
done

# Clean up docker
sudo docker system prune -f


# Starts containers
start_containers

# Imports workflows
import_workflows

# Import devices
import_devices

echo 'Startup finished!'
