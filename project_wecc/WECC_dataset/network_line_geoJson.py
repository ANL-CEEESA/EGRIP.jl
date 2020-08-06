import pandas as pd
import numpy as np
import csv

data_bus = pd.read_csv("WECC_Bus_all.csv", encoding="ISO-8859-1")
data_trans = pd.read_csv("WECC_Trans.csv", encoding="ISO-8859-1")

num_br = data_trans.shape[0]
for l in range(num_br):
    print(l)
    # get from bus idx
    f_bus = data_trans["from_bus"][l]
    # get bus index in data_bus
    idx_bus = f_bus - 1
    data_trans["Latitude_from_bus"][l] = data_bus["Latitude"][idx_bus]
    data_trans["Longitude_from_bus"][l] = data_bus["Longitude"][idx_bus]

    # get from bus idx
    t_bus = data_trans["to_bus"][l]
    # get bus index in data_bus
    idx_bus = t_bus - 1
    data_trans["Latitude_to_bus"][l] = data_bus["Latitude"][idx_bus]
    data_trans["Longitude_to_bus"][l] = data_bus["Longitude"][idx_bus]

data_trans.to_csv("WECC_Trans.csv", encoding="ISO-8859-1")


# data_line = pd.read_csv("WECC_Line.csv", encoding="ISO-8859-1")
# num_br = data_line.shape[0]
# the template. where data from the csv will be formatted to geojson
template = \
   ''' \
   { "type" : "Feature",
       "geometry" : {
           "type" : "LineString",
           "coordinates" : [[%s, %s],[%s, %s]]},
       "properties" : { "from_bus" : %s, "to_bus": %s}
       },
   '''


# the head of the geojson file
output = \
   ''' \

{ "type" : "FeatureCollection",
   "features" : [
   '''


# loop through the csv by row skipping the first
for l in range(num_br):
   # iter += 1
   # if iter >= 2:
   Longitude_from_bus = data_trans["Longitude_from_bus"][l]
   Latitude_from_bus = data_trans["Latitude_from_bus"][l]
   Longitude_to_bus = data_trans["Longitude_to_bus"][l]
   Latitude_to_bus = data_trans["Latitude_to_bus"][l]
   from_bus = data_trans["from_bus"][l]
   to_bus = data_trans["to_bus"][l]
   # output += template % (row[0], row[2], row[1], row[3], row[4])
   output += template % (Longitude_from_bus, Latitude_from_bus, Longitude_to_bus, Latitude_to_bus, from_bus, to_bus)

# the tail of the geojson file
output += \
   ''' \
   ]

}
   '''


# opens an geoJSON file to write the output
outFileHandle = open("WECC_Trans.geojson", "w")
outFileHandle.write(output)
outFileHandle.close()