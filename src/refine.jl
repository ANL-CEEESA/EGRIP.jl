# # If we use fucntions from other un-registered modules, we need to declare them
# # ----------------- Load modules from un-registered modules-------------------
# # Option 1: We organize multiple scripts as a package and put include("file") in the main module
# # Option 2: We put include("file") in the scripts needed
# include("ReadMFile.jl")
# include("Form.jl")

# # relative or absolute import will depend on if the package is loaded in LOAD_PATH
# using ReadMFile
# using Form


# ----------------- Load modules from registered package----------------
# using LinearAlgebra
# using JuMP
# # using CPLEX
# # using Gurobi
# using DataFrames
# using CSV
# using JSON
# using PowerModels




# # ============================ original code ========================
# model = Model(CPLEX.Optimizer)
# set_optimizer_attribute(model, "CPX_PARAM_EPGAP", 0.05)

# #----------------- Load system data ----------------
# # Load system data in PSSE format
# # Convert data from PSSE format to MPC format (MatPower format)
# # We can employ MatPower function to do this

# # Convert data from MPC format to Julia Dict (PowerModels format)
# dir = "/home/yichen.zhang/case_39/"
# case = "case39.m"
# data0 = parse_mfile(string(dir, case))
# ref = Form.build_ref(data0)[:nw][0]


# # Count numbers and generate iterators
# ngen = 10;
# nload = 21;
# gen = 1:ngen;
# load = 1:nload;


# # Load generation data
# # Generation data will be further adjusted based on the time and resolution specifications
# dir_file = "/home/yichen.zhang/case_39/BS_generator.csv"
# bs_data = CSV.read(dir_file)

# # Pre-define array
# Tcr = Array{Float64,1}(undef, ngen)
# Pcr = Array{Float64,1}(undef, ngen)
# Krp = Array{Float64,1}(undef, ngen)

# for g in keys(ref[:gen])
#     Pcr[g] = bs_data[g,3]/100 # cranking power: power needed for the unit to be normally functional
#     Tcr[g] = bs_data[g,4] # cranking time: time needed for the unit to be normally functional
#     Krp[g] = bs_data[g,5]/100 # ramping rate
# end

# # --------------Set time and resolution specifications-----------------
# # The final time selection should be complied with restoration time requirement.
# time_final = 500; # in minutes.
# time_series = 1:time_final;

# # Choicing different time steps is the key for testing multiple resolutions
# time_step = 20;

# # calculate stages
# nstage = time_final/time_step;
# stages = 1:nstage;

# # Adjust generator data based on time step
# for g in keys(ref[:gen])
#     Tcr[g] = ceil(bs_data[g,4]/time_step) # cranking time: time needed for the unit to be normally functional
#     Krp[g] = bs_data[g,5]*time_step # ramping rate
# end


# # ------------Define decision variable ---------------------
# @variable(model, x[keys(ref[:buspairs]),stages], Bin); # status of line at time t
# @variable(model, y[keys(ref[:gen]),stages], Bin); # status of gen at time t
# @variable(model, u[keys(ref[:bus]),stages], Bin); # status of bus at time t
# @variable(model, ref[:bus][i]["vmin"] <= v[i in keys(ref[:bus]),stages]
#     <= ref[:bus][i]["vmax"]); # bus voltage with upper- and lower bounds
# @variable(model, a[keys(ref[:bus]),stages]); # bus angle

# # slack variables of voltage and angle on flow equations
# bp2 = collect(keys(ref[:buspairs]))
# for k in keys(ref[:buspairs])
#     i,j = k
#     push!(bp2, (j,i))
# end
# @variable(model, vl[bp2,stages]) # V_i^j
# @variable(model, al[bp2,stages]) # theta_i^j
# @variable(model, vb[keys(ref[:bus]),stages])

# # load variable
# @variable(model, pl[keys(ref[:load]),stages])
# @variable(model, ql[keys(ref[:load]),stages])

# # generation variable
# @variable(model, pg[keys(ref[:gen]),stages])
# @variable(model, qg[keys(ref[:gen]),stages])

# # line flow with the index rule (branch, from_bus, to_bus)
# # Note that we can only measure the line flow at the bus terminal
# @variable(model, -ref[:branch][l]["rate_a"] <= p[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])
# @variable(model, -ref[:branch][l]["rate_a"] <= q[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])


