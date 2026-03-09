# Copyright 2025 NVIDIA CORPORATION
# SPDX-License-Identifier: Apache-2.0

"""
Branded plot script for KubeCon demo.
Generates side-by-side comparison of before/after time-based fairshare.

Usage:
    # Generate both CSVs first:
    ./bin/time-based-fairshare-simulator \
        -input demo/kubecon-fairshare/simulation/demo-config-no-tbf.yaml \
        -output demo/kubecon-fairshare/simulation/results-no-tbf.csv

    ./bin/time-based-fairshare-simulator \
        -input demo/kubecon-fairshare/simulation/demo-config-with-tbf.yaml \
        -output demo/kubecon-fairshare/simulation/results-with-tbf.csv

    # Generate the comparison plot:
    python demo/kubecon-fairshare/simulation/plot_branded.py \
        --before demo/kubecon-fairshare/simulation/results-no-tbf.csv \
        --after demo/kubecon-fairshare/simulation/results-with-tbf.csv \
        -o demo/kubecon-fairshare/simulation/fairshare-comparison.png
"""

import argparse
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib

matplotlib.rcParams.update({
    'font.size': 14,
    'axes.titlesize': 18,
    'axes.labelsize': 14,
    'legend.fontsize': 12,
    'figure.facecolor': '#1a1a2e',
    'axes.facecolor': '#16213e',
    'text.color': '#e0e0e0',
    'axes.labelcolor': '#e0e0e0',
    'xtick.color': '#e0e0e0',
    'ytick.color': '#e0e0e0',
})

NVIDIA_GREEN = '#76B900'
LLM_COLOR = '#4A90D9'
VISION_COLOR = '#F5A623'

parser = argparse.ArgumentParser(description='Plot before/after fairshare comparison')
parser.add_argument('--before', required=True, help='CSV file without time-based fairshare')
parser.add_argument('--after', required=True, help='CSV file with time-based fairshare')
parser.add_argument('--output', '-o', type=str, default=None,
                    help='Save plot to file (PNG/PDF). Displays interactively if not set.')
args = parser.parse_args()

df_before = pd.read_csv(args.before)
df_after = pd.read_csv(args.after)

fig, axes = plt.subplots(2, 2, figsize=(18, 10), sharex='col')
fig.suptitle('Time-Based Fairshare: Before vs After',
             fontsize=24, fontweight='bold', color=NVIDIA_GREEN, y=0.98)

# Filter to leaf queues only (skip department)
leaf_queues = ['llm-team', 'vision-team']
colors = {'llm-team': LLM_COLOR, 'vision-team': VISION_COLOR}
labels = {'llm-team': 'LLM Team', 'vision-team': 'Vision Team'}

def plot_panel(ax, df, metric, title):
    for queue in leaf_queues:
        queue_data = df[df['QueueID'] == queue]
        if not queue_data.empty:
            ax.plot(queue_data['Time'], queue_data[metric],
                    label=labels.get(queue, queue),
                    color=colors.get(queue, None),
                    linewidth=2)
    ax.set_title(title, fontweight='bold')
    ax.grid(True, alpha=0.2, color='#555')
    ax.legend(loc='upper right', facecolor='#16213e', edgecolor='#555')

# Top-left: Before - Allocation
plot_panel(axes[0][0], df_before, 'Allocation',
           'WITHOUT Time-Based Fairshare\n(GPU Allocation)')
axes[0][0].set_ylabel('GPUs Allocated')

# Top-right: After - Allocation
plot_panel(axes[0][1], df_after, 'Allocation',
           'WITH Time-Based Fairshare\n(GPU Allocation)')
axes[0][1].set_ylabel('GPUs Allocated')

# Bottom-left: Before - Fair Share
plot_panel(axes[1][0], df_before, 'FairShare',
           'WITHOUT Time-Based Fairshare\n(Fair Share)')
axes[1][0].set_ylabel('Fair Share (GPUs)')
axes[1][0].set_xlabel('Time (cycles)')

# Bottom-right: After - Fair Share
plot_panel(axes[1][1], df_after, 'FairShare',
           'WITH Time-Based Fairshare\n(Fair Share)')
axes[1][1].set_ylabel('Fair Share (GPUs)')
axes[1][1].set_xlabel('Time (cycles)')

plt.tight_layout(rect=[0, 0, 1, 0.95])

if args.output:
    plt.savefig(args.output, dpi=200, bbox_inches='tight',
                facecolor=fig.get_facecolor())
    print(f"Plot saved to {args.output}")
else:
    plt.show()
