from sys import argv
from itertools import cycle
from math import floor, ceil
from warnings import filterwarnings
filterwarnings('ignore')

import pandas as pd
import matplotlib.pyplot as plt


figsize = (10, 6)
xtick_config = dict(rotation=45, fontsize=10, fontname="monospace", ha='right')

if len(argv) < 3:
    print(f"Usage: python {argv[0]} <ab_data_file> <output_file_prefix>")
    exit()

filename = argv[1]
df = pd.read_csv(filename)
df = df.groupby(['connections', 'concurrency']).mean().reset_index()
cols = df.select_dtypes(include=[float]).columns
df[cols] = df[cols].round(2)
df['conn_conc'] = df.apply(lambda x: f"{(str(int(x['connections']/1000))+'k').ljust(4, '.')}.{str(int(x['concurrency'])).rjust(4, '.')}", axis=1)

cols_to_graph = {
    "ttime": "Total test time (sec)",
    "rps": "Requests per second (#/sec)",
    "tpr": "Time per request (ms)",
    "tpr_all": "Time per request (Across all concurrent requests) (ms)",
    "trate": "Transfer rate (Kbytes/sec)"
}




# Create normalized graph for rps, ttime, tpr
for connection_count in df['connections'].unique():
    fig, ax = plt.subplots(figsize=figsize)
    plt.title(f'Apache Benchmark Metrics Normalized')

    ax.set_xlabel('Total Requests + Concurrent Requests')
    df_filtered = df[df['connections'] == connection_count]
    colors = ["blue", 'red', 'yellow', 'green']
    for i, col in enumerate(['rps', 'ttime', 'tpr', 'tpr_all']):
        df_filtered["y_normed"] = (df_filtered[col] - df_filtered[col].mean()) / df_filtered[col].std()
        ax.plot(df_filtered['conn_conc'], df_filtered["y_normed"], label=cols_to_graph[col], color=colors[i])
        max_point = df_filtered.loc[df_filtered[col].idxmax()]
        ax.text(max_point["conn_conc"], max_point["y_normed"], f"{max_point[col]}", fontsize=8,
                bbox=dict(facecolor=colors[i], edgecolor='black', boxstyle='round,pad=0.5', alpha=0.5))
        ax.plot(max_point["conn_conc"], max_point["y_normed"], colors[i], marker="^")
    ax.set_xticklabels([item.get_text().split()[0] for item in ax.get_xticklabels()])
    plt.xticks(**xtick_config)

    lines, labels = ax.get_legend_handles_labels()
    ax.legend(lines, labels, loc='best')

    plt.tight_layout()
    plt.grid(alpha=0.5)
    plt.savefig(f'{argv[2]}_normalized_{connection_count}.png')




# Create individual graphs for rps, tpr, tpr_all, trate, ttime
for column_name, column_label in cols_to_graph.items():
    """ For all data in one graph
    fig, ax = plt.subplots(figsize=figsize)
    plt.title(column_label)

    ax.set_xlabel('Total Requests + Concurrent Requests')

    colors=cycle({"red", "blue"})
    for connection_count in df['connections'].unique():
        df_filtered = df[df['connections']==connection_count]
        curr_color=next(colors)
        ax.plot(df_filtered['conn_conc'], df_filtered[column_name], color=curr_color)
    ax.set_ylabel(column_label)

    plt.xticks(**xtick_config)
    plt.tight_layout()

    ax.set_xticklabels([item.get_text().split()[0] for item in ax.get_xticklabels()])

    plt.grid(alpha=0.5)
    plt.savefig(f'{argv[2]}_{column_name}.png')
    """
    for connection_count in df['connections'].unique():
        fig, ax = plt.subplots(figsize=figsize)
        plt.title(column_label)

        ax.set_xlabel('Total Requests + Concurrent Requests')
        df_filtered = df[df['connections'] == connection_count]
        ax.plot(df_filtered['conn_conc'], df_filtered[column_name], color='blue')
        max_point = df_filtered.loc[df_filtered[column_name].idxmax()]
        ax.text(max_point["conn_conc"], max_point[column_name], f"{max_point[column_name]}", fontsize=8,
                bbox=dict(facecolor=colors[i], edgecolor='black', boxstyle='round,pad=0.5', alpha=0.5))
        ax.plot(max_point["conn_conc"], max_point[column_name], colors[i], marker="^")
        ax.set_ylabel(column_label)
        if column_name == 'rps':
            y_min, y_max = df_filtered['rps'].min(), df_filtered['rps'].max()
            y_range = y_max - y_min
            if y_range < 100:
                y_limit_min = floor(y_min / 100) * 100
                y_limit_max = ceil(y_max / 100) * 100
                plt.ylim(y_limit_min, y_limit_max)

        plt.xticks(**xtick_config)
        ax.set_xticklabels([item.get_text().split()[0] for item in ax.get_xticklabels()])

        plt.tight_layout()
        plt.grid(alpha=0.5)
        plt.savefig(f'{argv[2]}_{column_name}_{connection_count}.png')




# Create graph for rps + ttime
for connection_count in df['connections'].unique():
    fig, ax = plt.subplots(figsize=figsize)
    plt.title(f'Requests Per Second + Total Time')

    plt.xticks(**xtick_config)
    ax.set_xlabel('Total Requests + Concurrent Requests')

    df_filtered = df[df['connections'] == connection_count]
    ax.plot(df_filtered['conn_conc'], df_filtered['rps'], label=cols_to_graph['rps'], color='blue') # 0-1.0
    max_point = df_filtered.loc[df_filtered['rps'].idxmax()]
    column_name='rps'
    ax.text(max_point["conn_conc"], max_point[column_name], f"{max_point[column_name]}", fontsize=8,
            bbox=dict(facecolor=colors[i], edgecolor='black', boxstyle='round,pad=0.5', alpha=0.5))
    ax.plot(max_point["conn_conc"], max_point[column_name], colors[i], marker="^")
    ax.set_ylabel(cols_to_graph["rps"], color='blue')
    ax2 = ax.twinx()
    ax2.plot(df_filtered['conn_conc'], df_filtered['ttime'], label=cols_to_graph['ttime'], color='red') # 0-25k
    max_point = df_filtered.loc[df_filtered['ttime'].idxmax()]
    column_name='ttime'
    ax2.text(max_point["conn_conc"], max_point[column_name], f"{max_point[column_name]}", fontsize=8,
            bbox=dict(facecolor=colors[i], edgecolor='black', boxstyle='round,pad=0.5', alpha=0.5))
    ax2.plot(max_point["conn_conc"], max_point[column_name], colors[i], marker="^")
    ax2.set_ylabel(cols_to_graph["ttime"], color='red')
    ax.set_xticklabels([item.get_text().split()[0] for item in ax.get_xticklabels()])

    # ax.legend(*(ax.get_legend_handles_labels() + ax2.get_legend_handles_labels()), loc='best')
    ax.legend(*tuple(x + y for x, y in zip(ax.get_legend_handles_labels(), ax2.get_legend_handles_labels())), loc='best')

    plt.tight_layout()
    plt.grid(alpha=0.5)
    plt.savefig(f'{argv[2]}_rps_ttime_{connection_count}.png')
