from os import listdir
import re
import warnings
warnings.filterwarnings('ignore')

import pandas as pd
import matplotlib.pyplot as plt


pattern = r'faasm_(.+)_workers_(.+)_ab_data'
colors = ['blue', 'green', 'red', 'cyan', 'magenta', 'yellow']
figsize = (10, 6)
xtick_config = dict(rotation=45, fontsize=10, fontname="monospace", ha='right')


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
    dfs = []
    for file in files:
        if appname in file:
            df = pd.read_csv(file)
            df = df.groupby(['connections', 'concurrency']).mean().reset_index()
            cols = df.select_dtypes(include=[float]).columns
            df[cols] = df[cols].round(2)
            df['dupe_num'] = df.groupby(['connections', 'concurrency']).cumcount()
            dfs.append(df)

    for connection_count in set([c for c in df['connections'].unique()]):
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
        ax.set_title('{} - {} requests'.format(appname, connection_count))
        ax.legend(loc='upper left')
        plt.tight_layout()
        plt.savefig('{}_{}.png'.format(appname, connection_count))