# # ------------------ Define contraints ---------------------
# # nodal (bus) constraints: voltage and angle difference, generator and bus energizing logics
# for (i,j) in keys(ref[:buspairs])
#     for t in stages
#         # voltage constraints
#         # voltage constraints are only activated if the associated line is energized
#         @constraint(model, vl[(i,j),t] >= ref[:bus][i]["vmin"]*x[(i,j),t])
#         @constraint(model, vl[(i,j),t] <= ref[:bus][i]["vmax"]*x[(i,j),t])
#         @constraint(model, vl[(j,i),t] >= ref[:bus][j]["vmin"]*x[(i,j),t])
#         @constraint(model, vl[(j,i),t] <= ref[:bus][j]["vmax"]*x[(i,j),t])
#         @constraint(model, vl[(i,j),t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-x[(i,j),t]))
#         @constraint(model, vl[(i,j),t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-x[(i,j),t]))
#         @constraint(model, vl[(j,i),t] >= v[j,t] - ref[:bus][j]["vmax"]*(1-x[(i,j),t]))
#         @constraint(model, vl[(j,i),t] <= v[j,t] - ref[:bus][j]["vmin"]*(1-x[(i,j),t]))

#         # angle difference constraints
#         # angle difference constraints are only activated if the associated line is energized
#         @constraint(model, a[i,t] - a[j,t] >= ref[:buspairs][(i,j)]["angmin"])
#         @constraint(model, a[i,t] - a[j,t] <= ref[:buspairs][(i,j)]["angmax"])
#         @constraint(model, al[(i,j),t] - al[(j,i),t] >= ref[:buspairs][(i,j)]["angmin"]*x[(i,j),t])
#         @constraint(model, al[(i,j),t] - al[(j,i),t] <= ref[:buspairs][(i,j)]["angmax"]*x[(i,j),t])
#         @constraint(model, al[(i,j),t] - al[(j,i),t] >= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmax"]*(1-x[(i,j),t]))
#         @constraint(model, al[(i,j),t] - al[(j,i),t] <= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmin"]*(1-x[(i,j),t]))

#         # on-line generator cannot be shut down
#         if t > 1
#             @constraint(model, x[(i,j), t] >= x[(i,j), t-1])
#         end

#         # bus should be energized before the connected genertor being on
#         @constraint(model, u[i,t] >= x[(i,j),t])
#         @constraint(model, u[j,t] >= x[(i,j),t])

#     end
# end


# # branch (power flow) constraints
# for (i,branch) in ref[:branch]
#     for t in stages
#         # create indices for variables
#         f_idx = (i, branch["f_bus"], branch["t_bus"])
#         t_idx = (i, branch["t_bus"], branch["f_bus"])
#         bpf_idx = (branch["f_bus"], branch["t_bus"])
#         bpt_idx = (branch["t_bus"], branch["f_bus"])
#         # get indexed power flow
#         p_fr = p[f_idx,t]
#         q_fr = q[f_idx,t]
#         p_to = p[t_idx,t]
#         q_to = q[t_idx,t]
#         # get indexed voltage
#         v_fr = vl[bpf_idx,t]
#         v_to = vl[bpt_idx,t]
#         c_br = vl[bpf_idx,t] + vl[bpt_idx,t] - x[bpf_idx,t]
#         s_br = al[bpt_idx,t] - al[bpf_idx,t]
#         u_fr = u[branch["f_bus"],t]
#         u_to = u[branch["t_bus"],t]

#         # get line parameters
#         ybus = pinv(branch["br_r"] + im * branch["br_x"])
#         g, b = real(ybus), imag(ybus)
#         g_fr = branch["g_fr"]
#         b_fr = branch["b_fr"]
#         g_to = branch["g_to"]
#         b_to = branch["b_to"]
#         # tap changer related computation
#         tap_ratio = branch["tap"]
#         angle_shift = branch["shift"]
#         tr, ti = tap_ratio * cos(angle_shift), tap_ratio * sin(angle_shift)
#         tm = tap_ratio^2

#         ###### TEST ######
#         # tr = 1; ti = 0; tm = 1
#         # g_fr = 0
#         # b_fr = 0
#         # g_to = 0
#         # b_to = 0

