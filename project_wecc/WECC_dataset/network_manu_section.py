import pandas as pd
import numpy as np
import json
import csv

# given the boundary lines and buses
boundary_lines = [[107, 132], [103, 133], [13, 28]]
network_section = {"1": [13, 103, 107], "2": [28, 132, 133]}

# read data
data_bus = pd.read_csv("WECC_Bus_all.csv", encoding="ISO-8859-1")
data_line = pd.read_csv("WECC_Line.csv", encoding="ISO-8859-1")
data_trans = pd.read_csv("WECC_Trans.csv", encoding="ISO-8859-1")

# construct a bus pairs
num_bus = data_bus.shape[0]
num_line = data_line.shape[0]
num_trans = data_trans.shape[0]

# create a list for bus pairs
bus_pairs = []

# loop the line data
for i in range(num_line):
    bus_1 = data_line["from_bus"][i]
    bus_2 = data_line["to_bus"][i]
    bus_pair = [bus_1, bus_2]
    bus_pair.sort()
    if (bus_pair not in boundary_lines) and (bus_pair not in bus_pairs):
        bus_pairs.append(bus_pair)
# loop the transformer data
for i in range(num_trans):
    bus_1 = data_trans["from_bus"][i]
    bus_2 = data_trans["to_bus"][i]
    bus_pair = [bus_1, bus_2]
    bus_pair.sort()
    if (bus_pair not in boundary_lines) and (bus_pair not in bus_pairs):
        bus_pairs.append(bus_pair)

# convert bus pairs to numpy array
bus_pairs = np.array(bus_pairs)

# loop bus set in section data and compare with bus pair
search_flag = 1
from_bus_position = 0
to_bus_position = 1

debug_dict = {}
loop_counter = 0

while search_flag:
    # check current bus numbers is each section
    key_section = network_section.keys()
    debug_dict[loop_counter] = {}
    # loop all sections
    for s in key_section:
        debug_dict[loop_counter][s] = {}
        num_root_bus = len(network_section[s])
        for i in range(num_root_bus):
            # get a root bus
            root_bus = network_section[s][i]
            debug_dict[loop_counter][s][root_bus] = []
            # find all buses that are connected to the root bus
            # first we check the from_bus column
            idx_set = np.where(bus_pairs[:, from_bus_position] == root_bus)[0]
            if idx_set.size != 0:
                for idx in idx_set:
                    if bus_pairs[idx, to_bus_position] not in network_section[s]:
                        network_section[s].append(int(bus_pairs[idx, to_bus_position]))
                        debug_dict[loop_counter][s][root_bus].append(bus_pairs[idx, to_bus_position])

                # we need to delete all rows
                # !! It is very important that do no use loop when deleting elements from arrays
                bus_pairs = np.delete(bus_pairs, idx_set, axis=0)

                # check if all buses in bus_pairs have been allocated
                if bus_pairs.size == 0:
                    search_flag = 0

            # second we check the to_bus column
            idx_set = np.where(bus_pairs[:, to_bus_position] == root_bus)[0]
            if idx_set.size != 0:
                for idx in idx_set:
                    if bus_pairs[idx, from_bus_position] not in network_section[s]:
                        network_section[s].append(int(bus_pairs[idx, from_bus_position]))
                        debug_dict[loop_counter][s][root_bus].append(bus_pairs[idx, from_bus_position])

                # we need to delete all rows
                # !! It is very important that do no use loop when deleting elements from arrays
                bus_pairs = np.delete(bus_pairs, idx_set, axis=0)

                # check if all buses in bus_pairs have been allocated
                if bus_pairs.size == 0:
                    search_flag = 0
    loop_counter = loop_counter + 1
    print(bus_pairs.size)

with open('network_section.json', 'w') as fp:
    json.dump(network_section, fp)