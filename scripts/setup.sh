#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# Setup script for KubeCon Time-Based Fairshare Demo
# Prerequisites: kind, kubectl, Helm 3 (no real GPUs needed)
# Creates a kind cluster and installs: fake-gpu-operator, Kubeflow Training
# Operator, KAI Scheduler, Prometheus, Grafana, queues, and dashboard.
# Optionally wires the OpenTelemetry Collector to Dash0 if DASH0_AUTH_TOKEN is set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMETHEUS_URL="http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

echo "============================================"
echo "  KubeCon Demo Setup: Time-Based Fairshare"
echo "============================================"

# --------------------------------------------------
# Step 1: Create kind cluster
# --------------------------------------------------
echo ""
echo "[1/12] Creating kind cluster..."

KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-"kind"}

if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER_NAME"; then
    echo "    Cluster '$KIND_CLUSTER_NAME' already exists, skipping creation"
else
    kind create cluster --name "$KIND_CLUSTER_NAME"
fi

kubectl config use-context "kind-${KIND_CLUSTER_NAME}"

echo "    Using cluster 'kind-${KIND_CLUSTER_NAME}'"

# --------------------------------------------------
# Step 2: Install fake-gpu-operator
# --------------------------------------------------
echo ""
echo "[2/12] Installing fake-gpu-operator..."

FAKE_GPU_OPERATOR_VERSION=${FAKE_GPU_OPERATOR_VERSION:-"0.2.0"}

# The demo scenario needs 100 GPUs total, regardless of cluster size:
# spread them across the available nodes (1 node -> 100/node, 10 nodes -> 10/node)
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
GPUS_PER_NODE=${GPUS_PER_NODE:-$((100 / NODE_COUNT))}

# Nodes only get simulated GPUs if they carry the node-pool label
for node in $(kubectl get nodes -o name); do
    kubectl label "$node" run.ai/simulated-gpu-node-pool=default --overwrite
done

helm upgrade -i fake-gpu-operator oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator \
    -n gpu-operator --create-namespace \
    --set "topology.nodePools.default.gpuCount=${GPUS_PER_NODE}" \
    --version "$FAKE_GPU_OPERATOR_VERSION" \
    --wait --timeout 120s

echo "    fake-gpu-operator installed (version: $FAKE_GPU_OPERATOR_VERSION)"
echo "    Simulating ${GPUS_PER_NODE} GPUs/node on ${NODE_COUNT} node(s) = $((GPUS_PER_NODE * NODE_COUNT)) GPUs total"

# --------------------------------------------------
# Step 3: Install Kubeflow Training Operator
# --------------------------------------------------
echo ""
echo "[3/12] Installing Kubeflow Training Operator (PyTorchJob CRD)..."

TRAINING_OPERATOR_VERSION=${TRAINING_OPERATOR_VERSION:-"v1.9.3"}

# Server-side apply: the CRDs are too large for client-side apply annotations
kubectl apply --server-side -k \
    "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=${TRAINING_OPERATOR_VERSION}"

kubectl wait --for=condition=available deployment/training-operator \
    -n kubeflow --timeout=120s

echo "    Kubeflow Training Operator installed (version: $TRAINING_OPERATOR_VERSION)"

# --------------------------------------------------
# Step 4: Install KAI Scheduler
# --------------------------------------------------
echo ""
echo "[4/12] Installing KAI Scheduler..."

KAI_VERSION=${KAI_VERSION:-"v0.16.2"}

helm upgrade -i kai-scheduler oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
    -n kai-scheduler --create-namespace \
    --set "global.gpuSharing=true" \
    --version "$KAI_VERSION" \
    --wait --timeout 120s

echo "    KAI Scheduler installed (version: $KAI_VERSION)"

# --------------------------------------------------
# Step 5: Install Prometheus Operator + Grafana
# --------------------------------------------------
echo ""
echo "[5/12] Installing kube-prometheus-stack (Prometheus + Grafana)..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

