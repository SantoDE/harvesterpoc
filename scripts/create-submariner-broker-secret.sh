#!/usr/bin/env bash
# Creates submariner-broker-secret in the submariner-operator namespace.
# Run this once after the submariner-k8s-broker Fleet bundle deploys.
#
# Usage: KUBECONFIG=<path> ./scripts/create-submariner-broker-secret.sh [context]
# Default context: rke2-test

set -euo pipefail

CONTEXT="${1:-rke2-test}"
BROKER_NS="submariner-k8s-broker"
OPERATOR_NS="submariner-operator"
SECRET_NAME="submariner-broker-secret"
BROKER_SERVER="https://rancher.51.38.122.163.sslip.io/k8s/clusters/c-m-ftdl6btr"

kube() { kubectl --context "$CONTEXT" "$@"; }

echo "Extracting broker credentials from ${BROKER_NS}..."
TOKEN=$(kube get secret submariner-k8s-broker-client-token -n "$BROKER_NS" \
  -o jsonpath='{.data.token}' | base64 -d)
CA=$(kube get secret submariner-k8s-broker-client-token -n "$BROKER_NS" \
  -o jsonpath='{.data.ca\.crt}')

echo "Generating IPsec PSK..."
PSK=$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | base64 | tr -d '\n')

echo "Creating namespace ${OPERATOR_NS} (if needed)..."
kube create namespace "$OPERATOR_NS" 2>/dev/null || true

echo "Creating/replacing ${SECRET_NAME} in ${OPERATOR_NS}..."
kube delete secret "$SECRET_NAME" -n "$OPERATOR_NS" 2>/dev/null || true
kube create secret generic "$SECRET_NAME" \
  -n "$OPERATOR_NS" \
  --from-literal=values.yaml="broker:
  server: ${BROKER_SERVER}
  token: ${TOKEN}
  ca: ${CA}
  insecure: true
ipsec:
  psk: \"${PSK}\""

echo "Done. Secret ${SECRET_NAME} created in ${OPERATOR_NS}."
