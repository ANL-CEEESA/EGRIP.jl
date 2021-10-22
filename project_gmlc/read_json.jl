
# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
using JSON
using CSV


repair_data = Dict()
repair_data = JSON.parsefile("../GMLC_test_case/rts_gmlc_gic_mods_PT.json")
