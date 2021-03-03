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
function def_var_load(model, ref, stages)
    # load P and Q
    @variable(model, pl[keys(ref[:load]),stages])
    @variable(model, ql[keys(ref[:load]),stages])

    # indicator of load status
    @variable(model, z[keys(ref[:load]),stages], Bin)
    # indicator of load restoration instant
    @variable(model, zs[keys(ref[:load]),stages], Bin);
    # total load at time t
    @variable(model, pd_total[stages])

    return model
end


@doc raw"""
Load pickup constraint
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
    println("formulating load logic constraints")
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
    return model
end

@doc raw"""
Load pickup constraint form 1
"""
function form_load_logic_1(model, ref, stages)

    z = model[:z]
    zs = model[:zs]

    # summation of zs will be one
    for d in keys(ref[:load])
        @constraint(model, sum(model[:zs][d,t] for t in stages) == 1)
    end

    # a load has no activity before it is picked up
    for t in stages
        if t > 1
            for d in keys(ref[:load])
                @constraint(model, sum(z[d,i] for i in 1:(t-1)) <= (t - 1) * (1 - zs[d,t]))
            end
        end
    end

    # a load is served to the end of the time horizon once it is picked up
    for t in stages
        for d in keys(ref[:load])
            @constraint(model, sum(z[d,i] for i in t:stages[end]) >= (stages[end] - t + 1) * zs[d,t])
        end
    end

    # total load
    for t in stages
        @constraint(model, model[:pd_total][t] == sum(ref[:load][d]["pd"] * z[d,t] for d in keys(ref[:load])))
    end

    return model
end
