import pandas as pd
import numpy as np
import csv

data_bus = pd.read_csv("WECC_Bus_all.csv", encoding="ISO-8859-1")

num_bus = data_bus.shape[0]
for l in range(num_bus):
    print(l)
    # clear unit name
    data_bus["BusName"][l] = data_bus["BusName"][l].split("-")[1]
    data_bus["BusNumber"][l] = data_bus["BusNumber"][l] - 1

data_bus.to_csv("WECC_Bus_all.csv", encoding="ISO-8859-1")
