# KubeCon Demo: Time-Based Fairshare GPU Allocation

A live demo showing how KAI Scheduler's time-based fairshare feature solves GPU allocation starvation between competing teams. Designed as a **looping booth display** with Grafana dashboards.

## Scenario (from [NVIDIA Blog](https://developer.nvidia.com/blog/ensuring-balanced-gpu-allocation-in-kubernetes-clusters-with-time-based-fairshare/))

- **100 GPU cluster** shared between two teams
- **LLM Team**: 30 GPU guaranteed quota, runs customer-facing inference endpoints (10 GPUs)
- **Vision Team**: 20 GPU guaranteed quota, focuses on computer vision research — testing architectures, hyperparameter sweeps, object detection training
- **50 GPUs** shared as an over-quota pool (equal weight)

**The Problem**: On a normal day, both teams are using the cluster. The Vision team's continuous stream of small 2-GPU training jobs fills the over-quota pool. When the LLM team analyzes customer feedback and launches a 50-GPU post-training run (20 remaining guaranteed + 30 from the over-quota pool), the scheduler sees LLM's over-quota request as exceeding fair share. Vision's small jobs keep grabbing freed resources first. The LLM team's post-training job waits...and waits...and waits.

**The Solution**: Time-based fairshare tracks historical over-quota usage. It detects that Vision has been consuming far more over-quota resources than LLM, boosts LLM's effective fair share, and resources oscillate fairly between teams over time.

## Prerequisites

