
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

# ===================================== local functions =====================================
include("proj_utils.jl")

# # ===================================== Load data =====================================
dir_case_network = "../GMLC_test_case/rts-gmlc-gic_ver1.raw"
dir_case_component_status = "../GMLC_test_case/rts_gmlc_gic_mods_PT.json"
network_data_format = "psse"
dir_case_result = "results_load_pickup/"
t_final = 25
t_step = 1
gap = 0.2
stages = 1:t_step:t_final
# load load pickup priority
load_priority_data = Dict()
load_priority_data = JSON.parsefile("load_pickup_priority.json")  # parse and transform data

# solve the problem
ref, model = solve_load_pickup(dir_case_network, network_data_format, dir_case_component_status, dir_case_result, t_final, t_step, gap;
                                solver="gurobi", load_priority=load_priority_data)

# verify total load
total_load = sum(ref[:load][d]["pd"] for d in keys(ref[:load]))
println("The total load of the system is: ", total_load)

# obtain results
Pl_seq = Dict()
Pl_seq = get_value(model[:pl])
ordered_Pl_seq = sort!(OrderedDict(Pl_seq)) # order the dict based on the key
ordered_P_total_seq = []
for t in stages
    push!(ordered_P_total_seq, sum(Pl_seq[d][t] for d in keys(ref[:load])))
end
# ===================================== plot ===================================
# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
# # Pyplot generic setting
using PyPlot
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"

# -------------------------- generator and load in one plot --------------------
fig, ax = PyPlot.subplots(figsize=(12, 5))
ax.plot(stages, ordered_P_total_seq*100,
            color=line_colors[1],
            linestyle = line_style[2],
            marker=line_markers[1],
            linewidth=2,
            markersize=2)
ax.set_title("System Total Load", fontdict=Dict("fontsize"=>20))
ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Time (days)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_load_pickup.png")
PyPlot.savefig(sav_dict)
