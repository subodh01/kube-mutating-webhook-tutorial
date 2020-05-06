#!/bin/bash

set -e

usage() {
    cat <<EOF
Generate certificate suitable for use with an sidecar-injector webhook service.

This script generates a self signed certificate for use with webhook server.

The webhook server's key/cert are stored in a k8s secret.

usage: ${0} [OPTIONS]

The following flags are required.

       --service          Service name of webhook.
       --namespace        Namespace where webhook service and secret reside.
       --secret           Secret name for CA certificate and server certificate/key pair.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case ${1} in
        --service)
            service="$2"
            shift
            ;;
        --secret)
            secret="$2"
            shift
            ;;
        --namespace)
            namespace="$2"
            shift
            ;;
        *)
            usage
            ;;
    esac
    shift
done

[ -z ${service} ] && service=sidecar-injector-webhook-svc
[ -z ${secret} ] && secret=sidecar-injector-webhook-certs
[ -z ${namespace} ] && namespace=sidecar-injector

if [ ! -x "$(command -v cfssl)" ]; then
    echo "cfssl not found"
    exit 1
fi

tmpdir=CERTS
mkdir -p ${tmpdir}

echo "creating certs in ${tmpdir} "

cat > ${tmpdir}/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "k8s-webhook": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ${tmpdir}/ca-csr.json <<EOF
{
  "CN": "k8s-webhook",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "San Jose",
      "O": "K8S-Webhook",
      "OU": "CA",
      "ST": "California"
    }
  ]
}
EOF

# Generate CA certs
cfssl gencert -initca ${tmpdir}/ca-csr.json | cfssljson -bare ${tmpdir}/ca

cat > ${tmpdir}/webhook-csr.json <<EOF
{
  "CN": "webhook-service",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "San Jose",
      "O": "Webhook-service",
      "OU": "CA",
      "ST": "California"
    }
  ]
}
EOF

# Generates webhook server certs
cfssl gencert -ca=${tmpdir}/ca.pem -ca-key=${tmpdir}/ca-key.pem -config=${tmpdir}/ca-config.json \
	-hostname=${service},${service}.${namespace},${service}.${namespace}.svc \
	-profile=k8s-webhook ${tmpdir}/webhook-csr.json | cfssljson -bare ${tmpdir}/webhook-server

# create the secret with CA cert and server cert/key
kubectl create secret generic ${secret} \
        --from-file=key.pem=${tmpdir}/webhook-server-key.pem \
        --from-file=cert.pem=${tmpdir}/webhook-server.pem \
        --dry-run -o yaml |
    kubectl -n ${namespace} apply -f -
