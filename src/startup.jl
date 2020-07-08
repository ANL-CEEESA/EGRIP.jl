# ----------------- Load modules from registered package----------------
using LinearAlgebra
using JuMP
using CPLEX
# using LightGraphs
# using LightGraphsFlows
# using Gurobi
using DataFrames
using CSV
using JSON
using PowerModels

@doc raw"""
- Solve generator start-up problem
- Inputs: A set of restoration data in csv format and original system data
    - network data directory where data format could be json, matpower and psse
    - restoration data directory
        - restoration_gen: specify initial generator status, cranking specifications and black-start generators
        - restoration_bus: specify initial bus status and its load priority, from where the problem type (partial or full restorations) can be determined
        - restoration_line: specify initial line status, from where the problem type (partial or full restorations) can be determined
    - result storage directory
    - gap
- Output: Generator start-up sequence
- Constraints:
    -
"""
function solve_startup(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

    #----------------- Load system data ----------------
    # check network data format and load accordingly
    # we are currently relying on PowerModels's IO functions
    if network_data_format == "json"
        println("print dir_case_network")
        println(dir_case_network)
        ref = Dict()
        ref = JSON.parsefile(dir_case_network)  # parse and transform data
        println("reconstruct data loaded from json")
        ref = Dict([Symbol(key) => val for (key, val) in pairs(ref)])
        ref[:gen] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:gen])])
        ref[:bus] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus])])
        ref[:bus_gens] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_gens])])
        ref[:bus_arcs] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_arcs])])
        ref[:bus_loads] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_loads])])
        ref[:bus_shunts] = Dict([parse(Int, string(key)) => val for (key, val) in pairs(ref[:bus_shunts])])
        ref[:branch] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:branch])])
        ref[:load] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:load])])
        ref[:buspairs] = Dict([ (parse(Int, split(key, ['(', ',', ')'])[2]),
            parse(Int, split(key, ['(', ',', ')'])[3]))=> val for (key, val) in pairs(ref[:buspairs])])
        ref[:arcs] = [Tuple(val) for (key, val) in pairs(ref[:arcs])]
        ref[:bus_arcs] = Dict([key=>[Tuple(arc) for arc in val] for (key,val) in pairs(ref[:bus_arcs])])
        println("complete loading network data in json format")
    elseif network_data_format == "matpower"
        # Convert data from matpower format to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:nw][0]
        println("complete loading network data in matpower format")
    elseif network_data_format == "psse"
        # Convert data from psse to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:nw][0]
        println("complete loading network data in psse format")
    else
        println("un-supported network data format")
    end

    # check data
    println("")
    println("bus")
    println(keys(ref[:bus]))

    println("bus arcs")
    println(keys(ref[:bus_arcs]))

    println("bus gen")
    println(keys(ref[:bus_gens]))

    println("bus pairs")
    println(keys(ref[:buspairs]))

    println("gen")
    println(keys(ref[:gen]))

    println("number of arcs")
    println(length(ref[:arcs]))

    println("arcs")
    println(ref[:arcs])

    # Count numbers and generate iterators
    ngen = length(keys(ref[:gen]));
    nload = length(keys(ref[:load]));
    # gen = 1:ngen;
    # load = 1:nload;

    # Load generation data
    # Generation data will be further adjusted based on the time and resolution specifications

    bs_data = CSV.read(dir_case_blackstart)

    # Define dictionary
    Tcr = Dict()
    Pcr = Dict()
    Krp = Dict()

    for g in keys(ref[:gen])
        Pcr[g] = bs_data[g,3]/100 # cranking power: power needed for the unit to be normally functional
        Tcr[g] = bs_data[g,4] # cranking time: time needed for the unit to be normally functional
        Krp[g] = bs_data[g,5]/100 # ramping rate
    end

    # --------------Set time and resolution specifications-----------------
    # The final time selection should be complied with restoration time requirement.
    time_final = t_final;
    time_series = 1:t_final;

    # Choicing different time steps is the key for testing multiple resolutions
    time_step = t_step;

    # calculate stages
    nstage = time_final/time_step;
    stages = 1:nstage;

    # Adjust generator data based on time step
    for g in keys(ref[:gen])
        Tcr[g] = ceil(bs_data[g,4]/time_step) # cranking time: time needed for the unit to be normally functional
        Krp[g] = bs_data[g,5]*time_step # ramping rate
    end


    #----------------- Load solver ---------------
    # JuMP 0.18
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # JuMP 0.19
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # ------------Define decision variable ---------------------
    @variable(model, x[keys(ref[:buspairs]),stages], Bin); # status of line at time t
    @variable(model, y[keys(ref[:gen]),stages], Bin); # status of gen at time t
    @variable(model, u[keys(ref[:bus]),stages], Bin); # status of bus at time t
    @variable(model, ref[:bus][i]["vmin"] <= v[i in keys(ref[:bus]),stages]
        <= ref[:bus][i]["vmax"]); # bus voltage with upper- and lower bounds
    @variable(model, a[keys(ref[:bus]),stages]); # bus angle

    # slack variables of voltage and angle on flow equations
    bp2 = collect(keys(ref[:buspairs]))
    for k in keys(ref[:buspairs])
        i,j = k
        push!(bp2, (j,i))
    end
    @variable(model, vl[bp2,stages]) # V_i^j
    @variable(model, al[bp2,stages]) # theta_i^j
    @variable(model, vb[keys(ref[:bus]),stages])

    # load variable
    @variable(model, pl[keys(ref[:load]),stages])
    @variable(model, ql[keys(ref[:load]),stages])

    # generation variable
    @variable(model, pg[keys(ref[:gen]),stages])
    @variable(model, qg[keys(ref[:gen]),stages])

    # line flow with the index rule (branch, from_bus, to_bus)
    # Note that we can only measure the line flow at the bus terminal
    @variable(model, -ref[:branch][l]["rate_a"] <= p[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])
    @variable(model, -ref[:branch][l]["rate_a"] <= q[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])

    # nodal constraint
    model = form_nodal(ref, model, stages, vl, vb, v, x, y, a, al, u, p, q, pg, pl, qg, ql)

    # branch (power flow) constraints
    model = form_branch(ref, model, stages, vl, al, x, u, p, q)

    # generator control constraint
    model = form_gen_logic(ref, model, stages, nstage, pg, y, Krp, Pcr)

    # load control constraint
    model = form_load_logic(ref, model, stages, pl, ql, u)

    # generator cranking constraint
    model = form_bs_logic(ref, model, stages, pg, qg, y, Pcr, Tcr)

    #------------------- Define objectives--------------------
    # @objective(model, Min, sum( sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages ) + sum( sum(t*z[l,t] for l in keys(ref[:load])) for t in stages ) )
    # @objective(model, Min, sum( sum(-pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] >= 0)
    #         + sum(pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] < 0) for t in stages ) )
    # @objective(model, Min, sum(10*sum(1 - y[g,t] for g in keys(ref[:gen])) + sum(x[a,t] for a in keys(ref[:buspairs])) for t in stages) )
    @objective(model, Min, sum(sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages) )

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))


    #------------- Record results ----------------
    # results in stages
    println("")
    adj_matrix = zeros(length(ref[:bus]), length(ref[:bus]))
    println("Line energization: ")
    for t in stages
        print("stage ", t, ": ")
        for (i,j) in keys(ref[:buspairs])
             if abs(value(x[(i,j),t]) - 1) < 1e-6 && adj_matrix[i,j] == 0
                print("(", i, ",", j, ") ")
                adj_matrix[i,j] = 1
             end
        end
        println("")
    end

    println("")
    println("Generator energization: ")
    for t in stages
        print("stage ", t, ": ")
        for g in keys(ref[:gen])
            if (abs(value(y[g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(y[g,t-1]) + value(y[g,t]) - 1) < 1e-6)
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
            if (abs(value(u[b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(u[b,t-1]) + value(u[b,t]) - 1) < 1e-6)
                print(b, " ")
            end
        end
        println("")
    end
end


@doc raw"""
load pickup constraint
- restored load cannot exceed its maximum values
```math
\begin{align*}
& 0 \leq pl_{l,t} \leq pl^{\max}u_{l,t}\\
& 0 \leq ql_{l,t} \leq ql^{\max}u_{l,t}\\
\end{align*}
```
- restored load cannot be shed
```math
\begin{align*}
& pl_{l,t-1} \leq pl_{l,t}\\
& ql_{l,t-1} \leq ql_{l,t}\\
\end{align*}
```
"""
function form_load_logic(ref, model, stages, pl, ql, u)

    println("formulating load logic constraints")

    for t in stages
        for l in keys(ref[:load])

            # active power load
            if ref[:load][l]["pd"] >= 0  # The current bus has positive active power load
                @constraint(model, pl[l,t] >= 0)
                @constraint(model, pl[l,t] <= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, pl[l,t] >= pl[l,t-1]) # no load shedding
                end
            else
                @constraint(model, pl[l,t] <= 0) # The current bus has no positive active power load ?
                @constraint(model, pl[l,t] >= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, pl[l,t] <= pl[l,t-1])
                end
            end

            # fix power factors
            if abs(ref[:load][l]["pd"]) >= exp(-8)
                @constraint(model, ql[l,t] == pl[l,t] * ref[:load][l]["qd"] / ref[:load][l]["pd"])
                continue
            end

            # reactive power load
            if ref[:load][l]["qd"] >= 0
                @constraint(model, ql[l,t] >= 0)
                @constraint(model, ql[l,t] <= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, ql[l,t] >= ql[l,t-1])
                end
            else
                @constraint(model, ql[l,t] <= 0)
                @constraint(model, ql[l,t] >= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, ql[l,t] <= ql[l,t-1])
                end
            end
        end
    end
    return model
end



@doc raw"""
generator status and output constraint
- generator ramping rate constraint
```math
\begin{align*}
-Krp_{g} \leq pg_{g,t}-pg_{g,t+1} \leq Krp_{g}
\end{align*}
```
- black-start unit is determined by the cranking power
```math
\begin{align*}
y_{g,t}=1 \text{  if  } Pcr_{g}=0
\end{align*}
```
- on-line generators cannot be shut down
```math
\begin{align*}
y_{g,t} <= y_{g,t+1}
\end{align*}
```
"""
function form_gen_logic(ref, model, stages, nstage, pg, y, Krp, Pcr)
    for g in keys(ref[:gen])
        # generator ramping rate constraint
        for t in 1:nstage-1
            @constraint(model, pg[g,t] - pg[g,t+1] >= -Krp[g])
            @constraint(model, pg[g,t] - pg[g,t+1] <= Krp[g])
        end
        # black-start unit is determined by the cranking power
        if Pcr[g] == 0
            for t in stages
                @constraint(model, y[g,t] == 1)
            end
        else
            for t in 1:nstage-1
                # on-line generators cannot be shut down
                @constraint(model, y[g,t] <= y[g,t+1])
            end
        end
    end
    return model
end

@doc raw"""
generator cranking constraint
- Once a non-black start generator is on, that is, $y_{g,t}=1$, then it needs to absorb the cranking power for its corresponding cranking time
- "After" the time step that this unit satisfies its cranking constraint, its power goes to zero; and from the next time step, it becomes a dispatchable generator
    - set non-black start unit generation limits based on "generator cranking constraint"
    - cranking constraint states if generator g has absorb the cranking power for its corresponding cranking time, it can produce power
- Mathematically if there exist enough 1 for $y_{g,t}=1$, then enable this generator's generating capability
- There will be the following scenarios
    - (1) generator is off, then $y_{g,t}-y_{g,t-Tcr_{g}} = 0$, then $pg_{g,t} = 0$
    - (2) generator is on but cranking time not satisfied, then $y_{g,t} - y_{g,t-Tcr_g} = 1$, then $pg_{g,t} = -Pcr_g$
    - (3) generator is on and just satisfies the cranking time, then $y_{g,t} - y_{g,t-Tcr_g} = 0$, $y_{g,t-Tcr_g-1}=0$, then $pg_{g,t} = 0$
    - (4) generator is on and bigger than satisfies the cranking time, then $y_{g,t} - y_{g,t-Tcr_g} = 0$, $y_{g,t-Tcr_g-1}=1$, then $0 <= pg_{g,t} <= pg^{\max}_{g}$
- All scenarios can be formulated as follows:
```math
\begin{align*}
& pg^{\min}_{g} \leq pg_{g,t} \leq pg^{\max}_{g}\\
& \text{ if }t > Tcr_{g}+1\\
& \quad\quad -Pcr_{g}(y_{g,t}-y_{g,Tcr_{g}}) \leq pg_{g,t} \leq pg^{\max}_{g}y_{g,t-Tcr_{g}-1}-Pcr_{g}(y_{g,t} - y_{g,t-Tcr_{g}}) \\
& \text{ elseif }t \leq Tcr_{g}\\
& \quad\quad pg_{g,t} = -Pcr_{g}y_{g,t}\\
& \text{else }\\
& \quad\quad pg_{g,t} = -Pcr_{g}(y_{g,t} - y_{g,1})
\end{align*}
```
"""
function form_bs_logic(ref, model, stages, pg, qg, y, Pcr, Tcr)

    println("formulating black-start constraints")

    for t in stages
        for g in keys(ref[:gen])
            if t > Tcr[g] + 1
                # scenario 1
                @constraint(model, pg[g,t] >= -Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
                @constraint(model, pg[g,t] <= ref[:gen][g]["pmax"] * y[g,t-Tcr[g]-1] - Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
            elseif t <= Tcr[g]
                # determine the non-black start generator power by its cranking condition
                # with the time less than the cranking time, the generator power could only be zero or absorbing cranking power
                @constraint(model, pg[g,t] == -Pcr[g] * y[g,t])
            else
                # if the unit is on from the first time instant, it satisfies the cranking constraint and its power becomes zero
                # if not, it still absorbs the cranking power
                @constraint(model, pg[g,t] == -Pcr[g] * (y[g,t] - y[g,1]))
            end
            @constraint(model, qg[g,t] >= ref[:gen][g]["qmin"]*y[g,t])
            # @constraint(model, qg[g,t] >= -10*y[g,t])
            @constraint(model, qg[g,t] <= ref[:gen][g]["qmax"]*y[g,t])
        end
    end
    return model
end
