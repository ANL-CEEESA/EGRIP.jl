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

    # ----------------- Build mathematical programming models -----------------
    # ----------------- JuMP 0.18 -----------------
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # ----------------- JuMP 0.19 -----------------
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # generator cranking constraint
    model, Pg_total = form_gen_cranking_1(ref, model, stages, Pcr, Tcr, Krp)


    return ref



    #-----------------Define objectives--------------------
    # @objective(model, Min, sum(sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages) )

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    # optimize!(model)
    # status = termination_status(model)
    # println("")
    # println("Termination status: ", status)
    # println("The objective value is: ", objective_value(model))


    # #------------- Record results ----------------
    # # results in stages
    # println("")
    # adj_matrix = zeros(length(ref[:bus]), length(ref[:bus]))
    # println("Line energization: ")
    # for t in stages
    #     print("stage ", t, ": ")
    #     for (i,j) in keys(ref[:buspairs])
    #          if abs(value(x[(i,j),t]) - 1) < 1e-6 && adj_matrix[i,j] == 0
    #             print("(", i, ",", j, ") ")
    #             adj_matrix[i,j] = 1
    #          end
    #     end
    #     println("")
    # end
    #
    # println("")
    # println("Generator energization: ")
    # for t in stages
    #     print("stage ", t, ": ")
    #     for g in keys(ref[:gen])
    #         if (abs(value(y[g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(y[g,t-1]) + value(y[g,t]) - 1) < 1e-6)
    #             print(ref[:gen][g]["gen_bus"], " ")
    #         end
    #     end
    #     println("")
    # end
    #
    # println("")
    # println("Bus energization: ")
    # for t in stages
    #     print("stage ", t, ": ")
    #     for b in keys(ref[:bus])
    #         if (abs(value(u[b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(u[b,t-1]) + value(u[b,t]) - 1) < 1e-6)
    #             print(b, " ")
    #         end
    #     end
    #     println("")
    # end
end
