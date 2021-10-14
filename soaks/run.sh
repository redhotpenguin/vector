#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

display_usage() {
	echo -e "\nUsage: \$0 SOAK_NAME SHA\n"
}

if [  $# -le 1 ]
then
    display_usage
    exit 1
fi

SOAK_NAME="${1:-}"
# PROFILE=$(echo "${SOAK_NAME}" | sed 's/_/-/g')

minikube stop || true
minikube delete || true
minikube start --cpus=10 --memory=32g
