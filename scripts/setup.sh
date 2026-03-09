#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# Setup script for KubeCon Time-Based Fairshare Demo
# Prerequisites: existing K8s cluster with fake-gpu-operator already installed
# Installs: KAI Scheduler, Prometheus, Grafana, queues, and dashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DEMO_DIR}/../.." && pwd)"

echo "============================================"
echo "  KubeCon Demo Setup: Time-Based Fairshare"
echo "============================================"

# --------------------------------------------------
# Step 1: Install KAI Scheduler
# --------------------------------------------------
echo ""
echo "[1/8] Installing KAI Scheduler..."

KAI_VERSION=${KAI_VERSION:-""}
if [ -z "$KAI_VERSION" ]; then
    # Auto-detect version from main branch
    KAI_VERSION="0.0.0-$(git -C "${REPO_ROOT}" rev-parse --short origin/main 2>/dev/null || echo 'latest')"
fi

helm upgrade -i kai-scheduler oci://ghcr.io/nvidia/kai-scheduler/kai-scheduler \
    -n kai-scheduler --create-namespace \
    --set "global.gpuSharing=true" \
    --version "$KAI_VERSION" \
    --wait --timeout 120s

echo "    KAI Scheduler installed (version: $KAI_VERSION)"

# --------------------------------------------------
# Step 2: Install Prometheus Operator + Grafana
# --------------------------------------------------
echo ""
echo "[2/8] Installing kube-prometheus-stack (Prometheus + Grafana)..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

helm upgrade -i --create-namespace -n monitoring kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --values "${REPO_ROOT}/docs/metrics/kube-prometheus-values.yaml" \
    --wait --timeout 180s

echo "    kube-prometheus-stack installed"

# --------------------------------------------------
# Step 3: Enable Prometheus in KAI config
# --------------------------------------------------
echo ""
echo "[3/8] Enabling Prometheus in KAI config..."

kubectl patch config kai-config --type merge \
    -p '{"spec":{"prometheus":{"enabled":true}}}'

echo "    Prometheus enabled in KAI config"

# --------------------------------------------------
# Step 4: Wait for Prometheus to be ready
# --------------------------------------------------
echo ""
echo "[4/8] Waiting for Prometheus pod to be ready..."

kubectl wait --for=condition=ready pod \
    -n kai-scheduler -l app.kubernetes.io/name=prometheus \
    --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=ready pod \
    -n kai-scheduler prometheus-prometheus-0 \
    --timeout=120s 2>/dev/null || \
echo "    Warning: Could not verify Prometheus readiness. Continuing..."

echo "    Prometheus is ready"

# --------------------------------------------------
# Step 5: Apply ServiceMonitors
# --------------------------------------------------
echo ""
echo "[5/8] Applying ServiceMonitors..."

kubectl apply -f "${REPO_ROOT}/docs/metrics/service-monitors.yaml"

echo "    ServiceMonitors applied"

# --------------------------------------------------
# Step 6: Apply Grafana datasource + dashboard
# --------------------------------------------------
echo ""
echo "[6/8] Configuring Grafana datasource and dashboard..."

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
# Step 7: Create queues
# --------------------------------------------------
echo ""
echo "[7/8] Creating queue hierarchy..."

kubectl apply -f "${DEMO_DIR}/setup/queues.yaml"

echo "    Queues created: ai-department -> llm-team, vision-team"

# --------------------------------------------------
# Step 8: Create workloads namespace
# --------------------------------------------------
echo ""
echo "[8/8] Creating workloads namespace..."

kubectl create namespace workloads 2>/dev/null || true

echo "    Namespace 'workloads' ready"

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Verification:"
echo "  kubectl get pods -n kai-scheduler"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get queues"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &"
echo "  Open: http://localhost:3000 (admin/prom-operator)"
echo "  Kiosk mode: http://localhost:3000/d/fairshare-demo?kiosk"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n kai-scheduler svc/prometheus-operated 9090:9090 &"
echo "  Open: http://localhost:9090"
echo ""
echo "Next steps:"
echo "  1. Run: scripts/run-demo-before.sh  (shows the starvation problem)"
echo "  2. Run: scripts/run-demo-after.sh   (shows time-based fairshare fix)"
