from sys import argv
from os import listdir
import re
from warnings import filterwarnings
from functools import partial
filterwarnings('ignore')

import pandas as pd
import matplotlib.pyplot as plt


colors = ['blue', 'green', 'red', 'cyan', 'magenta', 'yellow']
figsize = (10, 6)
xtick_config = dict(rotation=45, fontsize=10, fontname="monospace", ha='right')


def transform_dataframe_common(csv_filepath: str) -> pd.DataFrame:
    df = pd.read_csv(csv_filepath)
    df = df.groupby(['connections', 'concurrency']).mean().reset_index()
    cols = df.select_dtypes(include=[float]).columns
    df[cols] = df[cols].round(2)
    df['dupe_num'] = df.groupby(['connections', 'concurrency']).cumcount()
    return df


def graph_common(dfs: list, cores: list, graph_title_partial: partial, graph_output_filename_partial: partial) -> None:
    for connection_count in set([c for c in pd.concat(dfs)['connections'].unique()]):
        fig, ax = plt.subplots(figsize=figsize)
        unique_triples = {(row['connections'], row['concurrency'], row['dupe_num']) for df in dfs for _, row in df.iterrows() if row['connections'] == connection_count}
        for i, df in enumerate(dfs):
            df = df[df['connections'] == connection_count]
            for triple in unique_triples:
                if not (df[['connections', 'concurrency', 'dupe_num']] == list(triple)).all(axis=1).any():
                    new_row = pd.DataFrame([triple], columns=['connections', 'concurrency', 'dupe_num'])
                    df = df.append(new_row, ignore_index=True)
            # df['conn_conc'] = df.apply(lambda x: f"{(str(int(x['connections']/1000))+'k').ljust(4, '.')}.{str(int(x['concurrency'])).rjust(4, '.')}|{int(x['dupe_num'])}", axis=1)
            df['conn_conc'] = df.apply(lambda x: f"{(str(int(x['connections']/1000))+'k').ljust(4, '.')}.{str(int(x['concurrency'])).rjust(4, '.')}", axis=1)
            df.sort_values(['connections', 'concurrency', 'dupe_num'], inplace=True)
            df = df.interpolate(limit_area='inside')
            ax.plot(df['conn_conc'], df['rps'], color=colors[i], label='{} cores'.format(cores[i]))
            max_point = df.loc[df['rps'].idxmax()]
            ax.text(max_point["conn_conc"], max_point["rps"], f"Cores: {cores[i]}, {max_point['rps']}", fontsize=8,
                    bbox=dict(facecolor=colors[i], edgecolor='black', boxstyle='round,pad=0.5', alpha=0.5))
            ax.plot(max_point["conn_conc"], max_point["rps"], colors[i], marker="^")
            plt.xticks(**xtick_config)
                
        ax.set_xlabel('Connections + Concurrency')
        ax.set_ylabel('Requests per second')
        ax.set_title(graph_title_partial(connection_count=connection_count))
        ax.legend(loc='upper left')
        plt.tight_layout()
        plt.savefig(graph_output_filename_partial(connection_count=connection_count))


def generate_graphs_sledge():
    pattern = r'sledgert_(.+)_workers_(.+)_spinlooppause_(.+)_ab_data'
    files, appnames_set, cores_set, spinloop_set = set(), set(), set(), set()
    for filename in listdir():
        match = re.match(pattern, filename)
        if match:
            files.add(filename)
            appnames_set.add(match.group(1))
            cores_set.add(int(match.group(2)))
            spinloop_set.add(match.group(3))
    cores = sorted(list(cores_set))
    files = sorted(list(files), key=lambda f: int(re.sub('\D', '', f)))

    for appname in appnames_set:
        for spinlooppause_val in spinloop_set:
            dfs = [transform_dataframe_common(file) for file in files if appname in file and spinlooppause_val in file]
            graph_common(dfs, cores, graph_title_partial=partial('{appname} - {connection_count} requests - spinlooppause={spinlooppause_val}'.format, appname=appname, spinlooppause_val=spinlooppause_val), \
                        graph_output_filename_partial=partial('{appname}_{spinlooppause_val}_{connection_count}.png'.format, appname=appname, spinlooppause_val=spinlooppause_val))


def generate_graphs_faasm():
    pattern = r'faasm_(.+)_workers_(.+)_ab_data'
    files, appnames_set, cores_set = set(), set(), set()
    for filename in listdir():
        match = re.match(pattern, filename)
        if match:
            files.add(filename)
            appnames_set.add(match.group(1))
            cores_set.add(int(match.group(2)))
    cores = sorted(list(cores_set))
    files = sorted(list(files), key=lambda f: int(re.sub('\D', '', f)))

    for appname in appnames_set:
        dfs = [transform_dataframe_common(file) for file in files if appname in file]
        graph_common(dfs, cores, graph_title_partial=partial('{appname} - {connection_count} requests'.format, appname=appname), \
                        graph_output_filename_partial=partial('{appname}_{connection_count}.png'.format, appname=appname))


framework_function = { "sledgert": generate_graphs_sledge, "faasm": generate_graphs_faasm }
if __name__ == '__main__':
    if len(argv) < 2:
        print(f"Usage: python {argv[0]} <wasm_framework>")
        exit()
    framework = argv[1]
    framework_function.get(framework, lambda: exit(f"Invalid framework name, expected: {' or '.join(framework_function.keys())}"))()
    