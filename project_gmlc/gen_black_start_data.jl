
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
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
using Interpolations
using Distributions
using DataStructures
using PowerModels
# ---------------- local functions ---------------
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "../GMLC_test_case/rts-gmlc-gic.raw"

network_data_format = "psse"

# load network data
data0 = PowerModels.parse_file(dir_case_network)
ref = PowerModels.build_ref(data0)[:it][:pm][:nw][0]
# ref = load_network(dir_case_network, network_data_format)

println("-------reading gen_key----------")
gen_keyset = keys(sort!(OrderedDict(ref[:gen])))
println(gen_keyset)

println("-------reading bus_key----------")
bus_keyset = keys(sort!(OrderedDict(ref[:bus])))
println(bus_keyset)

gen_key = []
gen_bus = []
gen_cranking_power_MW = []
gen_cranking_time_min = []
gen_ramp_rate_MW_min = []
gen_black_start = []
for i in gen_keyset
    push!(gen_key, i)
    push!(gen_bus, ref[:gen][i]["gen_bus"])
    push!(gen_cranking_power_MW, ref[:gen][i]["pmax"]*ref[:gen][i]["mbase"]*0.01)
    push!(gen_cranking_time_min, 30)
    push!(gen_ramp_rate_MW_min, ref[:gen][i]["pmax"]*ref[:gen][i]["mbase"]*0.05)
    push!(gen_black_start, 0)
end
gen_key = sort!(gen_key)
gen_bus = sort!(gen_bus)

df = DataFrame(Gen_Key = gen_key, Gen_Bus = gen_bus,
        Gen_Cranking_Power_MW = gen_cranking_power_MW,
        Gen_Cranking_Time_min = gen_cranking_time_min,
            Gen_Ramp_Rate_MW_min = gen_ramp_rate_MW_min,
            Gen_Black_Start = gen_black_start)
CSV.write("gen_black_start_data.csv", df)
