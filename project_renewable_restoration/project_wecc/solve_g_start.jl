
# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JSON
using CSV
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP
using JuMP

function get_value(model, stages, ref, Pcr, Krp)
    Pg = Dict()
    for g in keys(ref[:gen])
        Pg[g] = []
        for t in stages
            current_pg = value(model[:yc][g,t]) * (-Pcr[g]) + sum(value(model[:yr][g,i]) * Krp[g] for i in 1:t)
            push!(Pg[g], current_pg)
        end
    end

    
    Pg_seq = []
    for t in stages
        push!(Pg_seq, value(model[:pg_total][t]))
    end

    Pd_seq = []
    for t in stages
        push!(Pd_seq, value(model[:pd_total][t]))
    end

    return Pg_seq, Pd_seq, Pg

end

function check_load(ref)
    for k in keys(ref[:load])
        if ref[:load][k]["pd"] <= 0
            println("Load bus: ", ref[:load][k]["load_bus"], ", active power: ", ref[:load][k]["pd"])
        end
    end
end


# # ------------ Interactive --------------
dir_case_network = "WECC_dataset/WECC_noHVDC.raw"
dir_case_blackstart = "WECC_dataset/WECC_generator_specs.csv"
network_data_format = "psse"
dir_case_result = "results_startup/"
t_final = 300
t_step = 10
gap = 0.05
nstage = t_final/t_step;
stages = 1:nstage;
ref, model, Pcr, Tcr, Krp, Trp = solve_startup(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap, Dict("activation"=>0))

for i in keys(ref)
    println(i)
end

# # ---------------- calculate total load ---------------------
total_gen = sum(ref[:gen][i]["pg"] for i in keys(ref[:gen])) * ref[:baseMVA]
total_load = sum(ref[:load][i]["pd"] for i in keys(ref[:load])) * ref[:baseMVA]
println("Total generator: ", total_gen)
println("Total load: ", total_load)


# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]


# --------- retrieve results ---------
Pg_seq, Pd_seq, Pg = get_value(model, stages, ref, Pcr, Krp)


# plot
using PyPlot
fig_name = "fig_gen_startup.png"
# If true, return Python-based GUI; otherwise, return Julia backend
PyPlot.pygui(true)
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(8, 5))
ax.plot(t_step:t_step:t_final, (Pg_seq)*100,
                color=line_colors[1],
                linestyle = line_style[1],
                marker=line_markers[1],
                linewidth=2,
                markersize=4,
                label="Total generation capacity")
ax.plot(t_step:t_step:t_final, (Pd_seq)*100,
                color=line_colors[2],
                linestyle = line_style[2],
                marker=line_markers[2],
                linewidth=2,
                markersize=4,
                label="Restored load")
ax.set_title("System Capacity Requirement", fontdict=Dict("fontsize"=>16))
ax.legend(loc="lower right", fontsize=16)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_tick_params(labelsize=16)
ax.yaxis.set_tick_params(labelsize=16)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, fig_name)
PyPlot.savefig(sav_dict)




fig_name = "fig_gen_startup_all_gen.png"
# If true, return Python-based GUI; otherwise, return Julia backend
PyPlot.pygui(true)
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(8, 5))
for g in keys(ref[:gen])
    ax.plot(t_step:t_step:t_final,Pg[g]*100)
end
ax.set_title("Generator Capacity Curve", fontdict=Dict("fontsize"=>16))
ax.legend(loc="lower right", fontsize=16)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_tick_params(labelsize=16)
ax.yaxis.set_tick_params(labelsize=16)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, fig_name)
PyPlot.savefig(sav_dict)


# for g in keys(ref[:gen])
#     fig_name = string("fig_gen_startup_gen_", g, ".png")
#     # If true, return Python-based GUI; otherwise, return Julia backend
#     PyPlot.pygui(true)
#     rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
#     rcParams["font.family"] = "Arial"
#     fig, ax = PyPlot.subplots(figsize=(8, 5))
#     ax.plot(t_step:t_step:t_final,Pg[g]*100)
#     ax.set_title(string("Restoration Trajectory", g), fontdict=Dict("fontsize"=>16))
#     ax.legend(loc="lower right", fontsize=10)
#     ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
#     ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
#     ax.xaxis.set_tick_params(labelsize=16)
#     ax.yaxis.set_tick_params(labelsize=16)
#     fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
#     PyPlot.show()
#     sav_dict = string(pwd(), "/", dir_case_result, fig_name)
#     PyPlot.savefig(sav_dict)
# end


println("  ")
println("Cranking power: ", Pcr[22])
println("Ramping time: ", Trp[22])
println("Ramping rate: ", Krp[22])
println("Pmax: ", ref[:gen][22]["pmax"])



