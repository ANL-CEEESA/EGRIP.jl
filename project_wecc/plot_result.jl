using PyPlot
using CSV
cd(@__DIR__)
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


# print(string(pwd()))

# # ---------------- read data ---------------------
# res_path = "results_sec_1_gap100"
# res_path = "results_sec_2_gap100"
res_path = "results"

pg = CSV.read(string(res_path, "/", "res_pg.csv"))
pl = CSV.read(string(res_path, "/", "res_pl.csv"))

step_all = 1:(size(pg)[2] - 2);

# calculate load trajectory
pl_step = []
for t in step_all
    push!(pl_step, sum(pl[:,t]))
end
pg_step = []
for t in step_all
    push!(pg_step, sum(pg[:,t]))
end

# ---------------- plotting ------------------
fig, ax = PyPlot.subplots(figsize=(8, 5))
ax.plot(step_all, pg_step,  "b*-", linewidth=2, markersize=4, label="Gen")
ax.plot(step_all, pl_step,  "rs-.", linewidth=2, markersize=4, label="Load")
ax.legend(loc="upper left", fontsize=16)
# ax.set_title("Load Trajectories", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_tick_params(labelsize=16)
ax.yaxis.set_tick_params(labelsize=16)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
PyPlot.savefig(string(res_path, "/", "res_1.png"))


# fig, ax = PyPlot.subplots(figsize=(8, 5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=4,
#                 label=label_list[i])
# end
# ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>16))
# ax.legend(loc="lower right", fontsize=10)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
# ax.xaxis.set_tick_params(labelsize=16)
# ax.yaxis.set_tick_params(labelsize=16)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, fig_name)
# PyPlot.savefig(sav_dict)
