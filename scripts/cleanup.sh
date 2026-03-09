#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# Cleans up all demo workloads while keeping infrastructure intact

set -euo pipefail

NAMESPACE=${NAMESPACE:-workloads}

echo "Cleaning up demo workloads..."

echo "  Deleting all PyTorchJobs in namespace '$NAMESPACE'..."
kubectl delete pytorchjobs -n "$NAMESPACE" --all 2>/dev/null || true

echo "  Deleting all Jobs in namespace '$NAMESPACE'..."
kubectl delete jobs -n "$NAMESPACE" --all 2>/dev/null || true

echo "  Deleting all pods in namespace '$NAMESPACE'..."
kubectl delete pods -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true

echo "  Deleting all PodGroups in namespace '$NAMESPACE'..."
kubectl delete podgroups -n "$NAMESPACE" --all 2>/dev/null || true

echo "  Waiting for pods to terminate..."
kubectl wait --for=delete pod --all -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

echo ""
echo "Cleanup complete. Infrastructure (KAI, Prometheus, Grafana) is still running."
echo "Run run-demo-before.sh or run-demo-after.sh to start a new demo."
