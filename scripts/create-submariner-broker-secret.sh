#!/usr/bin/env bash
# Creates submariner-broker-secret in the submariner-operator namespace.
# All cluster-specific values go in the secret since Fleet's targets[].values
# are not merged into valuesFrom — only the secret content reaches Helm.
#
# Usage:
#   ./scripts/create-submariner-broker-secret.sh ovh
#   ./scripts/create-submariner-broker-secret.sh rke2
#
# PSK is generated once and must be THE SAME on all clusters — pass it via env:
#   PSK=<shared-psk> ./scripts/create-submariner-broker-secret.sh rke2

set -euo pipefail

CLUSTER="${1:-}"
if [[ -z "$CLUSTER" ]]; then
  echo "Usage: $0 <ovh|rke2>"
  exit 1
fi

BROKER_NS="submariner-k8s-broker"
OPERATOR_NS="submariner-operator"
SECRET_NAME="submariner-broker-secret"

case "$CLUSTER" in
  ovh)
    KUBECONFIG="${KUBECONFIG:-/home/manuelz/Downloads/kubeconfig-ovh.yml}"
    BROKER_SERVER="kubernetes.default.svc"
    CLUSTER_ID="ovh-test"
    CLUSTER_CIDR="10.2.0.0/16"
    SERVICE_CIDR="10.3.0.0/16"
    NAT_ENABLED="false"
    EXTRA_ARGS="--insecure-skip-tls-verify"
    ;;
  rke2)
    KUBECONFIG="${KUBECONFIG:-/home/manuelz/Downloads/rke2-testnew.yaml}"
    BROKER_SERVER="tszdbs.c1.de1.k8s.ovh.net"
    CLUSTER_ID="rke2-test"
    CLUSTER_CIDR="10.42.0.0/16"
    SERVICE_CIDR="10.43.0.0/16"
    NAT_ENABLED="true"
    EXTRA_ARGS="--insecure-skip-tls-verify"
    ;;
  *)
    echo "Unknown cluster: $CLUSTER (expected ovh or rke2)"
    exit 1
    ;;
esac

export KUBECONFIG
kube() { kubectl $EXTRA_ARGS "$@"; }

echo "[$CLUSTER] Extracting broker credentials from OVH (${BROKER_NS})..."
# Broker always lives on OVH — extract from there regardless of target cluster
BROKER_KUBECONFIG="/home/manuelz/Downloads/kubeconfig-ovh.yml"
TOKEN=$(kubectl --kubeconfig "$BROKER_KUBECONFIG" --insecure-skip-tls-verify \
  get secret submariner-k8s-broker-client-token -n "$BROKER_NS" \
  -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl --kubeconfig "$BROKER_KUBECONFIG" --insecure-skip-tls-verify \
  get secret submariner-k8s-broker-client-token -n "$BROKER_NS" \
  -o jsonpath='{.data.ca\.crt}')

if [[ -z "${PSK:-}" ]]; then
  echo "[$CLUSTER] Generating IPsec PSK..."
  PSK=$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | base64 | tr -d '\n')
  echo "[$CLUSTER] PSK: ${PSK}"
  echo "[$CLUSTER] NOTE: use PSK=${PSK} when creating the secret on the other cluster!"
fi

echo "[$CLUSTER] Creating namespace ${OPERATOR_NS} (if needed)..."
kube create namespace "$OPERATOR_NS" 2>/dev/null || true

echo "[$CLUSTER] Creating/replacing ${SECRET_NAME} in ${OPERATOR_NS}..."
kube delete secret "$SECRET_NAME" -n "$OPERATOR_NS" 2>/dev/null || true
kube create secret generic "$SECRET_NAME" \
  -n "$OPERATOR_NS" \
  --from-literal=values.yaml="broker:
  server: ${BROKER_SERVER}
  token: ${TOKEN}
  ca: ${CA}
  namespace: submariner-k8s-broker
  insecure: true
ipsec:
  psk: \"${PSK}\"
submariner:
  clusterId: ${CLUSTER_ID}
  clusterCidr: ${CLUSTER_CIDR}
  serviceCidr: ${SERVICE_CIDR}
  natEnabled: ${NAT_ENABLED}
  cableDriver: libreswan"

echo "[$CLUSTER] Done."