- Kubernetes cluster with `kubectl` access
- [fake-gpu-operator](https://github.com/run-ai/fake-gpu-operator) installed (10 GPUs per node, 100 total)
- Helm 3
- ~16GB RAM on cluster nodes

## Quick Start

```bash
# 1. Install KAI Scheduler + Prometheus + Grafana
./scripts/setup.sh

# 2. Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# 3. Open Grafana dashboard in kiosk mode
open "http://localhost:3000/d/fairshare-demo?kiosk"
# Login: admin / prom-operator

# 4. Run the "before" demo (starvation problem)
./scripts/run-demo-before.sh

# 5. When ready, Ctrl+C and run the "after" demo (fairshare fix)
./scripts/run-demo-after.sh
```

## Demo Flow

### Phase 1: "Before" (Without Time-Based Fairshare)

Run `./scripts/run-demo-before.sh`:

1. **Normal operations** — both teams deploy simultaneously:
   - LLM inference endpoints (10 pods x 1 GPU = 10 GPUs)
   - Vision R&D jobs (35 jobs x 2 GPUs = 70 GPU demand)
2. Vision fills the over-quota pool (20 quota + 50 over-quota = 70 GPUs)
3. LLM team analyzes customer feedback, submits a 50-GPU post-training run
4. **The post-training job waits...and waits...and waits** — Vision's continuous small jobs keep grabbing freed resources first

**What you see on Grafana**:
- GPU Allocation: Vision at ~70, LLM stuck at ~10
- Pending GPU Demand: blue area jumps to 50 (LLM's post-training is blocked)

### Phase 2: "After" (With Time-Based Fairshare)

Run `./scripts/run-demo-after.sh`:

1. **Same normal operations** — both teams running simultaneously
2. Vision fills the over-quota pool (building usage history)
3. LLM team submits the same 50-GPU post-training run
4. **Time-based fairshare detects Vision's high historical over-quota usage**
5. LLM's effective fair share is boosted — the scheduler reclaims over-quota GPUs from Vision
6. **Resources oscillate** — both teams get fair access over time

**What you see on Grafana**:
- GPU Allocation: lines cross over and oscillate as fairshare rebalances
- Pending GPU Demand: blue area appears briefly then shrinks as LLM pods get scheduled
- Fair Share Over Time: LLM share rises, Vision share drops, then they oscillate

## Grafana Dashboard

The dashboard (`grafana/dashboard.json`) includes:

| Panel | Description |
|-------|-------------|
| Header | Scenario summary: 100 GPUs, quotas, shared pool |
| GPU Allocation Over Time | Main chart — shows real-time GPU allocation per team |
| Pending GPU Demand | Shows GPUs that pods are waiting for (Pending pods only) |
| Fair Share Over Time | Shows how fair share adjusts based on historical usage |
| LLM/Vision Gauges | Current GPU allocation per team |

**Dashboard settings**: Dark theme, 5s auto-refresh, 15-minute rolling window, kiosk mode.

## Partner Story (for explaining the demo)

### Setup

*"We have a 100 GPU cluster shared by two teams. The LLM team has 30 GPUs guaranteed for their customer-facing inference endpoints — they use about 10. The Vision team has 20 GPUs guaranteed for computer vision research — architecture testing, hyperparameter sweeps, object detection. There's a 50 GPU shared pool that either team can borrow from when they need extra capacity."*

### The Normal Day

*"On a normal day, both teams are running. LLM is serving inference on 10 GPUs. The Vision team has a steady stream of small 2-GPU training jobs — they fill up the entire shared pool. Vision is using 70 GPUs total: their 20 guaranteed plus all 50 from the shared pool. The cluster is fully utilized, no GPUs wasted."*

### The Trigger

*"Then the LLM team finishes analyzing customer feedback and realizes they need to improve the model. They launch a post-training run that needs 50 GPUs — 20 from their remaining guaranteed quota plus 30 from the shared pool."*

### Without Time-Based Fairshare (the problem)

*"Without time-based fairshare, the LLM team's post-training job waits...and waits...and waits. Here's why: the scheduler operates statelessly. Whenever a Vision job finishes and frees 2 GPUs, Vision has another small job ready to grab them immediately. The scheduler sees LLM requesting 30 GPUs from the shared pool as exceeding fair share while Vision still claims their portion. LLM can never accumulate enough free GPUs to start their gang-scheduled training job."*

*"Look at the Pending GPU Demand chart — that blue area at 50 means 50 GPUs worth of LLM work is blocked and waiting. It stays there indefinitely."*

### With Time-Based Fairshare (the solution)

*"With time-based fairshare enabled, the scheduler tracks historical usage. It sees that Vision has been consuming far more over-quota resources than LLM over time. So it boosts LLM's effective fair share and begins reclaiming GPUs from Vision's over-quota allocation."*

*"Watch the allocation chart — the lines cross over. LLM's post-training pods start scheduling. The Pending GPU Demand chart drops as those blocked pods get resources. Over time, the allocation oscillates fairly between both teams."*

### The Takeaway

*"Time-based fairshare gives you three things: (1) No wasted GPUs — teams can freely borrow idle capacity. (2) No starvation — when contention happens, the scheduler reclaims borrowed GPUs based on historical fairness. (3) Automatic — no manual intervention needed, the scheduler handles rebalancing."*

## Recording for Booth Loop

### Using OBS Studio

1. Set up OBS at 1920x1080, 60fps
2. Create scene: full-screen browser capture of Grafana in kiosk mode
3. Run the "before" demo, record for 3-5 minutes
4. Add a title overlay: "WITHOUT Time-Based Fairshare"
5. Run the "after" demo, record for 5-8 minutes
6. Add a title overlay: "WITH Time-Based Fairshare"
7. Combine clips, add transition between before/after
8. Export as loop-friendly MP4

### Tips

- Use browser zoom (150%) for readability at booth distance
- Add a "fast forward" indicator when waiting for oscillation
- The oscillation takes ~2-5 minutes to become visible (tunable)

## Tuning Parameters

If oscillation is too slow or too fast, edit `setup/scheduling-shard-with-tbf.yaml`:

| Parameter | Faster Oscillation | Slower Oscillation |
|-----------|-------------------|-------------------|
| `windowSize` | `2m` | `10m` |
| `halfLifePeriod` | `30s` | `3m` |
| `kValue` | `2.0` | `0.5` |
| `fetchInterval` | `10s` | `30s` |

After changing, re-apply: `kubectl apply -f setup/scheduling-shard-with-tbf.yaml`

## Simulator (Offline Plots)

Generate static before/after comparison plots without a cluster:

```bash
# Build the simulator
cd /path/to/KAI-Scheduler
go build -o bin/time-based-fairshare-simulator ./cmd/time-based-fairshare-simulator

# Generate CSV results
./bin/time-based-fairshare-simulator \
    -input demo/kubecon-fairshare/simulation/demo-config-no-tbf.yaml \
    -output demo/kubecon-fairshare/simulation/results-no-tbf.csv

./bin/time-based-fairshare-simulator \
    -input demo/kubecon-fairshare/simulation/demo-config-with-tbf.yaml \
    -output demo/kubecon-fairshare/simulation/results-with-tbf.csv

# Generate branded comparison plot
pip install pandas matplotlib
python demo/kubecon-fairshare/simulation/plot_branded.py \
    --before demo/kubecon-fairshare/simulation/results-no-tbf.csv \
    --after demo/kubecon-fairshare/simulation/results-with-tbf.csv \
    -o demo/kubecon-fairshare/simulation/fairshare-comparison.png
```

## Troubleshooting

### Prometheus not scraping metrics

```bash
# Check Prometheus is running
kubectl get pods -n kai-scheduler -l app.kubernetes.io/name=prometheus

# Check ServiceMonitors exist
kubectl get servicemonitors -n kai-scheduler

# Verify metrics are being exposed
kubectl port-forward -n kai-scheduler svc/prometheus-operated 9090:9090 &
# Query: kai_queue_allocated_gpus
```

### Grafana dashboard shows "No data"

1. Verify the `kai-prometheus` datasource is configured:
   - Grafana > Settings > Data Sources > kai-prometheus
   - Test connection
2. Check that KAI scheduler is running and metrics are flowing:
   ```bash
   kubectl get pods -n kai-scheduler
   kubectl logs -n kai-scheduler -l app=scheduler --tail=20
   ```
3. Wait 1-2 minutes for Prometheus to scrape initial data

### Oscillation not visible

- Increase `kValue` to 2.0 for more aggressive correction
- Decrease `windowSize` to 2m and `halfLifePeriod` to 30s
- Ensure both teams have continuous job demand (the scripts handle this)

### Vision jobs not monopolizing in "before" demo

- Ensure enough Vision jobs are submitted (the script submits 35 initially)
- Check that Vision jobs request 2 GPUs each and LLM inference is only 10 GPUs
- Verify queues exist: `kubectl get queues`

## Cleanup

```bash
# Remove workloads only
./scripts/cleanup.sh

# Full teardown (removes KAI, Prometheus, Grafana)
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall kai-scheduler -n kai-scheduler
kubectl delete namespace workloads monitoring kai-scheduler
```

## File Structure

```
demo/kubecon-fairshare/
  README.md                          # This file
  setup/
    queues.yaml                      # Queue hierarchy
    scheduling-shard-no-tbf.yaml     # Config without time-based fairshare
    scheduling-shard-with-tbf.yaml   # Config with time-based fairshare
  jobs/
    llm-inference.yaml               # Always-on inference pods
    vision-rd-job.yaml               # Vision R&D job template
    llm-training-burst.yaml          # LLM post-training template
  scripts/
    setup.sh                         # Full setup script
    run-demo-before.sh               # "Before" demo
    run-demo-after.sh                # "After" demo
    cleanup.sh                       # Workload cleanup
  grafana/
    dashboard.json                   # Grafana dashboard
    datasource-configmap.yaml        # Prometheus datasource
  simulation/
    demo-config-no-tbf.yaml          # Simulator: no TBF
    demo-config-with-tbf.yaml        # Simulator: with TBF
    plot_branded.py                  # Branded comparison plot
```
