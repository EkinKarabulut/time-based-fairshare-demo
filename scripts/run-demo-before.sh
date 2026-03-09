#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# "BEFORE" Demo: Shows the starvation problem WITHOUT time-based fairshare
#
# Scenario (from NVIDIA blog):
#   1. Both teams are already running on the cluster ("normal operations")
#      - LLM team runs customer-facing inference endpoints (10 GPUs)
#      - Vision team runs continuous CV research jobs (2 GPUs each)
#   2. Vision team's small jobs fill the 50-GPU over-quota pool
#   3. LLM team analyzes customer feedback, needs to improve the model
#   4. LLM submits a 50-GPU post-training run -> STARVES
#      The post-training job waits…and waits…and waits.
#
# Watch Grafana: Vision stays at ~70 GPUs, LLM stuck at 10 GPUs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE=${NAMESPACE:-workloads}

echo "============================================"
echo "  BEFORE: Without Time-Based Fairshare"
echo "============================================"

# Clean slate
echo ""
echo "[Cleanup] Removing any existing workloads..."
kubectl delete pytorchjobs -n "$NAMESPACE" --all 2>/dev/null || true
kubectl delete jobs -n "$NAMESPACE" --all 2>/dev/null || true
kubectl delete pods -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true
kubectl delete podgroups -n "$NAMESPACE" --all 2>/dev/null || true
sleep 5

# Disable time-based fairshare
echo ""
echo "[Config] Disabling time-based fairshare..."
kubectl apply -f "${DEMO_DIR}/setup/scheduling-shard-no-tbf.yaml"
sleep 10

# Phase 1: Normal operations — both teams running simultaneously
echo ""
echo "[Phase 1] Normal operations: both teams are using the cluster"
echo "  LLM team: deploying customer-facing inference endpoints (10 GPUs)..."
echo "  Vision team: submitting CV research jobs — architecture tests, hyperparameter sweeps (2 GPUs each)..."

# Submit LLM inference and Vision R&D jobs simultaneously
for i in $(seq 1 10); do
    sed "s/PODINDEX/$i/g" "${DEMO_DIR}/jobs/llm-inference.yaml" | \
        kubectl apply -n "$NAMESPACE" -f -
done
for i in $(seq 1 35); do
    sed "s/PODINDEX/$i/g" "${DEMO_DIR}/jobs/vision-rd-job.yaml" | \
        kubectl apply -n "$NAMESPACE" -f -
done

echo "  Waiting 60s for both teams to settle into steady state..."
echo "  Vision's continuous small jobs fill the 50-GPU over-quota pool."
sleep 60

# Show current state
echo ""
echo "[Status] Current GPU allocation:"
echo "  LLM team pods:"
kubectl get pods -n "$NAMESPACE" -l team=llm-team --no-headers | wc -l | xargs -I{} echo "    {} pods running"
echo "  Vision team pods:"
kubectl get pods -n "$NAMESPACE" -l team=vision-team --no-headers | wc -l | xargs -I{} echo "    {} pods running"

# Phase 2: LLM post-training arrives (gang-scheduled)
echo ""
echo "[Phase 2] LLM team has analyzed customer feedback and needs to improve the model."
echo "  Submitting 50-GPU post-training run (5 pods x 10 GPUs, gang-scheduled)..."
echo "  Needs 20 remaining guaranteed GPUs + 30 from over-quota pool."

# Submit PyTorchJob (single resource — all pods created and gang-scheduled together)
kubectl apply -f "${DEMO_DIR}/jobs/llm-training-burst.yaml"

echo ""
echo "============================================"
echo "  The LLM team's post-training job"
echo "  waits...and waits...and waits."
echo ""
echo "  Vision team's continuous small jobs keep"
echo "  grabbing freed resources first. The scheduler"
echo "  sees LLM's 30-GPU over-quota request as"
echo "  exceeding fair share while Vision still"
echo "  claims their portion."
echo ""
echo "  Expected allocation:"
echo "    Vision: ~70 GPUs (20 quota + 50 over-quota)"
echo "    LLM:    ~10 GPUs (inference only)"
echo "    LLM post-training: 0 GPUs (STARVED!)"
echo "============================================"

echo ""
echo "Demo is running. All jobs sleep indefinitely to hold GPUs."
echo "Run ./scripts/cleanup.sh when done."
