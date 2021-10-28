
# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# To load EGRIP, we have two following options. Currently we use the first one
# ------- Option 1: add EGRIP to the Julia LOAD_PATH.---------
push!(LOAD_PATH,"../src/")
using EGRIP
# ---------- Option 2: we use EGRIP as a module.--------------
# include("../src/EGRIP.jl")
# using .EGRIP

# ----------------- registered packages----------------
using PowerModels
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
using Interpolations
using Distributions
using DataStructures
using Gurobi
using LinearAlgebra
using Random

# ===================================== local functions =====================================
include("proj_utils.jl")

# # ===================================== Load data =====================================
dir_case_network = "../GMLC_test_case/rts-gmlc-gic_ver1.raw"
dir_case_component_status = "../GMLC_test_case/rts_gmlc_gic_mods_PT.json"
network_data_format = "psse"
dir_case_result = "results_load_pickup/"
t_final = 22
t_step = 1
gap = 0.1
stages = 1:t_step:t_final
# define load pickup priority
ref = EGRIP.load_network(dir_case_network, network_data_format)

load_priority = Dict()
for (i,item) in ref[:load]
    load_priority[i] = rand((1,2,3,4,5))  # randomly select from (1,2,3,4,5)
end

open(string("load_pickup_priority.json"), "w") do f
    JSON.print(f, load_priority)
end

# test loading
load_priority_1 = Dict()
load_priority_1 = JSON.parsefile("load_pickup_priority.json")  # parse and transform data
for (i,item) in ref[:load]
    println(load_priority_1[string(i)]) 
end