#         # AC Line Flow Constraints
#         @constraint(model, p_fr ==  (g+g_fr)/tm*(2*v_fr-x[bpf_idx,t]) + (-g*tr+b*ti)/tm*c_br + (-b*tr-g*ti)/tm*s_br)
#         @constraint(model, q_fr == -(b+b_fr)/tm*(2*v_fr-x[bpf_idx,t]) - (-b*tr-g*ti)/tm*c_br + (-g*tr+b*ti)/tm*s_br)

#         @constraint(model, p_to ==  (g+g_to)*(2*v_to-x[bpf_idx,t]) + (-g*tr-b*ti)/tm*c_br + (-b*tr+g*ti)/tm*(-s_br) )
#         @constraint(model, q_to == -(b+b_to)*(2*v_to-x[bpf_idx,t]) - (-b*tr+g*ti)/tm*c_br + (-g*tr-b*ti)/tm*(-s_br) )
#     end
# end

# # generator status and output constraint
# for g in keys(ref[:gen])
#     # generator ramping rate constraint
#     for t in 1:nstage-1
#         @constraint(model, pg[g,t] - pg[g,t+1] >= -Krp[g])
#         @constraint(model, pg[g,t] - pg[g,t+1] <= Krp[g])
#     end
#     # black-start unit is determined by the cranking power
#     if Pcr[g] == 0
#         for t in stages
#             @constraint(model, y[g,t] == 1)
#         end
#     else
#         for t in 1:nstage-1
#             @constraint(model, y[g,t] <= y[g,t+1]) # on-line generators cannot be shut down
#         end
#     end
# end


# # generator cranking constraint
# # This part is the key feature of black start. The logic is as follows:
# # Once a non-black start generator is on, that is, y[g]=1, then it needs to absorb the cranking power for its corresponding cranking time
# # "After" the time step that this unit satisfies its cranking constraint, its power goes to zero; and from the next time step, it becomes a dispatchable generator
# for t in stages
#     for g in keys(ref[:gen])
#         if t > Tcr[g] + 1
#             # set non-black start unit generation limits based on "generator cranking constraint"
#             # cranking constraint states if generator g has absorb the cranking power for its corresponding cranking time, it can produce power
#             # Mathematically if there exist enough 1 for y[g], then enable this generator's generating capability
#             # There will be the following scenarios
#             # (1) generator is off, then y[g,t] - y[g,t-Tcr[g]] = 0, then pg[g,t] == 0
#             # (2) generator is on but cranking time not satisfied, then y[g,t] - y[g,t-Tcr[g]] = 1, then pg[g,t] == -Pcr[g]
#             # (3) generator is on and just satisfies the cranking time, then y[g,t] - y[g,t-Tcr[g]] = 0, y[g,t-Tcr[g]-1]=0, then pg[g,t] == 0
#             # (4) generator is on and bigger than satisfies the cranking time, then y[g,t] - y[g,t-Tcr[g]] = 0, y[g,t-Tcr[g]-1]=1, then 0 <= pg[g,t] <= pg_max
#             @constraint(model, pg[g,t] >= -Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
#             @constraint(model, pg[g,t] <= ref[:gen][g]["pmax"] * y[g,t-Tcr[g]-1] - Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
#         elseif t <= Tcr[g]
#             # determine the non-black start generator power by its cranking condition
#             # with the time less than the cranking time, the generator power could only be zero or absorbing cranking power
#             @constraint(model, pg[g,t] == -Pcr[g] * y[g,t])
#         else
#             # if the unit is on from the first time instant, it satisfies the cranking constraint and its power becomes zero
#             # if not, it still absorbs the cranking power
#             @constraint(model, pg[g,t] == -Pcr[g] * (y[g,t] - y[g,1]))
#         end
#         @constraint(model, qg[g,t] >= ref[:gen][g]["qmin"]*y[g,t])
#         # @constraint(model, qg[g,t] >= -10*y[g,t])
#         @constraint(model, qg[g,t] <= ref[:gen][g]["qmax"]*y[g,t])
#     end
# end


# # load pickup constraint
# for t in stages
#     for l in keys(ref[:load])

#         # active power load
#         if ref[:load][l]["pd"] >= 0  # The current bus has positive active power load
#             @constraint(model, pl[l,t] >= 0)
#             @constraint(model, pl[l,t] <= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
#             if t > 1
#                 @constraint(model, pl[l,t] >= pl[l,t-1]) # no load shedding
#             end
#         else
#             @constraint(model, pl[l,t] <= 0) # The current bus has no positive active power load ?
#             @constraint(model, pl[l,t] >= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
#             if t > 1
#                 @constraint(model, pl[l,t] <= pl[l,t-1])
#             end
#         end

