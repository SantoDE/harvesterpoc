#!/usr/bin/env bash
# Sets up Submariner cross-cluster connectivity between OVH and rke2-test.
#
# Prerequisites:
#   - subctl installed at ~/.local/bin/subctl
#   - OVH kubeconfig at ~/Downloads/kubeconfig-ovh.yml
#   - rke2-test kubeconfig at ~/Downloads/rke2-testnew.yaml
#   - Gateway node labeled on OVH (done once manually):
#       kubectl label node test-pool-small-node-d22ca7 submariner.io/gateway=true
#       kubectl annotate node test-pool-small-node-d22ca7 submariner.io/preferred-server=true
#
# Usage:
#   ./scripts/setup-submariner.sh

set -euo pipefail

SUBCTL="${HOME}/.local/bin/subctl"
OVH_KUBECONFIG="${HOME}/Downloads/kubeconfig-ovh.yml"
RKE2_KUBECONFIG="${HOME}/Downloads/rke2-testnew.yaml"
BROKER_INFO="broker-info.subm"

echo "==> Deploying broker on OVH and exporting broker-info..."
KUBECONFIG="$OVH_KUBECONFIG" "$SUBCTL" deploy-broker

echo "==> Joining OVH cluster to broker..."
KUBECONFIG="$OVH_KUBECONFIG" "$SUBCTL" join "$BROKER_INFO" \
  --clusterid ovh-test \
  --natt=false

echo "==> Joining rke2-test cluster to broker..."
KUBECONFIG="$RKE2_KUBECONFIG" "$SUBCTL" join "$BROKER_INFO" \
  --clusterid rke2-test \
  --natt=true

echo "==> Waiting 10s for gateways to connect..."
sleep 10

echo "==> Connections:"
KUBECONFIG="$OVH_KUBECONFIG" "$SUBCTL" show connections
