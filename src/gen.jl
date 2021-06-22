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
Define generator variables
- The definitation of variables corresponds to different formulations.
"""
function def_var_gen(model, ref, stages, form)
    if form == 1
        # on-off status of gen at time t
        @variable(model, y[keys(ref[:gen]),stages], Bin);
        # generation variable
        @variable(model, pg[keys(ref[:gen]),stages])
        @variable(model, qg[keys(ref[:gen]),stages])
        # total load at time t
        @variable(model, pg_total[stages])
    elseif form == 2
        # indicator of starting instant x_gt in the paper
        @variable(model, ys[keys(ref[:gen]),stages], Bin);
        # indicator of cranking
        @variable(model, yc[keys(ref[:gen]),stages], Bin);
        # indicator of ramping
        @variable(model, yr[keys(ref[:gen]),stages], Bin);
        # indicator of Pmax
        @variable(model, yd[keys(ref[:gen]),stages], Bin);
        # generator output
        @variable(model, pg[keys(ref[:gen]),stages])
        # total generation capacity at time t
        @variable(model, pg_total[stages]);
    elseif form == 3
        # starting instant x_g in the paper (continuous value in time steps)
        @variable(model, yg[keys(ref[:gen])], Int);
        # generator output
        @variable(model, pg[keys(ref[:gen]),stages])
        # supplementary binary value for the first if-then condition
        @variable(model, ag[keys(ref[:gen]),stages], Bin);
        # supplementary binary value for the second if-then condition
        @variable(model, bg[keys(ref[:gen]),stages], Bin);
        # supplementary binary value for the third if-then condition
        @variable(model, cg[keys(ref[:gen]),stages], Bin);
        # total load at time t
        @variable(model, pg_total[stages])
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
function form_gen_logic(model, ref, stages, nstage, Krp, Pcr)
    for g in keys(ref[:gen])
        # generator ramping rate constraint
        for t in 1:nstage-1
            @constraint(model, model[:pg][g,t] - model[:pg][g,t+1] >= -Krp[g])
            @constraint(model, model[:pg][g,t] - model[:pg][g,t+1] <= Krp[g])
        end
        # black-start unit is determined by the cranking power
        if Pcr[g] == 0
            for t in stages
                @constraint(model, model[:y][g,t] == 1)
            end
        else
            for t in 1:nstage-1
                # on-line generators cannot be shut down
                @constraint(model, model[:y][g,t] <= model[:y][g,t+1])
            end
        end
    end
    return model
end


@doc raw"""
Generator cranking constraint
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
& \quad\quad -Pcr_{g}(y_{g,t}-y_{g,t-Tcr_{g}}) \leq pg_{g,t} \leq pg^{\max}_{g}y_{g,t-Tcr_{g}-1}-Pcr_{g}(y_{g,t} - y_{g,t-Tcr_{g}}) \\
& \text{ elseif }t \leq Tcr_{g}\\
& \quad\quad pg_{g,t} = -Pcr_{g}y_{g,t}\\
& \text{else }\\
& \quad\quad pg_{g,t} = -Pcr_{g}(y_{g,t} - y_{g,1})
\end{align*}
```
"""
function form_gen_cranking_1(model, ref, stages, Pcr, Tcr)

    println("Formulating generator cranking constraints")

    for t in stages
        for g in keys(ref[:gen])
            if t > Tcr[g] + 1
                # if y has been 1 for Tcr[g], then pg >=0; else pg=-Pcr if y = 1 and pg = 0 otherwise
                @constraint(model, model[:pg][g,t] >= -Pcr[g] * (model[:y][g,t] - model[:y][g,t-Tcr[g]]))
                # if y has been 1 for Tcr[g], then pg <=pg_max; else pg=-Pcr if y = 1 and pg = 0 otherwise
                @constraint(model, model[:pg][g,t] <= ref[:gen][g]["pmax"] * model[:y][g,t-Tcr[g]-1] - Pcr[g] * (model[:y][g,t] - model[:y][g,t-Tcr[g]]))
            elseif t <= Tcr[g]
                # determine the non-black start generator power by its cranking condition
                # with the time less than the cranking time, the generator power could only be zero or absorbing cranking power
                @constraint(model, model[:pg][g,t] == -Pcr[g] * model[:y][g,t])
            else
                # if the unit is on from the first time instant, it satisfies the cranking constraint and its power becomes zero
                # if not, it still absorbs the cranking power
                @constraint(model, model[:pg][g,t] == -Pcr[g] * (model[:y][g,t] - model[:y][g,1]))
            end
            # reactive power limits associated with the generator status
            @constraint(model, model[:qg][g,t] >= ref[:gen][g]["qmin"] * model[:y][g,t])
            @constraint(model, model[:qg][g,t] <= ref[:gen][g]["qmax"] * model[:y][g,t])
        end
    end

    # define the total generation
    for t in stages
        @constraint(model, model[:pg_total][t] == sum(model[:pg][g,t] for g in keys(ref[:gen])))
    end
    return model
end




@doc raw"""
Generator cranking constraint (form 2)
"""
function form_gen_cranking_2(model, ref, stages, Pcr, Tcr, Krp)

    # calculate ramping time
    # here we use minimum power
    Trp = Dict()
    for g in keys(ref[:gen])
        Trp[g] = ceil( (ref[:gen][g]["pmax"] + Pcr[g]) / Krp[g])
    end

    for g in keys(ref[:gen])
        println("Generator: ",g,"  Cranking time: ", Tcr[g])
    end
    for g in keys(ref[:gen])
        println("Generator: ",g,"  Pmax by Krp*Trp: ", Krp[g]*Trp[g],"  Pmax: ",ref[:gen][g]["pmax"])
    end

    println("Formulating generator cranking constraints")

    println("summation of ys will be one")
    # summation of ys will be one
    for g in keys(ref[:gen])
        @constraint(model, sum(model[:ys][g,t] for t in stages) == 1)
    end

    println("a NBS generator has no activity before it is started")
    # a NBS generator has no activity before it is started
    for t in stages
        # Eq (1): no cranking before be activated
        if t > 1
            for g in keys(ref[:gen])
                @constraint(model, (t - 1) * (1 - model[:ys][g,t]) >= sum(model[:yc][g,i] for i in 1:(t-1)))
            end
        end

        # Eq (2): no ramping before be activated
        for g in keys(ref[:gen])
            # get the terminal time
            t_terminal = min(stages[end], t + Tcr[g] - 1)
            @constraint(model, (t + Tcr[g] - 1) * (1 - model[:ys][g,t]) >= sum(model[:yr][g,i] for i in 1:t_terminal))
        end

        # Eq (3): not Pmax before be activated
        for g in keys(ref[:gen])
            # get the terminal time
            t_terminal = min(stages[end], t + Tcr[g] + Trp[g] - 1)
            @constraint(model, (t + Tcr[g] + Trp[g] - 1) * (1 - model[:ys][g,t]) >= sum(model[:yd][g,i] for i in 1:t_terminal))
        end
    end
    println("once started, a cranking is followed")
    # once started, a cranking is followed
    for t in stages
        for g in keys(ref[:gen])
            t_terminal = min(stages[end], t + Tcr[g] - 1)
            @constraint(model, sum(model[:yc][g,i] for i in t:t_terminal) >= model[:ys][g,t] * min(stages[end] - t, Tcr[g]))
        end
    end
    println("once cranking is finished, a ramping is followed")
    # once cranking is finished, a ramping is followed
    for t in stages
        for g in keys(ref[:gen])
            t_terminal = min(stages[end], t + Tcr[g] + Trp[g] - 1)
            t_start = t + Tcr[g] - 1
            @constraint(model, sum(model[:yr][g,i] for i in t_start:t_terminal) >= model[:ys][g,t] * min(stages[end] - t, Trp[g]))
        end
    end

    println("once ramping is finished, generator should be at max")
    # once ramping is finished, generator should be at max
    for t in stages
        for g in keys(ref[:gen])
            t_terminal = stages[end]
            t_start = t + Tcr[g]+ Trp[g] - 1
            @constraint(model, sum(model[:yd][g,i] for i in t_start:t_terminal) >= model[:ys][g,t] * (stages[end] - (t + Tcr[g]+ Trp[g] - 1)))
        end
    end

    println("individual generation at each time t")
    # individual generation at each time t
    for t in stages
        for g in keys(ref[:gen])
            @constraint(model, model[:pg][g,t] == model[:yc][g,t] * (-Pcr[g]) + sum(model[:yr][g,i] * Krp[g] for i in 1:t) )
        end
    end

    # total generation at each time t
    for t in stages
        @constraint(model, model[:pg_total][t] == sum((model[:yc][g,t] * (-Pcr[g]) + sum(model[:yr][g,i] * Krp[g] for i in 1: t) for g in keys(ref[:gen]))))
    end

    # in each stage the generator can only have one status
    for t in stages
        for g in keys(ref[:gen])
            @constraint(model, model[:yr][g,t] + model[:yc][g,t] + model[:yd][g,t] <= 1)
        end
    end
    # when each generator arrive at the Pmax, it stays
    for t in stages
        if t > 1
            for g in keys(ref[:gen])
                @constraint(model, model[:yd][g,t] >= model[:yd][g,t-1])
            end
        end
    end

    # return variables
    return model, Trp
end


@doc raw"""
Generator cranking constraint (form 3)
"""
function form_gen_cranking_3(model, ref, stages, Pcr, Tcr, Krp)

    # calculate ramping time
    # here we use minimum power
    Trp = Dict()
    for g in keys(ref[:gen])
        Trp[g] = ceil( (ref[:gen][g]["pmax"] + Pcr[g]) / Krp[g])
    end

    println("Formulating generator cranking constraints")

    M_time_bound = stages[end] + 50

    for t in stages
        # first if-then
        for g in keys(ref[:gen])
            # big M for power lower and upper bounds
            M_power_bound = ref[:gen][g]["pmax"] + 20

            # first if-then
            @constraint(model, t- model[:yg][g] <= M_time_bound * (1 - model[:ag][g,t]) - 0.1)
            @constraint(model, t- model[:yg][g] >= -M_time_bound * model[:ag][g,t])
            @constraint(model, -M_power_bound * (1 - model[:ag][g,t]) <= model[:pg][g,t])
            @constraint(model, model[:pg][g,t] <= M_power_bound * (1 - model[:ag][g,t]))

            # second if-then
            @constraint(model, t - model[:yg][g] - Tcr[g] <= M_time_bound * (1 - model[:bg][g,t]) - 0.1)
            @constraint(model, t - model[:yg][g] - Tcr[g] >= -M_time_bound * model[:bg][g,t])
            @constraint(model, -M_power_bound * (1 + model[:ag][g,t] - model[:bg][g,t]) <= model[:pg][g,t] + Pcr[g])
            @constraint(model, model[:pg][g,t] + Pcr[g] <= M_power_bound * (1 + model[:ag][g,t] - model[:bg][g,t]))

            # third if-then
            @constraint(model, t - model[:yg][g] - Tcr[g] - Trp[g] <= M_time_bound * (1 - model[:cg][g,t]) - 0.1)
            @constraint(model, t - model[:yg][g] - Tcr[g] - Trp[g] >= -M_time_bound * model[:cg][g,t])
            @constraint(model, -M_power_bound * (1 + model[:ag][g,t] + model[:bg][g,t] - model[:cg][g,t]) <= model[:pg][g,t] - Krp[g] * (t - model[:yg][g] - Tcr[g] + 1))
            @constraint(model, model[:pg][g,t] - Krp[g] * (t - model[:yg][g] - Tcr[g] + 1) <= M_power_bound * (1+ model[:ag][g,t] + model[:bg][g,t] - model[:cg][g,t]))

            # last if-then
            @constraint(model, -M_power_bound * (model[:ag][g,t] + model[:bg][g,t] + model[:cg][g,t]) <= model[:pg][g,t] - Krp[g]*Trp[g])
            @constraint(model, model[:pg][g,t] - Krp[g]*Trp[g] <= M_power_bound * (model[:ag][g,t] + model[:bg][g,t] + model[:cg][g,t]))
        end
    end

    # define the range of activation
    for g in keys(ref[:gen])
        @constraint(model, model[:yg][g] >= 1 )
        @constraint(model, model[:yg][g] <= stages[end])
    end

    # define the total generation
    for t in stages
        @constraint(model, model[:pg_total][t] == sum(model[:pg][g,t] for g in keys(ref[:gen])))
    end

    return model, Trp
end