#         # fix power factors
#         if abs(ref[:load][l]["pd"]) >= exp(-8)
#             @constraint(model, ql[l,t] == pl[l,t] * ref[:load][l]["qd"] / ref[:load][l]["pd"])
#             continue
#         end

#         # reactive power load
#         if ref[:load][l]["qd"] >= 0
#             @constraint(model, ql[l,t] >= 0)
#             @constraint(model, ql[l,t] <= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
#             if t > 1
#                 @constraint(model, ql[l,t] >= ql[l,t-1])
#             end
#         else
#             @constraint(model, ql[l,t] <= 0)
#             @constraint(model, ql[l,t] >= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
#             if t > 1
#                 @constraint(model, ql[l,t] <= ql[l,t-1])
#             end
#         end
#     end
# end


# #------------------- Define objectives--------------------
# # @objective(model, Min, sum( sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages ) + sum( sum(t*z[l,t] for l in keys(ref[:load])) for t in stages ) )
# # @objective(model, Min, sum( sum(-pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] >= 0)
# #         + sum(pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] < 0) for t in stages ) )
# # @objective(model, Min, sum(10*sum(1 - y[g,t] for g in keys(ref[:gen])) + sum(x[a,t] for a in keys(ref[:buspairs])) for t in stages) )
# @objective(model, Min, sum(sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages) )

# println("Formulation completed")


#--------------- Additional status constraints to implement the multi-resolution idea ---------------------
# General idea is described as follows:
# Example: y(low resolution): |  stage 1 = 0    | |   stage 2 = 0   | |   stage 3 =1  |
# Example: y (Interpolate):   0, 0, 0, 0, 0,  0,    x, x, x, x,  x,    1, 1, 1, 1, 1...


# # Read time series data
# dir_file = "/home/yichen.zhang/case_39/Interpol_y.csv";
# Interpol_y = CSV.read(dir_file);
# dir_file = "/home/yichen.zhang/case_39/Interpol_u.csv";
# Interpol_u = CSV.read(dir_file);


# # Fix generator black start sequence based on lower resolution results
# for g in keys(ref[:gen])
#     # find the index of the dataframe where generator g is located
#     g_index = findall(x->x==g, Interpol_y[:,1]);
#     for t in stages
#         # Determine the slice of the time series data
#         t_s = Int((t-1)*time_step+1+2) : Int(t*time_step+2); # add 2 because the first two columns are gen bus and gen index

#         # Check the status of the sliced time series data
#         # If the current time series data contain 0, fix to zero
#         if (0 in Interpol_y[g_index[1], t_s])
#             @constraint(model, y[g,t] == 0)

#         # If the current time series data does not contain 0 but contain 2, do nothing
#         elseif !(0 in Interpol_y[g_index[1], t_s]) & (2 in Interpol_y[g_index[1], t_s])

#         # If the current time series data is all 1, fix to one
#         elseif sum(convert(Array,Interpol_y[g_index[1], t_s]))==size(Interpol_y[g_index[1], t_s])[1]
#                 @constraint(model, y[g,t] == 1)
#         # Should be no other cases
#         else
#             println("Should not happen!!!!")
#             println(g)
#             println(t_s)
#         end

#     end
# end
# println("Heuristic completed")


# #------------- Build and solve model----------------
# status = optimize!(model)
# println("The objective value is: ", getobjectivevalue(model))


# # ------------------------ results in stages -----------------------
# println("")
# adj_matrix = zeros(length(ref[:bus]), length(ref[:bus]))
# println("Line energization: ")
# for t in stages
#     print("stage ", t, ": ")
#     for (i,j) in keys(ref[:buspairs])
#         if abs(getvalue(x[(i,j),t]) - 1) < 1e-6 && adj_matrix[i,j] == 0
#             print("(", i, ",", j, ") ")
#             adj_matrix[i,j] = 1
#         end
#     end
#     println("")
# end
# println("")
# println("Generator energization: ")
# for t in stages
#     print("stage ", t, ": ")
#     for g in keys(ref[:gen])
#         if (abs(getvalue(y[g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(getvalue(y[g,t-1]) + getvalue(y[g,t]) - 1) < 1e-6)
#             print(ref[:gen][g]["gen_bus"], " ")
#         end
#     end
#     println("")
# end
# println("")
# println("Bus energization: ")
# for t in stages
#     print("stage ", t, ": ")
#     for b in keys(ref[:bus])
#         if (abs(getvalue(u[b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(getvalue(u[b,t-1]) + getvalue(u[b,t]) - 1) < 1e-6)
#             print(b, " ")
#         end
#     end
#     println("")
# end

