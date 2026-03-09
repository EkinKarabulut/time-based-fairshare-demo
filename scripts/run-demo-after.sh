#!/bin/bash
# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

# "AFTER" Demo: Shows time-based fairshare solving the starvation problem
#
# Scenario (same workloads as "before"):
#   1. Both teams are already running on the cluster ("normal operations")
#      - LLM team runs customer-facing inference endpoints (10 GPUs)
#      - Vision team runs continuous CV research jobs (2 GPUs each)
#   2. Vision team's small jobs fill the over-quota pool, building usage history
#   3. LLM team analyzes customer feedback, submits 50-GPU post-training run
#   4. Time-based fairshare detects Vision's high historical over-quota usage
#   5. LLM's effective fair share is boosted — resources OSCILLATE fairly!
#
# Watch Grafana: Allocation lines cross over as fairshare balances usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE=${NAMESPACE:-workloads}

echo "============================================"
echo "  AFTER: With Time-Based Fairshare"
echo "============================================"

# Clean slate
echo ""
echo "[Cleanup] Removing any existing workloads..."
kubectl delete pytorchjobs -n "$NAMESPACE" --all 2>/dev/null || true
kubectl delete jobs -n "$NAMESPACE" --all 2>/dev/null || true
kubectl delete pods -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true
kubectl delete podgroups -n "$NAMESPACE" --all 2>/dev/null || true
sleep 5

# Enable time-based fairshare
echo ""
echo "[Config] Enabling time-based fairshare..."
kubectl apply -f "${DEMO_DIR}/setup/scheduling-shard-with-tbf.yaml"
echo "  Waiting 15s for scheduler to restart and connect to Prometheus..."
sleep 15

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

echo "  Waiting 120s for both teams to settle and build usage history..."
echo "  Vision's continuous small jobs fill the 50-GPU over-quota pool."
sleep 120

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
echo "  With time-based fairshare, the scheduler sees that Vision has accumulated"
echo "  high historical over-quota usage while LLM has barely used over-quota."

# Submit PyTorchJob (single resource — all pods created and gang-scheduled together)
kubectl apply -f "${DEMO_DIR}/jobs/llm-training-burst.yaml"

echo ""
echo "============================================"
echo "  Observe Grafana: Watch the allocation"
echo "  lines OSCILLATE as time-based fairshare"
echo "  balances usage between teams."
echo ""
echo "  The scheduler boosts LLM's effective fair"
echo "  share because they've been historically"
echo "  starved for over-quota access."
echo ""
echo "  Expected behavior:"
echo "    1. Both teams running at steady state"
echo "    2. Fair share shifts toward LLM (lower history)"
echo "    3. LLM post-training pods start scheduling"
echo "    4. Resources oscillate fairly over time"
echo "============================================"

echo ""
echo "Demo is running. All jobs sleep indefinitely to hold GPUs."
echo "Watch Grafana for the oscillation pattern as fairshare rebalances."
echo "Run ./scripts/cleanup.sh when done."
