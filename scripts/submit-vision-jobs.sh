#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# Continuously submits Vision R&D jobs to maintain contention
# Each job uses 2 GPUs and runs for 2 minutes
# Press Ctrl+C to stop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE=${NAMESPACE:-workloads}
START_INDEX=${1:-1}
DELAY=${DELAY:-3}

echo "Submitting Vision R&D jobs continuously (starting at index $START_INDEX, ${DELAY}s delay)..."
echo "Press Ctrl+C to stop"

i=$START_INDEX
while true; do
    # Clean up completed/failed pods to avoid clutter
    kubectl delete pods -n "$NAMESPACE" -l team=vision-team,workload-type=training \
        --field-selector=status.phase==Succeeded 2>/dev/null || true
    kubectl delete pods -n "$NAMESPACE" -l team=vision-team,workload-type=training \
        --field-selector=status.phase==Failed 2>/dev/null || true

    sed "s/JOBINDEX/$i/g" "${DEMO_DIR}/jobs/vision-rd-job.yaml" | \
        kubectl apply -n "$NAMESPACE" -f - 2>/dev/null || true
    echo "  Submitted vision-rd-$i"
    i=$((i + 1))
    sleep "$DELAY"
done