# # ------------------ Write generator active power dispatch solution----------------------
# resultfile = open(string(dir, "res_pg.csv"), "w")
# print(resultfile, "Gen Index, Gen Bus,")
# for t in stages
#     if t<nstage
#         print(resultfile, t)
#         print(resultfile, ", ")
#     else
#         println(resultfile, t)
#     end
# end
# for (i, gen) in ref[:gen]
#             print(resultfile, i)
#             print(resultfile, ", ")
#             print(resultfile, gen["gen_bus"])
#             print(resultfile, ", ")
#             for t in stages
#                 if t<nstage
#                     print(resultfile, getvalue(pg[i,t])*100)
#                     print(resultfile, ",")
#                 else
#                     print(resultfile, getvalue(pg[i,t])*100)
#                 end
#             end
#         println(resultfile, " ")
# end
# close(resultfile)

# # -------------------- Write generator rective power dispatch solution -------------------
# resultfile = open(string(dir, "res_qg.csv"), "w")
# print(resultfile, "Gen Index, Gen Bus,")
# for t in stages
#     if t<nstage
#         print(resultfile, t)
#         print(resultfile, ", ")
#     else
#         println(resultfile, t)
#     end
# end
# for (i, gen) in ref[:gen]
#             print(resultfile, i)
#             print(resultfile, ", ")
#             print(resultfile, gen["gen_bus"])
#             print(resultfile, ", ")
#             for t in stages
#                 if t<nstage
#                     print(resultfile, getvalue(qg[i,t])*100)
#                     print(resultfile, ",")
#                 else
#                     print(resultfile, getvalue(qg[i,t])*100)
#                 end
#             end
#         println(resultfile, " ")
# end
# close(resultfile)

# # ----------------------- Write load active power dispatch solution --------------------
# resultfile = open(string(dir, "res_pl.csv"), "w")
# print(resultfile, "Load Index, Bus Index, ")
# for t in stages
#     if t<nstage
#         print(resultfile, t)
#         print(resultfile, ", ")
#     else
#         println(resultfile, t)
#     end
# end
# for (i, load) in ref[:load]
#             print(resultfile, i)
#             print(resultfile, ", ")
#             print(resultfile, load["load_bus"])
#             print(resultfile, ", ")
#             for t in stages
#                 if t<nstage
#                     print(resultfile, getvalue(pl[i,t])*100)
#                     print(resultfile, ",")
#                 else
#                     print(resultfile, getvalue(pl[i,t])*100)
#                 end
#             end
#         println(resultfile, " ")
# end
# close(resultfile)

# # ----------------------------- Write load rective power dispatch solution -----------------
# resultfile = open(string(dir, "res_ql.csv"), "w")
# print(resultfile, "Load Index, Bus Index, ")
# for t in stages
#     if t<nstage
#         print(resultfile, t)
#         print(resultfile, ", ")
#     else
#         println(resultfile, t)
#     end
# end
# for (i, load) in ref[:load]
#             print(resultfile, i)
#             print(resultfile, ", ")
#             print(resultfile, load["load_bus"])
#             print(resultfile, ", ")
#             for t in stages
#                 if t<nstage
#                     print(resultfile, getvalue(ql[i,t])*100)
#                     print(resultfile, ",")
#                 else
#                     print(resultfile, getvalue(ql[i,t])*100)
#                 end
#             end
#         println(resultfile, " ")
# end
# close(resultfile)


