#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

tmpdir=CERTS

export CA_BUNDLE=$(cat ${tmpdir}/ca.pem | base64 -w0)

if command -v envsubst >/dev/null 2>&1; then
    envsubst
else
    sed -e "s|\${CA_BUNDLE}|${CA_BUNDLE}|g"
fi
