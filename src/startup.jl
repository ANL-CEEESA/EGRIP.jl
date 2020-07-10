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

    # ------------Define constraints ---------------------
    # generator cranking constraint
    model = form_gen_cranking_1(ref, model, stages, Pcr, Tcr, Krp)

    # load pickup logic
    model = form_load_logic_1(ref, model, stages)

    # generator capacity is greater than load for all time
    for t in stages
        @constraint(model, model[:pg_total][t] >= model[:pd_total][t])
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
