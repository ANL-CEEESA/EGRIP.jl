import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

color_list = ['black', 'red', 'blue', 'green', 'cyan', 'magenta', 'darkorange',
              'royalblue', 'lime', 'chocolate', 'olive', 'yellow', 'mediumslateblue',
              'tan', 'teal', 'palegreen'
              ]

wind_xls = pd.ExcelFile('wind_farm_POE.xlsx')
name_list = ['Observed Power (MW)', '90 POE', '80 POE', '70 POE', '60 POE', '50 POE', '40 POE', '30 POE', '20 POE', '10 POE']
wind_farm1 = pd.read_excel(wind_xls, "farm 1")
wind_farm2 = pd.read_excel(wind_xls, "farm 2")
wind_farm3 = pd.read_excel(wind_xls, "farm 3")

# retrieve all real wind power data and save as CSV
wind_power = wind_farm1['Observed Power (MW)']
wind_power = wind_power.append(wind_farm2['Observed Power (MW)'], ignore_index=True)
wind_power = wind_power.append(wind_farm3['Observed Power (MW)'], ignore_index=True)
wind_power.to_csv("wind_power.csv", index=False)

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
plt.plot(wind_power, alpha=1, color='b', linewidth=2)
plt.show()
plt.grid(color='0.8')
plt.ylabel("MW", fontsize=16)
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.savefig("WF_real_all.png")

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
for i, k in enumerate(name_list):
    plt.plot(wind_farm1[k], label=k, alpha=1, color=color_list[i])
# plt.plot(wind_farm1["Observed Power (MW)"], label="Observed Power (MW)", alpha=0.5, linewidth=3, color='black')
plt.legend(fontsize=16)
plt.show()
plt.ylabel("MW", fontsize=16)
plt.grid(color='0.8')
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.title('Wind Farm 1', fontsize=16)
plt.savefig("WF_1.png")

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
for i, k in enumerate(name_list):
    plt.plot(wind_farm2[k], label=k, alpha=1, color=color_list[i])
# plt.plot(wind_farm1["Observed Power (MW)"], label="Observed Power (MW)", alpha=0.5, linewidth=3, color='black')
plt.legend(fontsize=16)
plt.show()
plt.ylabel("MW", fontsize=16)
plt.grid(color='0.8')
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.title('Wind Farm 2', fontsize=16)
plt.savefig("WF_2.png")

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
for i, k in enumerate(name_list):
    plt.plot(wind_farm3[k], label=k, alpha=1, color=color_list[i])
# plt.plot(wind_farm1["Observed Power (MW)"], label="Observed Power (MW)", alpha=0.5, linewidth=3, color='black')
plt.legend(fontsize=16)
plt.show()
plt.ylabel("MW", fontsize=16)
plt.grid(color='0.8')
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.title('Wind Farm 3', fontsize=16)
plt.savefig("WF_3.png")

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
plt.plot(wind_farm1['90 POE'], label='Farm 1', alpha=1, color=color_list[1])
plt.plot(wind_farm2['90 POE'], label='Farm 2', alpha=1, color=color_list[2])
plt.plot(wind_farm3['90 POE'], label='Farm 3', alpha=1, color=color_list[3])
# plt.plot(wind_farm1["Observed Power (MW)"], label="Observed Power (MW)", alpha=0.5, linewidth=3, color='black')
plt.legend(fontsize=16)
plt.show()
plt.ylabel("MW", fontsize=16)
plt.grid(color='0.8')
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.title('Wind Farm POE 90', fontsize=16)
plt.savefig("WF_comp_poe90.png")

plt.rcParams.update({'font.family': 'Arial'})
plt.figure(figsize=(15, 8))
plt.plot(wind_farm1['Observed Power (MW)'], label='Farm 1', alpha=1, color=color_list[1])
plt.plot(wind_farm2['Observed Power (MW)'], label='Farm 2', alpha=1, color=color_list[2])
plt.plot(wind_farm3['Observed Power (MW)'], label='Farm 3', alpha=1, color=color_list[3])
# plt.plot(wind_farm1["Observed Power (MW)"], label="Observed Power (MW)", alpha=0.5, linewidth=3, color='black')
plt.legend(fontsize=16)
plt.show()
plt.ylabel("MW", fontsize=16)
plt.grid(color='0.8')
plt.xticks(fontsize=16)
plt.yticks(fontsize=16)
plt.title('Wind Farm Observed Power', fontsize=16)
plt.savefig("WF_comp_observed_power.png")