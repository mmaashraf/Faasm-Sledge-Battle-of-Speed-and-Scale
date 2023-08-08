import matplotlib.pyplot as plt
import sys
from datetime import datetime

filename = sys.argv[1]
outfile = sys.argv[2]
# Read data from output_file.txt
data = []
with open(filename) as file:
    for line in file:
        row = line.strip().split()
        data.append([int(row[0]), int(row[1]), float(row[2])])

# Group data by concurrency
concurrency_data = {}
for row in data:
    concurrency = row[0]
    if concurrency not in concurrency_data:
        concurrency_data[concurrency] = {"timestamps": [], "cpu_values": [], "timestamps_hr":[]}
    concurrency_data[concurrency]["timestamps"].append(row[1])
    concurrency_data[concurrency]["timestamps_hr"].append(datetime.fromtimestamp(row[1] // 1000000000))
    concurrency_data[concurrency]["cpu_values"].append(row[2])

# Plot graph
fig, ax = plt.subplots()
for concurrency, values in concurrency_data.items():
    timestamps = values["timestamps_hr"]
    cpu_values = values["cpu_values"]
    ax.plot(timestamps, cpu_values, label=f"Concurrency {concurrency}", marker="o", markersize=2, linewidth=1)

ax.xaxis_date()
ax.set_xlabel("Timestamp")
ax.set_ylabel("CPU")
plt.legend(loc='best')
plt.xticks(**dict(rotation=45, fontsize=10, fontname="monospace", ha='right'))
plt.tight_layout()
fig.savefig(f'{outfile}.png')
