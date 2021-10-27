
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
t_final = 500
t_step = 100
gap = 0.1
time_step = 100

# load component status data
# In the original file, generator 66 is not specified.
component_status = Dict()
component_status = JSON.parsefile("../GMLC_test_case/rts_gmlc_gic_mods_PT.json")

# load network data
data0 = PowerModels.parse_file(dir_case_network)
ref = PowerModels.build_ref(data0)[:it][:pm][:nw][0]
size(ref[:bus_gens][1069], 1) == 0


# =====================================set model=====================================
model = Model(Gurobi.Optimizer)
set_optimizer_attribute(model, "MIPGap", gap)

# make stages
#TODO: maybe read the outage data and determine the maximum days to be considered
stages = 1:30 # here the unit is day

# =====================================Define decision variable =====================================
println("Defining restoration variables")
# define generator variables
model = EGRIP.def_var_gen(model, ref, stages; form=4)
# define load variable
model = EGRIP.def_var_load(model, ref, stages; form=4)
# define flow variable
model = EGRIP.def_var_flow(model, ref, stages)
println("Complete defining restoration variables")


# ===================================== load damage data =====================================
#TODO: assign generator availiability (y) constraints based on the data
for gen_key in keys(component_status["gen"])
    for t in 1:component_status["gen"][gen_key]["repair_time_days"]
        @constraint(model, model[:y][parse(Int, gen_key), t] == 0)
    end
end

for bus_key in keys(component_status["bus"])
    for t in 1:component_status["bus"][bus_key]["repair_time_days"]
        @constraint(model, model[:u][parse(Int, bus_key), t] == 0)
    end
end

for branch_key in keys(component_status["branch"])
    from_bus = component_status["branch"][branch_key]["source_id"][2]
    to_bus = component_status["branch"][branch_key]["source_id"][3]
    for t in 1:component_status["branch"][branch_key]["repair_time_days"]
        @constraint(model, model[:x][(from_bus, to_bus), t] == 0)
    end
end

# ===================================== generator constraints =====================================

# power limits associated with the generator status
for t in stages
    for g in keys(ref[:gen])
        @constraint(model, model[:pg][g,t] >= ref[:gen][g]["pmin"] * model[:y][g,t])
        @constraint(model, model[:pg][g,t] <= ref[:gen][g]["pmax"] * model[:y][g,t])
        @constraint(model, model[:qg][g,t] >= ref[:gen][g]["qmin"] * model[:y][g,t])
        @constraint(model, model[:qg][g,t] <= ref[:gen][g]["qmax"] * model[:y][g,t])
    end
end

# # ===================================== network constraints =====================================

vl = model[:vl]
vb = model[:vb]
v = model[:v]
x = model[:x]
y = model[:y]
a = model[:a]
al = model[:al]
u = model[:u]
p = model[:p]
q = model[:q]
pg = model[:pg]
pl = model[:pl]
qg = model[:qg]
ql = model[:ql]

