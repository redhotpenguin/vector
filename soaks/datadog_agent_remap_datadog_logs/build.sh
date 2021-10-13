#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASELINE="${1:-}"
COMPARISON="${2:-}"
FEATURES="sources-internal_metrics,sinks-prometheus,sources-datadog,sinks-datadog,transforms-remap"
FEATURE_SHA=$(echo -n "${FEATURES}" | sha256sum - | head -c40)

pushd "${__dir}"

# We need to build two copies of vector with the same flags, one for the
# baseline SHA and the other for current. Baseline is either 'master' or
# whatever the user sets.

cleanup() {
    git switch "${CURRENT_BRANCH}"
}

display_usage() {
	echo -e "\nUsage: \$0 BASELINE_SHA COMPARISON_SHA\n"
}
# if less than two arguments supplied, display usage
if [  $# -le 1 ]
then
    display_usage
    exit 1
fi

build_vector() {
    TARGET="target/release/vector"
    IMAGE="vector:${1}-${FEATURE_SHA}"
    pushd ../../
    git checkout "$1"
    podman build --file "${__dir}/Dockerfile" --build-arg=VECTOR_FEATURES="${FEATURES}" --tag "${IMAGE}" .
    popd
}

trap cleanup EXIT
build_vector "${BASELINE}"
build_vector "${COMPARISON}"

popd
