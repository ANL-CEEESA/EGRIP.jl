# ----------------- Load modules from registered package----------------
# using LinearAlgebra
# using JuMP
# # using CPLEX
# # using Gurobi
# using DataFrames
# using CSV
# using JSON
# using PowerModels
# using Random
# using Distributions

@doc raw"""
Define wind generator variables
"""
function def_var_wind(model, ref, stages)
    #TODO: add wind generators by buses
    # dispatched wind power
    @variable(model, pw[stages])

    return model
end


@doc raw"""
Form wind power dispatch chance constraints approximated by Sample Averaged Approximation (generated wind data)
"""
function form_wind_saa_1(model, ref, stages, wind)

    #TODO: different wind power distribution
    # sample wind power
    Random.seed!(123) # Setting the seed
    pw_sp = Dict()
    for s in 1:wind["sample_number"]
        wind_power_sample = rand(Normal(wind["mean"], wind["var"]), length(stages)) # an array
        wind_power_sample[findall(x->x<0, wind_power_sample)].=0 # make all below zero sample to zero
        pw_sp[s] = wind_power_sample
    end

    # integer variables for sample averaged approximation
    @variable(model, w[1:wind["sample_number"]], Bin)

    # chance constraint approximation
    println("Approximate chance constraints using sample averaged approximation")
    for s in 1:wind["sample_number"]
        for t in stages
            @constraint(model, model[:pw][t] - 100 * model[:w][s] <= pw_sp[s][Int(t)])
        end
    end

    # total violated cases should be less than a value
    @constraint(model, sum(model[:w][s] for s in 1:wind["sample_number"]) <= wind["violation_probability"] * wind["sample_number"])

    # Additionally, the dispatchable wind power cannot exceed the total installed capacity
    for t in stages
        @constraint(model, model[:pw][t] <= wind["mean"] + wind["var"])
        @constraint(model, model[:pw][t] >= 0)
    end

    return model, pw_sp
end


@doc raw"""
Form wind power dispatch chance constraints approximated by Sample Averaged Approximation (realistic wind data)
"""
function form_wind_saa_2(model, ref, stages, wind_data, viol_prob)

    #TODO: different wind power distribution
    # sample wind power
    pw_sp = Dict()
    n_stages = length(stages)
    n_wind_data = size(wind_data, 1)
    sample_index = 1:n_stages:n_wind_data
    n_sample = length(sample_index)
    for s in 1:n_sample-1
        pw_sp[s] = wind_data[sample_index[s]:sample_index[s+1]-1, 1]
    end

    println(pw_sp)

    # integer variables for sample averaged approximation
    @variable(model, w[1:n_sample-1], Bin)

    # chance constraint approximation
    println("Approximate chance constraints using sample averaged approximation")
    for s in 1:n_sample-1
        for t in stages
            @constraint(model, model[:pw][t] - 100 * model[:w][s] <= pw_sp[s][Int(t)]/100)
        end
    end
    # total violated cases should be less than a value
    @constraint(model, sum(model[:w][s] for s in 1:n_sample-1) <= viol_prob * (n_sample-1))
    # Additionally, the dispatchable wind power cannot exceed the total installed capacity
    for t in stages
        @constraint(model, model[:pw][t] <= maximum(wind_data[:,1])/100)
        @constraint(model, model[:pw][t] >= 0)
    end
    return model, pw_sp
end
