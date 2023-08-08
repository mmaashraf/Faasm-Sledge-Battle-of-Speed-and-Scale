from sys import argv
import pandas as pd
import matplotlib.pyplot as plt

if len(argv) < 3:
    print(f"Usage: python {argv[0]} <ab_data_file> <output_file>")
    exit()

# Read the input file from command-line argument
filename = argv[1]

# Read the data from the CSV file
df = pd.read_csv(filename)
df['conn_conc'] = df.apply(lambda x: f"{int(x['connections'])}-{int(x['concurrency'])}", axis=1)

cols_to_graph = {
    "ttime": "Total test time (sec)",
    "rps": "Requests per second (#/sec)",
    "tpr": "Time per request (ms)",
    "tpr_all": "Time per request (Across all concurrent requests) (ms)",
    "trate": "Transfer rate (Kbytes/sec)"
}



fig, ax = plt.subplots()
plt.title(f'Apache Benchmark Metrics Normalized')

ax.set_xlabel('Total Requests + Concurrent Requests')

ax.plot(df['conn_conc'], (df['ttime'] - df['ttime'].mean()) / df['ttime'].std(), label=cols_to_graph['ttime'], color='blue') # 0-1.0
ax.plot(df['conn_conc'], (df['rps'] - df['rps'].mean()) / df['rps'].std(), label=cols_to_graph['rps'], color='red') # 0-25k
ax.plot(df['conn_conc'], (df['tpr'] - df['tpr'].mean()) / df['tpr'].std(), label=cols_to_graph['tpr'], color='green') # 0-10.0
ax.plot(df['conn_conc'], (df['tpr_all'] - df['tpr_all'].mean()) / df['tpr_all'].std(), label=cols_to_graph['tpr_all'], color='purple') # 0-1.0
ax.plot(df['conn_conc'], (df['trate'] - df['trate'].mean()) / df['trate'].std(), label=cols_to_graph['trate'], color='orange') # 0-2k

# Add a legend for the lines
lines, labels = ax.get_legend_handles_labels()
ax.legend(lines, labels, loc='best')

plt.xticks(rotation=90)
plt.tight_layout()

# Save the plot
plt.savefig(f'{argv[2]}_normalized.png')



for column_name, column_label in cols_to_graph.items():
    # Create a figure and axis object
    fig, ax = plt.subplots()
    plt.title(column_label)

    ax.set_xlabel('Total Requests + Concurrent Requests')

    ax.plot(df['conn_conc'], df[column_name], label=column_label, color='blue')

    # Set the y-axis labels and title
    ax.set_ylabel(column_label)

    plt.xticks(rotation=90)
    plt.tight_layout()

    # Save the plot
    plt.savefig(f'{argv[2]}_{column_name}.png')
