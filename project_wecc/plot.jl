using PyPlot
using CSV
cd(@__DIR__)
push!(LOAD_PATH,"../src/")
using EGRIP

# ----------------- plotting setup -------------
# If true, return Python-based GUI; otherwise, return Julia backend
PyPlot.pygui(true)
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Renewable", "W Renewable: Sample 1000, Prob 0.05",
                            "W Renewable: Sample 1000, Prob 0.10",
                            "W Renewable: Sample 1000, Prob 0.15",
                            "W Renewable: Sample 1000, Prob 0.20"]


# ---------------- network ---------------------
ref = load_network("WECC_dataset/WECC_noHVDC.raw", "psse")
Pcr, Tcr, Krp = load_gen("WECC_dataset/WECC_generator_specs.csv", ref, 100)


# # ---------------- read data ---------------------
# res_path = "results_sec_N"
# res_path = "results_sec_2_gap100"
res_path = "results_no_pf"

pg = CSV.read(string(res_path, "/", "res_pg.csv"))
pl = CSV.read(string(res_path, "/", "res_pl.csv"))

step_all = 1:(size(pg)[2] - 2);

# calculate load trajectory
pl_step = []
for t in step_all
    push!(pl_step, sum(pl[:,t+2]))
end
pg_step = []
for t in step_all
    push!(pg_step, sum(pg[:,t+2]))
end

println(pl[:,2])
println(findall(x->x==109, pl[:,2]))

# # ---------------- calculate gen and load ---------------------
p_gen = Dict()
for i in keys(ref[:gen])
    gen_bus = ref[:gen][i]["gen_bus"]
    idx = findall(x->x==gen_bus, pg[:,2])
    p_gen[i] = ref[:gen][i]["pg"]
    println("Generator Bus: ", gen_bus, "   Rated Power: ", round(ref[:gen][i]["pg"]), "   Max Power: ", round(ref[:gen][i]["pmax"]), "   Ramp Rate: ", round(Krp[i]), "   Cranking Time: ", round(Tcr[i]), "   Current Power: ", round(pg[idx, 6][1] / ref[:baseMVA]))
end
sum(p_gen[k] for k in keys(p_gen))

p_load = Dict()
for i in keys(ref[:load])
    load_bus = ref[:load][i]["load_bus"]
    idx = findall(x->x==load_bus, pl[:,2])
    p_load[i] = ref[:load][i]["pd"]
    println("Load Bus: ", load_bus, "   Rated Power: ", ref[:load][i]["pd"], "   Current Power: ", pl[idx, 6][1] / ref[:baseMVA])
end
sum(p_load[k] for k in keys(p_load))

# ---------------- plotting ------------------
fig, ax = PyPlot.subplots(figsize=(8, 5))
ax.plot(step_all, pg_step,  "b*-", linewidth=2, markersize=4, label="Gen")
ax.plot(step_all, pl_step,  "rs-.", linewidth=2, markersize=4, label="Load")
ax.legend(loc="upper left", fontsize=16)
# ax.set_title("Load Trajectories", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_label_text("Stages", fontdict=Dict("fontsize"=>16))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_tick_params(labelsize=16)
ax.yaxis.set_tick_params(labelsize=16)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
PyPlot.savefig(string(res_path, "/", "res_1.png"))

println("generation at each step is ", pg_step)


# # # ---------------- calculate total load ---------------------
# total_load = sum(ref[:load][i]["pd"] for i in keys(ref[:load])) * ref[:baseMVA]
# println("  ")
# println("==================")
# println("total load is ", total_load)
# println("==================")
# println("  ")