@doc raw"""
Solve refined restoration problem
- Refined restoration problem will read a low-resolution result and fix certain time ranges of the variable to reducee the computation complexity
- Inputs: A set of restoration data in csv format and original system data
    - network data directory where data format could be json, matpower and psse
    - restoration data directory
        - restoration_gen: specify low-resolution generator restoration plan
        - restoration_bus: specify low-resolution bus status restoration plan
        - restoration_line: specify low-resolution line status restoration plan
    - result storage directory
    - gap
- Output: Restoration plans
- Constraints:
    - linearized AC power flow constraint
    - steady-state voltage variation constraint
    - generator cranking constraint
    - generator status and output constraint
    - load pick-up constraint
    - fixed low-resolution restoration plans
"""
function solve_refined_restoration(dir_case_network, network_data_format, dir_case_blackstart, dir_gen_plan, dir_case_result, t_final, t_step, gap)
    #----------------- Data processing -------------------
    # load network data
    ref = load_network(dir_case_network, network_data_format)
    # Count numbers and generate iterators
    ngen = length(keys(ref[:gen]));
    nload = length(keys(ref[:load]));
    # Set time and resolution specifications
    # The final time selection should be complied with restoration time requirement.
    time_final = t_final;
    time_series = 1:t_final;
    # Choicing different time steps is the key for testing multiple resolutions
    time_step = t_step;
    # calculate stages
    nstage = time_final/time_step;
    stages = 1:nstage;
    # Load generation data
    Pcr, Tcr, Krp = load_gen(dir_case_blackstart, ref, time_step)


    #----------------- Load solver ---------------
    # JuMP 0.18
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # JuMP 0.19
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # ------------Define decision variable ---------------------
    # define generator variables
    model = def_var_gen(model, ref, stages)
    # define load variable
    model = def_var_load(model, ref, stages)
    # define flow variable
    model = def_var_flow(model, ref, stages)

    # ------------Define constraints ---------------------
    # nodal constraint
    model = form_nodal(model, ref, stages)

    # branch (power flow) constraints
    model = form_branch(model, ref, stages)

    # generator control constraint
    model = form_gen_logic(model, ref, stages, nstage, Krp, Pcr)

    # generator cranking constraint
    model = form_gen_cranking(model, ref, stages, Pcr, Tcr)

    # load control constraint
    model = form_load_logic(model, ref, stages)


    #--------------- Additional status constraints to implement the multi-resolution idea ---------------------
    # General idea is described as follows:
    # Example: y(low resolution): |  stage 1 = 0    | |   stage 2 = 0   | |   stage 3 =1  |
    # Example: y (Interpolate):   0, 0, 0, 0, 0,  0,    x, x, x, x,  x,    1, 1, 1, 1, 1...

    # Read time series data
    Interpol_y = CSV.read(dir_gen_plan, DataFrame);

    # Fix generator black start sequence based on lower resolution results
    for g in keys(ref[:gen])
        # find the index of the dataframe where generator g is located
        g_index = findall(x->x==g, Interpol_y[:,1]);
        for t in stages
            # Determine the slice of the time series data
            t_s = Int((t-1)*time_step+1+2) : Int(t*time_step+2); # add 2 because the first two columns are gen bus and gen index

            # Check the status of the sliced time series data
            # If the current time series data contain 0, fix to zero
            if (0 in Interpol_y[g_index[1], t_s])
                @constraint(model, model[:y][g,t] == 0)

            # If the current time series data does not contain 0 but contain 2, do nothing
            elseif !(0 in Interpol_y[g_index[1], t_s]) & (2 in Interpol_y[g_index[1], t_s])

            # If the current time series data is all 1, fix to one
            elseif sum(convert(Array,Interpol_y[g_index[1], t_s]))==size(Interpol_y[g_index[1], t_s])[1]
                    @constraint(model,  model[:y][g,t] == 1)
            # Should be no other cases
            else
                println("Should not happen!!!!")
                println(g)
                println(t_s)
            end

        end
    end
    println("Heuristic variable fix completed")


    #------------------- Define objectives--------------------