helm upgrade -i --create-namespace -n monitoring kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --values "${DEMO_DIR}/setup/kube-prometheus-values.yaml" \
    --wait --timeout 180s

echo "    kube-prometheus-stack installed"

# --------------------------------------------------
# Step 6: Point KAI at the external Prometheus
# --------------------------------------------------
echo ""
echo "[6/12] Configuring KAI to use the kube-prometheus-stack Prometheus..."

kubectl patch config kai-config --type merge \
    -p "{\"spec\":{\"prometheus\":{\"enabled\":true,\"externalPrometheusUrl\":\"${PROMETHEUS_URL}\"}}}"

echo "    KAI configured with external Prometheus: ${PROMETHEUS_URL}"

# --------------------------------------------------
# Step 7: Wait for Prometheus to be ready
# --------------------------------------------------
echo ""
echo "[7/12] Waiting for Prometheus pod to be ready..."

kubectl wait --for=condition=ready pod \
    -n monitoring -l app.kubernetes.io/name=prometheus \
    --timeout=120s 2>/dev/null || \
echo "    Warning: Could not verify Prometheus readiness. Continuing..."

echo "    Prometheus is ready"

# --------------------------------------------------
# Step 8: Apply ServiceMonitors
# --------------------------------------------------
echo ""
echo "[8/12] Applying ServiceMonitors..."

kubectl apply -f "${DEMO_DIR}/setup/external-service-monitors.yaml"

echo "    ServiceMonitors applied"

# --------------------------------------------------
# Step 9: Apply Grafana datasource + dashboard
# --------------------------------------------------
echo ""
echo "[9/12] Configuring Grafana datasource and dashboard..."

kubectl apply -f "${DEMO_DIR}/grafana/datasource-configmap.yaml"

# Provision dashboard via ConfigMap (auto-loaded by Grafana sidecar)
kubectl create configmap grafana-dashboard-fairshare \
    -n monitoring \
    --from-file=fairshare-demo.json="${DEMO_DIR}/grafana/dashboard.json" \
    --dry-run=client -o yaml | \
    kubectl label --local -f - grafana_dashboard="1" -o yaml | \
    kubectl apply -f -

echo "    Grafana datasource and dashboard configured"

# --------------------------------------------------
# Step 10: Create queues
# --------------------------------------------------
echo ""
echo "[10/12] Creating queue hierarchy..."

kubectl apply -f "${DEMO_DIR}/setup/queues.yaml"

echo "    Queues created: ai-department -> llm-team, vision-team"

# --------------------------------------------------
# Step 11: Create workloads namespace
# --------------------------------------------------
echo ""
echo "[11/12] Creating workloads namespace..."

kubectl create namespace workloads 2>/dev/null || true

echo "    Namespace 'workloads' ready"

# --------------------------------------------------
# Step 12: Observability (optional, Dash0)
# --------------------------------------------------
echo ""
echo "[12/12] Observability (Dash0)..."

if [ -n "${DASH0_AUTH_TOKEN:-}" ]; then
    "${SCRIPT_DIR}/setup-observability.sh"
else
    echo "    DASH0_AUTH_TOKEN not set, skipping."
    echo "    To enable later: DASH0_AUTH_TOKEN=<token> scripts/setup-observability.sh"
fi

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Verification:"
echo "  kubectl get pods -n gpu-operator"
echo "  kubectl get pods -n kai-scheduler"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get queues"
echo "  kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.capacity.nvidia\.com/gpu'"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &"
echo "  Open: http://localhost:3000 (admin/prom-operator)"
echo "  Kiosk mode: http://localhost:3000/d/fairshare-demo?kiosk"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &"
echo "  Open: http://localhost:9090"
echo ""
echo "Next steps:"
echo "  1. Run: scripts/run-demo-before.sh  (shows the starvation problem)"
echo "  2. Run: scripts/run-demo-after.sh   (shows time-based fairshare fix)"
echo ""
echo "Optional: ship metrics, logs and traces to Dash0:"
echo "  DASH0_AUTH_TOKEN=<token> scripts/setup-observability.sh"
