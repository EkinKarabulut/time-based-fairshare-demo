#!/usr/bin/env bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# Observability setup for the Time-Based Fairshare Demo.
# Installs the OpenTelemetry Collector wired to Dash0:
#   - gateway (deployment): OTLP traces/metrics/logs + KAI metrics federated
#     from the kube-prometheus-stack Prometheus
#   - logs agent (daemonset): tails container logs on every node
# Grafana keeps reading metrics directly from Prometheus; this only adds
# the Dash0 export path.
#
# Prerequisites: scripts/setup.sh has been run (kube-prometheus-stack must
# be up so the federate endpoint exists).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================"
echo "  Observability Setup: OTel Collector + Dash0"
echo "============================================"

# --------------------------------------------------
# Step 1: Check Dash0 configuration
# --------------------------------------------------
if [ -z "${DASH0_AUTH_TOKEN:-}" ]; then
    echo ""
    echo "DASH0_AUTH_TOKEN is not set. Nothing to do:"
    echo "  Grafana already reads metrics directly from Prometheus."
    echo ""
    echo "To ship metrics, logs and traces to Dash0, run:"
    echo "  export DASH0_AUTH_TOKEN=<your token>"
    echo "  export DASH0_ENDPOINT_OTLP_GRPC_HOSTNAME=ingress.eu-west-1.aws.dash0.com  # optional (default)"
    echo "  export DASH0_ENDPOINT_OTLP_GRPC_PORT=4317                                 # optional (default)"
    echo "  export DASH0_DATASET=default                                              # optional (default)"
    echo "  ./scripts/setup-observability.sh"
    exit 0
fi

DASH0_ENDPOINT_OTLP_GRPC_HOSTNAME="${DASH0_ENDPOINT_OTLP_GRPC_HOSTNAME:-ingress.eu-west-1.aws.dash0.com}"
DASH0_ENDPOINT_OTLP_GRPC_PORT="${DASH0_ENDPOINT_OTLP_GRPC_PORT:-4317}"
DASH0_DATASET="${DASH0_DATASET:-default}"

# --------------------------------------------------
# Step 2: Create namespace + Dash0 secrets
# --------------------------------------------------
echo ""
echo "[1/3] Creating OpenTelemetry namespace and Dash0 secrets..."

kubectl create namespace opentelemetry --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic dash0-secrets \
    --from-literal=dash0-authorization-token="$DASH0_AUTH_TOKEN" \
    --from-literal=dash0-grpc-hostname="$DASH0_ENDPOINT_OTLP_GRPC_HOSTNAME" \
    --from-literal=dash0-grpc-port="$DASH0_ENDPOINT_OTLP_GRPC_PORT" \
    --from-literal=dash0-dataset="$DASH0_DATASET" \
    --namespace=opentelemetry \
    --dry-run=client -o yaml | kubectl apply -f -

echo "    Dash0 target: ${DASH0_ENDPOINT_OTLP_GRPC_HOSTNAME}:${DASH0_ENDPOINT_OTLP_GRPC_PORT} (dataset: ${DASH0_DATASET})"

# --------------------------------------------------
# Step 3: Install OpenTelemetry Collector (gateway)
# --------------------------------------------------
echo ""
echo "[2/3] Installing OpenTelemetry Collector gateway..."

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo update open-telemetry

helm upgrade -i otel-collector open-telemetry/opentelemetry-collector \
    --namespace opentelemetry \
    -f "${DEMO_DIR}/setup/otel-collector-values.yaml" \
    --wait --timeout 120s

echo "    Gateway installed (OTLP + Prometheus federation -> Dash0)"

# --------------------------------------------------
# Step 4: Install OpenTelemetry Collector (logs agent)
# --------------------------------------------------
echo ""
echo "[3/3] Installing OpenTelemetry Collector logs agent..."

helm upgrade -i otel-logs-agent open-telemetry/opentelemetry-collector \
    --namespace opentelemetry \
    -f "${DEMO_DIR}/setup/otel-logs-agent-values.yaml" \
    --wait --timeout 120s

echo "    Logs agent installed (pod logs -> Dash0)"

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo "============================================"
echo "  Observability Setup Complete!"
echo "============================================"
echo ""
echo "Verification:"
echo "  kubectl get pods -n opentelemetry"
echo "  kubectl logs -n opentelemetry deploy/otel-collector-opentelemetry-collector --tail=20"
echo ""
echo "OTLP endpoint for instrumented workloads:"
echo "  grpc: otel-collector-opentelemetry-collector.opentelemetry.svc.cluster.local:4317"
echo "  http: otel-collector-opentelemetry-collector.opentelemetry.svc.cluster.local:4318"
echo ""
echo "In Dash0 (dataset: ${DASH0_DATASET}):"
echo "  - Metrics: kai_queue_allocated_gpus, kai_queue_deserved_gpus, ..."
echo "  - Logs: kai-scheduler / workloads pod logs"
echo "  - Traces: appear once workloads send OTLP traces"
