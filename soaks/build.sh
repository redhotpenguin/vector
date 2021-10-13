#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

# We need to build two copies of vector with the same flags, one for the
# baseline SHA and the other for current. Baseline is either 'master' or
# whatever the user sets.

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
trap cleanup EXIT
cleanup() {
    git switch "${CURRENT_BRANCH}"
}

display_usage() {
	echo -e "\nUsage: \$0 SOAK_NAME BASELINE_SHA COMPARISON_SHA\n"
}

build_vector() {
    TARGET="target/release/vector"
    IMAGE="vector:${1}-${FEATURE_SHA}"
    pushd ../
    git checkout "$1"
    podman build --ignorefile "${__dir}/Dockerfile.ignore" --file "${__dir}/Dockerfile" --build-arg=VECTOR_FEATURES="${FEATURES}" --tag "${IMAGE}" .
    popd
}

if [  $# -le 1 ]
then
    display_usage
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
SOAK_NAME="${1:-}"
BASELINE="${2:-}"
COMPARISON="${3:-}"

SOAK_DIR="${__dir}/${SOAK_NAME}"
. "${SOAK_DIR}/FEATURES"
FEATURE_SHA=$(echo -n "${FEATURES}" | sha256sum - | head -c40)

pushd "${__dir}"
build_vector "${BASELINE}"
build_vector "${COMPARISON}"
popd
