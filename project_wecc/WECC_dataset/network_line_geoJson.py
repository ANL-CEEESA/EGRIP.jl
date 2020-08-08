import pandas as pd
import numpy as np
import csv
import json


def csv2geojson(df, name_str):
    """
    :param df: a data frame containing line data with bus coordinates
    :param name_str: GeoJson file name
    :return: no return
    """
    if type(df) == str:
        df = pd.read_csv(df, encoding="ISO-8859-1")

    # get size of the dataframe
    num = df.shape[0]

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
    for l in range(num):
        # iter += 1
        # if iter >= 2:
        Longitude_from_bus = df["Longitude_from_bus"][l]
        Latitude_from_bus = df["Latitude_from_bus"][l]
        Longitude_to_bus = df["Longitude_to_bus"][l]
        Latitude_to_bus = df["Latitude_to_bus"][l]
        from_bus = df["from_bus"][l]
        to_bus = df["to_bus"][l]
        # output += template % (row[0], row[2], row[1], row[3], row[4])
        output += template % (Longitude_from_bus, Latitude_from_bus, Longitude_to_bus, Latitude_to_bus, from_bus, to_bus)

    # the tail of the geojson file
    output += \
        ''' \
        ]
 
     }
        '''

    # opens an geoJSON file to write the output
    outFileHandle = open(name_str, "w")
    outFileHandle.write(output)
    outFileHandle.close()


# ===================== read raw transformer data and add coordinates ===========
def arc_csv(arc_list, name_str, data_bus):
    """
    :param arcs: a bus-pair list
    :param name_str: file name to be used
    :param data_bus: data frame bus data with coordinates
    :return: a dictionary with name columns: from_bus, to_bus, Latitude_from_bus, Longitude_to_bus
    """
    data_arc = pd.DataFrame(columns=['from_bus', 'Latitude_from_bus', 'Longitude_from_bus', 'to_bus', 'Latitude_to_bus', 'Longitude_to_bus'])
    for a in arc_list:
        # get from bus idx
        f_bus = a[0]
        # get bus index in data_bus
        idx_bus = f_bus - 1
        Latitude_from_bus = data_bus["Latitude"][idx_bus]
        Longitude_from_bus = data_bus["Longitude"][idx_bus]

        # get from bus idx
        t_bus = a[1]
        # get bus index in data_bus
        idx_bus = t_bus - 1
        Latitude_to_bus = data_bus["Latitude"][idx_bus]
        Longitude_to_bus = data_bus["Longitude"][idx_bus]

        data_arc = data_arc.append({'from_bus': f_bus, 'Latitude_from_bus': Latitude_from_bus,'Longitude_from_bus': Longitude_from_bus,
                                    'to_bus': t_bus, 'Latitude_to_bus': Latitude_to_bus, 'Longitude_to_bus': Longitude_to_bus}, ignore_index=True)

    data_arc.to_csv(name_str, encoding="ISO-8859-1")


# # ===================== generate sectionalized line CSV ===========
# # read bus data
# bus_data = pd.read_csv("WECC_Bus_all.csv", encoding="ISO-8859-1")
# # read southern network
# with open('sec_S.json') as f:
#   ref_S = json.load(f)
# # read northern network
# with open('sec_N.json') as f:
#   ref_N = json.load(f)
# # create arc: bus pairs using PowerModel.jl ref structure
# arc_list_S = []
# arc_list_N = []
# for arc in ref_S["arcs"]:
#     current_arc = [arc[1], arc[2]]
#     current_arc.sort()
#     if current_arc not in arc_list_S:
#         arc_list_S.append(current_arc)
# for arc in ref_N["arcs"]:
#     current_arc = [arc[1], arc[2]]
#     current_arc.sort()
#     if current_arc not in arc_list_N:
#         arc_list_N.append(current_arc)
#
# arc_csv(arc_list_S, "WECC_Arc_S.csv", bus_data)
# arc_csv(arc_list_N, "WECC_Arc_N.csv", bus_data)



# # ===================== convert line CSV to geojson ===========
# csv2geojson("WECC_Line.csv", "WECC_Line.geojson")
# csv2geojson("WECC_Trans.csv", "WECC_Trans.geojson")


# # ===================== convert sectionalized line CSV to geoJson ===========
csv2geojson("WECC_Arc_S.csv", "WECC_Arc_S.geojson")
csv2geojson("WECC_Arc_N.csv", "WECC_Arc_N.geojson")

