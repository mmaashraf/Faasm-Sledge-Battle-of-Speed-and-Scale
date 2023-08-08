import matplotlib.pyplot as plt
import matplotlib.dates as md
from datetime import datetime
import sys

filename = sys.argv[1]
outfile = sys.argv[2]
# Read data from output_file.txt
data = []
with open(filename) as file:
    for line in file:
        row = line.strip().split()
        data.append([int(row[0]), int(row[1]), float(row[3]), float(row[4])])

# Group data by concurrency
concurrency_data = {}
for row in data:
    concurrency = row[0]
    if concurrency not in concurrency_data:
        concurrency_data[concurrency] = {"timestamps": [], "timestamps_hr": [], "vm_values": [],"pm_values": []}
    concurrency_data[concurrency]["timestamps"].append(row[1])
    concurrency_data[concurrency]["timestamps_hr"].append(md.date2num(datetime.fromtimestamp(row[1] // 1000000000)))
    concurrency_data[concurrency]["vm_values"].append(row[2])
    concurrency_data[concurrency]["pm_values"].append(row[3])


# Plot graph
fig, ax = plt.subplots()
for concurrency, values in concurrency_data.items():
    timestamps = values["timestamps_hr"]
    color = next(ax._get_lines.prop_cycler)['color']
    pm_values = values["pm_values"]
    ax.plot(timestamps, pm_values, label=f"PM-Concurrency {concurrency}", marker="x", markersize=2, linewidth=1, color=color)
# Set labels and legend
ax.xaxis.set_major_formatter(md.DateFormatter('%H:%M:%S'))
ax.set_xlabel("Timestamp")
ax.set_ylabel("Physical Memory (Mb)")
plt.legend(loc='best',prop = {'size' : 6})
plt.xticks(**dict(rotation=45, fontsize=10, fontname="monospace", ha='right'))
plt.tight_layout()
fig.savefig(f'{outfile}_Physical.png')



fig, ax = plt.subplots()
for concurrency, values in concurrency_data.items():
    timestamps = values["timestamps_hr"]
    color = next(ax._get_lines.prop_cycler)['color']
    vm_values = values["vm_values"]
    ax.plot(timestamps, vm_values, label=f"VM-Concurrency {concurrency}", marker="o", markersize=2, linewidth=1, color=color)
# Set labels and legend
ax.xaxis.set_major_formatter(md.DateFormatter('%H:%M:%S'))
ax.set_xlabel("Timestamp")
ax.set_ylabel("Virtual Memory (Mb)")
plt.legend(loc='best',prop = {'size' : 6})
plt.xticks(**dict(rotation=45, fontsize=10, fontname="monospace", ha='right'))
plt.tight_layout()
fig.savefig(f'{outfile}_Virtual.png')