#     @objective(model, Min, sum(sum( - model[:y][g,t]*ref[:gen][g]["pg"] for g in keys(ref[:gen])) for t in stages)
#                                 + sum(sum( - model[:u][ref[:load][d]["load_bus"], t]*ref[:load][d]["pd"] for d in keys(ref[:load])) for t in stages) )
#     @objective(model, Min, sum(sum( - model[:pg][g,t] for g in keys(ref[:gen])) for t in stages)
#                                 + sum(sum( - model[:pl][d, t] for d in keys(ref[:load])) for t in stages) )
    @objective(model, Min, sum(sum( - model[:pl][d, t] for d in keys(ref[:load])) for t in stages))

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))
    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))

  #
    # #------------- Record results ----------------
    # # results in stages
    println("")
    adj_matrix = Dict()
    for (i,j) in keys(ref[:buspairs])
        adj_matrix[(i,j)] = 0
    end
    println("Line energization: ")
    for t in stages
        print("stage ", t, ": ")
        for (i,j) in keys(ref[:buspairs])
             if (abs(value(model[:x][(i,j),t]) - 1) < 1e-6) && (adj_matrix[(i,j)] == 0)
                print("(", i, ",", j, ") ")
                adj_matrix[(i,j)] = 1
             end
        end
        println("")
    end

    println("")
    println("Generator energization: ")
    for t in stages
        print("stage ", t, ": ")
        for g in keys(ref[:gen])
            if (abs(value(model[:y][g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:y][g,t-1]) + value(model[:y][g,t]) - 1) < 1e-6)
                print(ref[:gen][g]["gen_bus"], " ")
            end
        end
        println("")
    end

    println("")
    println("Bus energization: ")
    for t in stages
        print("stage ", t, ": ")
        for b in keys(ref[:bus])
            if (abs(value(model[:u][b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:u][b,t-1]) + value(model[:u][b,t]) - 1) < 1e-6)
                print(b, " ")
            end
        end
        println("")
    end

    # #-----------Build a dictionary to store the changing point---------------
    CP = Dict();

    # Write branch energization solution
    CP[:x] = Dict();
    resultfile = open(string(dir_case_result, "res_x.csv"), "w")
    print(resultfile, "Branch Index, From Bus , To Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, branch) in ref[:branch]
            # if branch["b_fr"] == 0
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, branch["f_bus"])
                print(resultfile, ", ")
                print(resultfile, branch["t_bus"])
                print(resultfile, ",")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:x][(branch["f_bus"], branch["t_bus"]),t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:x][(branch["f_bus"], branch["t_bus"]),t])==0) & (value(model[:x][(branch["f_bus"], branch["t_bus"]),t+1])==1)
                            CP[:x][i] = t
                        end
                    else
                        print(resultfile, round(value(model[:x][(branch["f_bus"], branch["t_bus"]),t])))
                    end
                end
            println(resultfile, " ")
            #end
    end
    close(resultfile)

    # Write generator energization solution
    CP[:y] = Dict();
    resultfile = open(string(dir_case_result, "res_y.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:y][i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:y][i,t])==0) & (value(model[:y][i,t+1])==1)
                            CP[:y][i] = t
                        end
                    else
                        print(resultfile, value(model[:y][i,t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write bus energization solution
    CP[:u] = Dict();
    resultfile = open(string(dir_case_result, "res_u.csv"), "w")
    print(resultfile, "Bus Index,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, bus) in ref[:bus]
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:u][i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:u][i,t])==0) & (value(model[:u][i,t+1])==1)
                            CP[:u][i] = t
                        end
                    else
                        print(resultfile, round(value(model[:u][i,t])))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Write generator active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:pg][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pg][i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write generator rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_qg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:qg][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:qg][i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pl.csv"), "w")
    print(resultfile, "Load Index, Bus Index, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ref[:load]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:pl][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pl][i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_ql.csv"), "w")
    print(resultfile, "Load Index, Bus Index, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ref[:load]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:ql][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:ql][i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # #---------------- Interpolate current plan to time series (one-minute based) data --------------------
    # Interpolate generator energization solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_y.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                       # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        # Determine if the current generator has a changing scenario
                        if i in keys(CP[:y])
                            # check if the current stage is the changing stage
                            # mark changing stage different from 0 or 1 (do not use string as it causes problems after reading from CSV)
                            if CP[:y][i] == stage_index
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else
                                print(resultfile, Int(round(value(model[:y][i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(model[:y][i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, Int(round(value(model[:y][i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Interpolate generator dispatch solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_pg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, round(value(model[:pg][i,stage_index])*100))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, round(value(model[:pg][i,stage_index])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Interpolate bus energization solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_u.csv"), "w")
    print(resultfile, "Bus Index,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, bus) in ref[:bus]
                print(resultfile, i)
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                       # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        if i in keys(CP[:u])
                            # check if the current stage is the changing stage
                            if CP[:u][i] == stage_index  # If yes, mark the time series data as "tbd"
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else                          # If no, use the previously calculated values
                                print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    return ref, model

end
