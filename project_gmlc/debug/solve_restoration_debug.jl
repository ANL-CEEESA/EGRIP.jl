
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

# ---------------- local functions ---------------
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "../GMLC_test_case/rts-gmlc-gic.raw"
dir_case_blackstart = "gen_black_start_data.csv"
network_data_format = "psse"
dir_case_result = "results/"
t_final = 500
t_step = 100
gap = 0.1

time_step = 100

# load network data
data0 = PowerModels.parse_file(dir_case_network)
ref = PowerModels.build_ref(data0)[:it][:pm][:nw][0]
size(ref[:bus_gens][1069], 1) == 0

bs_data = CSV.read(dir_case_blackstart, DataFrame)
# Define dictionary
Pcr = Dict()
Tcr = Dict()
Krp = Dict()

for g in keys(ref[:gen])
    index = findall(x->x==g,bs_data[:,1])
    # cranking power: power needed for the unit to be normally functional, unit converted into pu
    Pcr[g] = bs_data[index,3] / ref[:baseMVA]
    # cranking time: time needed for the unit to be normally functional
    Tcr[g] = bs_data[index,4]  # in minutes
    # ramping rate: the unit in BS data is MW/min and converted into pu/min
    Krp[g] = bs_data[index,5] / ref[:baseMVA]   # originally in minutes/MW and now in minutes/pu
end

# Adjust generator data based on time step from minute to per time step
for g in keys(ref[:gen])
    Tcr[g] = ceil(Tcr[g][1] / time_step) # cranking time: time needed for the unit to be normally functional
    Krp[g] = Krp[g] * time_step # ramping rate in pu/each step
end



# ref, model = solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)


# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Wind",
              "Prob 0.05",
              "Prob 0.10",
              "Prob 0.15",
              "Prob 0.20"]


# ===============================plotting ======================================
# # -----------------------------------generator power----------------------------
# using PyPlot
# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("Generator Capacity", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_gen_wecc.png")
# PyPlot.savefig(sav_dict)

# # ---------------------------------------load power------------------------------
# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(12,5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_load_wecc.png")
# PyPlot.savefig(sav_dict)


# # ------------------- save data into json --------------------
# using JSON
# json_string = JSON.json(Pw_seq)
# open("results_startup/data_gen_startup_real_data_wind.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pg_seq)
# open("results_startup/data_gen_startup_real_data_gen.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pd_seq)
# open("results_startup/data_gen_startup_real_data_load.json","w") do f
#   JSON.print(f, json_string)
# end
