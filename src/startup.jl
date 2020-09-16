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
Solve generator start-up problem
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
function solve_startup(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap, wind)
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

    # define load variables
    model = def_var_load(model, ref, stages)

    # add wind into ref
    # #TODO: load wind data from csv or raw
    # #TODO: wind power distribution; currently Guassian is used
    # ref[:wind] = Dict(
    # 4 => Dict("bus"=>4, "pw_mean"=>4, "pw_dev"=>1),
    # 14 => Dict("bus"=>14, "pw_mean"=>5, "pw_dev"=>1.2),
    # 24 => Dict("bus"=>24, "pw_mean"=>6, "pw_dev"=>1.5),
    # )
    if wind["activation"] == 1
        model = def_var_wind(model, ref, stages)
    end


    # ------------Define constraints ---------------------
    # generator cranking constraint
    model = form_gen_cranking_1(model, ref, stages, Pcr, Tcr, Krp)

    # load pickup logic
    model = form_load_logic_1(model, ref, stages)

    # wind power dispatch chance constraint
    if wind["activation"] == 1
        model, pw_sp = form_wind_saa(model, ref, stages, wind["sample_number"], wind["violation_probability"])
    end

    # generator capacity is greater than load for all time
    if wind["activation"] == 1
        println("Generation start-up with wind power")
        for t in stages
            @constraint(model, model[:pw][t] + model[:pg_total][t] >= model[:pd_total][t])
        end
    else
        println("Generation start-up without wind power")
        for t in stages
            @constraint(model, model[:pg_total][t] >= model[:pd_total][t])
        end
    end


    #-----------------Define objectives--------------------
    @objective(model, Min, sum(sum(t * model[:ys][g,t] for t in stages) for g in keys(ref[:gen])) +
                            + sum(sum(t * model[:zs][d,t] for t in stages) for d in keys(ref[:load]))
                )

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    # optimize the model
    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))


    # #------------- Record results ----------------
    # results in stages
    println("")
    println("Generation total capacity: ")
    for t in stages
        println("stage ", t, ": ", value(model[:pg_total][t]))
    end

    println("Load total capacity: ")
    for t in stages
        println("stage ", t, ": ", value(model[:pd_total][t]))
    end

    return ref, model
end
