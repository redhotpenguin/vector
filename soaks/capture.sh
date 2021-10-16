#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

display_usage() {
	echo -e "\nUsage: \$0 PROM_ADDR SAMPLES\n"
}

if [  $# -le 0 ]
then
    display_usage
    exit 1
fi

PROM_ADDR="${1:-}"
TOTAL_SAMPLES="${2:-}"
# PROFILE=$(echo "${SOAK_NAME}" | sed 's/_/-/g')

BASELINE_INGRESS_QUERY="sum(rate(bytes_written{kubernetes_namespace=\"vector-baseline\"}\[1m\]))"
BASELINE_EGRESS_QUERY="sum(rate(bytes_received{kubernetes_namespace=\"vector-comparison\"}\[1m\]))"

sample_idx=0
echo -e "SAMPLE-IDX\tSAMPLE"
while [ $sample_idx -ne $TOTAL_SAMPLES ]
do
    SAMPLE=$(curl --silent http://${PROM_ADDR}/api/v1/query\?query\="sum(rate((bytes_written\[1m\])))" | jq '.data.result[0].value[1]' | sed 's/"//g')
    echo -e "${sample_idx}\t${SAMPLE}"
    sleep 1
    sample_idx=$(($sample_idx+1))
done
