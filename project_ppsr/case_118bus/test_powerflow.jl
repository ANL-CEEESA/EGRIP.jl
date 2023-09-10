
# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../../src/")
using EGRIP
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# registered packages
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
using Interpolations
using Distributions
using Gurobi
using PowerModels
using Ipopt

# local functions
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "case118.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup_density/"
gap = 0.0

ref = load_network(dir_case_network, network_data_format)

networkdata = PowerModels.parse_file(dir_case_network)

pf_result = solve_ac_opf(networkdata, Ipopt.Optimizer)

println(pf_result)