println("Formulating nodal constraints")
for (i,j) in keys(ref[:buspairs])
    for t in stages
        # voltage constraints
        # voltage constraints are only activated if the associated line is energized
        @constraint(model, vl[(i,j),t] >= ref[:bus][i]["vmin"]*x[(i,j),t])
        @constraint(model, vl[(i,j),t] <= ref[:bus][i]["vmax"]*x[(i,j),t])
        @constraint(model, vl[(j,i),t] >= ref[:bus][j]["vmin"]*x[(i,j),t])
        @constraint(model, vl[(j,i),t] <= ref[:bus][j]["vmax"]*x[(i,j),t])
        @constraint(model, vl[(i,j),t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-x[(i,j),t]))
        @constraint(model, vl[(i,j),t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-x[(i,j),t]))
        @constraint(model, vl[(j,i),t] >= v[j,t] - ref[:bus][j]["vmax"]*(1-x[(i,j),t]))
        @constraint(model, vl[(j,i),t] <= v[j,t] - ref[:bus][j]["vmin"]*(1-x[(i,j),t]))

        # angle difference constraints
        # angle difference constraints are only activated if the associated line is energized
        @constraint(model, a[i,t] - a[j,t] >= ref[:buspairs][(i,j)]["angmin"])
        @constraint(model, a[i,t] - a[j,t] <= ref[:buspairs][(i,j)]["angmax"])
        @constraint(model, al[(i,j),t] - al[(j,i),t] >= ref[:buspairs][(i,j)]["angmin"]*x[(i,j),t])
        @constraint(model, al[(i,j),t] - al[(j,i),t] <= ref[:buspairs][(i,j)]["angmax"]*x[(i,j),t])
        @constraint(model, al[(i,j),t] - al[(j,i),t] >= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmax"]*(1-x[(i,j),t]))
        @constraint(model, al[(i,j),t] - al[(j,i),t] <= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmin"]*(1-x[(i,j),t]))

        # energized line cannot be shut down
        if t > 1
            @constraint(model, x[(i,j), t] >= x[(i,j), t-1])
        end

        # line energization rules
        @constraint(model, u[i,t] + u[j,t] >= x[(i,j),t])

    end
end


# nodal (bus) constraints
for (i, bus) in ref[:bus]  # loop its keys and entries

    for t in stages
        bus_shunts = [ref[:shunt][s] for s in ref[:bus_shunts][i]]

        @constraint(model, vb[i,t] >= ref[:bus][i]["vmin"]*u[i,t])
        @constraint(model, vb[i,t] <= ref[:bus][i]["vmax"]*u[i,t])
        @constraint(model, vb[i,t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-u[i,t]))
        @constraint(model, vb[i,t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-u[i,t]))

        # u_i >= y_i & u_{i,t} >= u_{i,t-1}
        # for g in ref[:bus_gens][i]
        #     @constraint(model, u[i,t] == y[g,t])  # bus on == generator on
        # end

        if size(ref[:bus_gens][i],1) > 0
            g = ref[:bus_gens][i][1]
            @constraint(model, u[i,t] == y[g,t])
        end

        # Bus KCL
        # Nodal power balance constraint
        @constraint(model, sum(p[a,t] for a in ref[:bus_arcs][i]) ==
            sum(pg[g,t] for g in ref[:bus_gens][i]) -
            sum(pl[l,t] for l in ref[:bus_loads][i]) -
            sum(shunt["gs"] for shunt in bus_shunts)*(2*vb[i,t] - u[i,t]))
        @constraint(model, sum(q[a,t] for a in ref[:bus_arcs][i]) ==
            sum(qg[g,t] for g in ref[:bus_gens][i]) -
            sum(ql[l,t] for l in ref[:bus_loads][i]) +
            sum(shunt["bs"] for shunt in bus_shunts)*(2*vb[i,t] - u[i,t]))

    end
end


vl = model[:vl]
al = model[:al]
x = model[:x]
u = model[:u]
p = model[:p]
q = model[:q]

println("Formulating branch constraints")
for (i, branch) in ref[:branch]
    for t in stages
        # create indices for variables
        f_idx = (i, branch["f_bus"], branch["t_bus"])
        t_idx = (i, branch["t_bus"], branch["f_bus"])
        bpf_idx = (branch["f_bus"], branch["t_bus"])
        bpt_idx = (branch["t_bus"], branch["f_bus"])
        # get indexed power flow
        p_fr = p[f_idx,t]
        q_fr = q[f_idx,t]
        p_to = p[t_idx,t]
        q_to = q[t_idx,t]
        # get indexed voltage
        v_fr = vl[bpf_idx,t]
        v_to = vl[bpt_idx,t]
        c_br = vl[bpf_idx,t] + vl[bpt_idx,t] - x[bpf_idx,t]
        s_br = al[bpt_idx,t] - al[bpf_idx,t]
        u_fr = u[branch["f_bus"],t]
        u_to = u[branch["t_bus"],t]

        # get line parameters
        ybus = pinv(branch["br_r"] + im * branch["br_x"])
        g, b = real(ybus), imag(ybus)
        g_fr = branch["g_fr"]
        b_fr = branch["b_fr"]
        g_to = branch["g_to"]
        b_to = branch["b_to"]
        # tap changer related computation
        tap_ratio = branch["tap"]
        angle_shift = branch["shift"]
        tr, ti = tap_ratio * cos(angle_shift), tap_ratio * sin(angle_shift)
        tm = tap_ratio^2

        # AC Line Flow Constraints
        @constraint(model, p_fr ==  (g+g_fr)/tm*(2*v_fr-x[bpf_idx,t]) + (-g*tr+b*ti)/tm*c_br + (-b*tr-g*ti)/tm*s_br)
        @constraint(model, q_fr == -(b+b_fr)/tm*(2*v_fr-x[bpf_idx,t]) - (-b*tr-g*ti)/tm*c_br + (-g*tr+b*ti)/tm*s_br)

        @constraint(model, p_to ==  (g+g_to)*(2*v_to-x[bpf_idx,t]) + (-g*tr-b*ti)/tm*c_br + (-b*tr+g*ti)/tm*(-s_br) )
        @constraint(model, q_to == -(b+b_to)*(2*v_to-x[bpf_idx,t]) - (-b*tr+g*ti)/tm*c_br + (-g*tr-b*ti)/tm*(-s_br) )
    end
end


# ===================================== load constraints =====================================
for t in stages
    for l in keys(ref[:load])
        # active power load
        if ref[:load][l]["pd"] >= 0  # The current bus has positive active power load
            @constraint(model, model[:pl][l,t] >= 0)
            @constraint(model, model[:pl][l,t] <= ref[:load][l]["pd"] * model[:u][ref[:load][l]["load_bus"],t])
        else
            @constraint(model, model[:pl][l,t] <= 0) # The current bus has negative active power load
            @constraint(model, model[:pl][l,t] >= ref[:load][l]["pd"] * model[:u][ref[:load][l]["load_bus"],t])
        end

        # reactive power load
        if ref[:load][l]["qd"] >= 0
            @constraint(model, model[:ql][l,t] >= 0)
            @constraint(model, model[:ql][l,t] <= ref[:load][l]["qd"] * model[:u][ref[:load][l]["load_bus"],t])
        else
            @constraint(model, model[:ql][l,t] <= 0)
            @constraint(model, model[:ql][l,t] >= ref[:load][l]["qd"] * model[:u][ref[:load][l]["load_bus"],t])
        end
    end
end


# =====================================Objective=====================================
@objective(model, Max, sum(sum(model[:pl][d, t] for d in keys(ref[:load])) for t in stages))

optimize!(model)
status = termination_status(model)
println("")
println("Termination status: ", status)
println("The objective value is: ", objective_value(model))


# ===================================== solution =====================================
Pl_seq = Dict()
Pl_seq = get_value(model[:pl])
ordered_Pl_seq = sort!(OrderedDict(Pl_seq)) # order the dict based on the key
ordered_P_total_seq = []
for t in stages
    push!(ordered_P_total_seq, sum(Pl_seq[d][t] for d in keys(ref[:load])))
end
sav_dict_csv = string(pwd(), "/", dir_case_result, "load_status.csv")
CSV.write(sav_dict_csv, ordered_Pl_seq)

Pl_seq_status = Dict()
for d in keys(sort!(OrderedDict(ref[:load])))
    Pl_seq_status[d] = []
    for t in stages
        if abs(Pl_seq[d][t]) <= 0.005
            push!(Pl_seq_status[d], 0)
        elseif (abs(Pl_seq[d][t]) >= 0.005) && abs(Pl_seq[d][t] - ref[:load][d]["pd"]) >= 0.005
            push!(Pl_seq_status[d], 1)
        elseif abs(Pl_seq[d][t] - ref[:load][d]["pd"]) <= 0.005
            push!(Pl_seq_status[d], 2)
        end
    end
end


# write the results into csv
resultfile = open(string(dir_case_result, "load_value.csv"), "w")
print(resultfile, "Load Index, Load Bus,")
for t in stages
    if t < stages[end]
        print(resultfile, t)
        print(resultfile, ", ")
    else
        println(resultfile, t)
    end
end
for (i, entry) in sort!(OrderedDict(ref[:load]))
            print(resultfile, i)
            print(resultfile, ", ")
            print(resultfile, entry["load_bus"])
            print(resultfile, ", ")
            for t in stages
                if t < stages[end]
                    print(resultfile, value(model[:pl][i, t]))
                    print(resultfile, ", ")
                else
                    # Determine which stages should the current time instant be
                    print(resultfile, value(model[:pl][i, t]))
                end
            end
        println(resultfile, " ")
end
close(resultfile)


# write the results into csv
resultfile = open(string(dir_case_result, "load_status.csv"), "w")
print(resultfile, "Load Index, Load Bus,")
for t in stages
    if t < stages[end]
        print(resultfile, t)
        print(resultfile, ", ")
    else
        println(resultfile, t)
    end
end
for (i, entry) in sort!(OrderedDict(ref[:load]))
            print(resultfile, i)
            print(resultfile, ", ")
            print(resultfile, entry["load_bus"])
            print(resultfile, ", ")
            for t in stages
                if t < stages[end]
                    print(resultfile, Pl_seq_status[i][t])
                    print(resultfile, ", ")
                else
                    # Determine which stages should the current time instant be
                    print(resultfile, Pl_seq_status[i][t])
                end
            end
        println(resultfile, " ")
end
close(resultfile)



# verify total load
total_load = sum(ref[:load][d]["pd"] for d in keys(ref[:load]))
println("The total load of the system is: ", total_load)

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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_gen.png")
PyPlot.savefig(sav_dict)
