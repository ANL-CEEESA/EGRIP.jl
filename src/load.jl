# ----------------- Load modules from registered package----------------
# using LinearAlgebra
# using JuMP
# # using CPLEX
# # using Gurobi
# using DataFrames
# using CSV
# using JSON
# using PowerModels


@doc raw"""
Define load variables
"""
function def_var_load(model, ref, stages, form)
    if form == 1
        # load P and Q
        @variable(model, pl[keys(ref[:load]),stages])
        @variable(model, ql[keys(ref[:load]),stages])
        # total load at time t
        @variable(model, pd_total[stages])
    elseif form == 2
        # indicator of load status
        @variable(model, z[keys(ref[:load]),stages], Bin)
        # indicator of load restoration instant
        @variable(model, zs[keys(ref[:load]),stages], Bin);
        # total load at time t
        @variable(model, pd_total[stages])
    elseif form == 3
        # starting instant x_d in the paper (continuous value in time step)
        @variable(model, zd[keys(ref[:load])], Int)
        # supplementary binary value for the first if-then condition
        @variable(model, ed[keys(ref[:load]),stages], Bin);
        # individual load value
        @variable(model, pl[keys(ref[:load]),stages])
        # total load at time t
        @variable(model, pd_total[stages])
    end

    return model
end


@doc raw"""
Load pickup constraint used for full restoration problem
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
function form_load_logic(model, ref, stages)
    println("")
    println("Formulating load pickup constraints")
    pl = model[:pl]
    ql = model[:ql]
    u = model[:u]

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

#             # fix power factors
#             if abs(ref[:load][l]["pd"]) >= exp(-8)
#                 @constraint(model, ql[l,t] == pl[l,t] * ref[:load][l]["qd"] / ref[:load][l]["pd"])
#                 continue
#             end

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

    # define the total load
    for t in stages
        @constraint(model, model[:pd_total][t] == sum(model[:pl][d,t] for d in keys(ref[:load])))
    end

    return model
end


@doc raw"""
Load pickup constraint form 1 used in generator start-up problem
"""
function form_load_logic_1(model, ref, stages)
    println("")
    println("Formulating load pickup constraints")
    pl = model[:pl]
    ql = model[:ql]

    for t in stages
        for l in keys(ref[:load])

            # active power load
            if ref[:load][l]["pd"] >= 0  # The current bus has positive active power load
                @constraint(model, pl[l,t] >= 0)
                @constraint(model, pl[l,t] <= ref[:load][l]["pd"])
                if t > 1
                    @constraint(model, pl[l,t] >= pl[l,t-1]) # no load shedding
                end
            else
                @constraint(model, pl[l,t] <= 0) # The current bus has no positive active power load ?
                @constraint(model, pl[l,t] >= ref[:load][l]["pd"])
                if t > 1
                    @constraint(model, pl[l,t] <= pl[l,t-1])
                end
            end
        end
    end

    # define the total load
    for t in stages
        @constraint(model, model[:pd_total][t] == sum(model[:pl][d,t] for d in keys(ref[:load])))
    end

    return model
end


@doc raw"""
Load pickup constraint form 2 used in generator start-up problem
"""
function form_load_logic_2(model, ref, stages)

    println("Formulating load pickup constraints")

    # summation of zs will be one
    for d in keys(ref[:load])
        @constraint(model, sum(model[:zs][d,t] for t in stages) == 1)
    end

    # a load has no activity before it is picked up
    for t in stages
        if t > 1
            for d in keys(ref[:load])
                @constraint(model, sum(model[:z][d,i] for i in 1:(t-1)) <= (t - 1) * (1 - model[:zs][d,t]))
            end
        end
    end

    # a load is served to the end of the time horizon once it is picked up
    for t in stages
        for d in keys(ref[:load])
            @constraint(model, sum(model[:z][d,i] for i in t:stages[end]) >= (stages[end] - t + 1) * model[:zs][d,t])
        end
    end

    # total load
    for t in stages
        @constraint(model, model[:pd_total][t] == sum(ref[:load][d]["pd"] * model[:z][d,t] for d in keys(ref[:load])))
    end

    return model
end


@doc raw"""
Load pickup constraint form 3
"""
function form_load_logic_3(model, ref, stages)

    println("Formulating load pickup constraints")

    M_time_bound = stages[end] + 50

    for t in stages
        # first if-them
        for d in keys(ref[:load])
            # big M for power lower and upper bounds
            M_power_bound = ref[:load][d]["pd"] + 20

            # combined if-then
            @constraint(model, t - model[:zd][d] <= M_time_bound * (1 - model[:ed][d,t]) - 0.1)
            @constraint(model, t - model[:zd][d] >= -M_time_bound * model[:ed][d,t])
            @constraint(model, 0 <= model[:pl][d,t])
            @constraint(model, model[:pl][d,t] <= M_power_bound * (1 - model[:ed][d,t]))
            @constraint(model, -M_power_bound * model[:ed][d,t] <= model[:pl][d,t] - ref[:load][d]["pd"])
            @constraint(model, model[:pl][d,t] - ref[:load][d]["pd"] <= M_power_bound * model[:ed][d,t])
        end
    end

    # define the range of activation
    for d in keys(ref[:load])
        @constraint(model, model[:zd][d] >= 1)
        @constraint(model, model[:zd][d] <= stages[end])
    end

    # define the total load
    for t in stages
        @constraint(model, model[:pd_total][t] == sum(model[:pl][d,t] for d in keys(ref[:load])))
    end

    return model
end
