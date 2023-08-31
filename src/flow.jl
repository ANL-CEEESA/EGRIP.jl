# ----------------- Load modules from registered package----------------
# using LinearAlgebra
# using JuMP
# using CPLEX
# # using Gurobi
# using DataFrames
# using CSV
# using JSON
# using PowerModels


@doc raw"""
Define flow variable
"""
function def_var_flow(model, ref, stages)
    @variable(model, x[keys(ref[:buspairs]),stages], Bin); # status of line at time t
    @variable(model, u[keys(ref[:bus]),stages], Bin); # status of bus at time t
    # synthetic voltage with upper- and lower bounds to collect the real voltage variables used in flow and bus
    @variable(model, ref[:bus][i]["vmin"] <= v[i in keys(ref[:bus]),stages] <= ref[:bus][i]["vmax"]);
    @variable(model, a[keys(ref[:bus]),stages]); # bus angle

    # slack variables of voltage and angle on flow equations
    bp2 = collect(keys(ref[:buspairs]))
    for k in keys(ref[:buspairs])
        i,j = k
        push!(bp2, (j,i))
    end
    @variable(model, vl[bp2,stages]) # V_i^j: line i-j voltage at terminal i
    @variable(model, al[bp2,stages]) # theta_i^j: angle varaibles in the power flow
    @variable(model, vb[keys(ref[:bus]),stages]) # V_i: bus i voltage

    # line flow with the index rule (branch, from_bus, to_bus)
    # Note that we can only measure the line flow at the bus terminal
    # In PSS/E, it seems if a flow limit is set to zero, it is not considered
    # So for now we relax the flow limits
    # @variable(model, -ref[:branch][l]["rate_a"] <= p[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])
    # @variable(model, -ref[:branch][l]["rate_a"] <= q[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])
    @variable(model, p[(l,i,j) in ref[:arcs],stages])
    @variable(model, q[(l,i,j) in ref[:arcs],stages])

    return model
end


@doc raw"""
Form the nodal constraints:
- voltage constraint
    - voltage deviation should be limited
    - voltage constraints are only activated if the associated line is energized
```math
\begin{align*}
    & v^{\min}_{i} \leq v_{i,t} \leq v^{\max}_{i}\\
    & v^{\min}_{i}x_{ij,t} \leq vl_{ij,t} \leq v^{\max}_{i}x_{ij,t}\\
    & v^{\min}_{j}x_{ij,t} \leq vl_{ji,t} \leq v^{\max}_{j}x_{ij,t}\\
    & v_{i,t} - v^{\max}_{i}(1-x_{ij,t}) \leq vl_{ij,t} \leq v_{i,t} - v^{\min}_{i}(1-x_{ij,t})\\
    & v_{j,t} - v^{\max}_{j}(1-x_{ij,t}) \leq vl_{ij,t} \leq v_{j,t} - v^{\min}_{j}(1-x_{ij,t})
\end{align*}
```
- angle difference constraint
    - angle difference should be limited
     - angle difference constraints are only activated if the associated line is energized
```math
 \begin{align*}
     & a^{\min}_{ij} \leq a_{i,t}-a_{j,t} \leq a^{\max}_{ij}\\
     & a^{\min}_{ij}x_{ij,t} \leq al_{ij,t}-al_{ji,t} \leq a^{\max}_{ij}x_{ij,t}\\
     & a_{i,t}-a_{j,t}-a^{\max}_{ij}(1-x_{ij,t}) \leq al_{ij,t}-al_{ji,t} \leq a_{i,t}-a_{j,t}-a^{\min}_{ij}(1-x_{ij,t})
 \end{align*}
```
- generator and bus energizing logics
    - energized line cannot be shut down
    - bus should be energized before the connected genertor being on
```math
\begin{align*}
 & x_{ij,t} \geq x_{ij,t-1}\\
 & u_{i,t} \geq x_{ij,t}\\
 & u_{j,t} \geq x_{ij,t}
\end{align*}
```
- bus energized constraints
    - bus energized indicating generator energized
    - energized buses cannot be shut down
```math
\begin{align*}
& v^{\min}u_{i,t} \leq vb_{i,t} \leq v^{\max}u_{i,t} \\
& v_{i,t} - v^{\max}(1-u_{i,t}) \leq vb_{i,t} \leq v_{i,t} - v^{\min}(1-u_{i,t})\\
& u_{g,t} = y_{g,t}\\
& u_{i,t} \geq u_{i,t-1}
\end{align*}
```
- nodal power balance constraint
```math
\begin{align*}
& \sum_{b\in i}p_{b,t}=\sum_{g\in i}pg_{g,t}-\sum_{l\in i}pl_{l,t}-Gs(2vb_{i,t}-u_{i,t})\\
& \sum_{b\in i}q_{b,t}=\sum_{g\in i}qg_{g,t}-\sum_{l\in i}ql_{l,t}+Bs(2vb_{i,t}-u_{i,t})
\end{align*}
```
"""
function form_nodal(model, ref, stages)
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
            # # voltage constraints
            # # voltage constraints are only activated if the associated line is energized
            # @constraint(model, vl[(i,j),t] >= ref[:bus][i]["vmin"]*x[(i,j),t])
            # @constraint(model, vl[(i,j),t] <= ref[:bus][i]["vmax"]*x[(i,j),t])
            # @constraint(model, vl[(j,i),t] >= ref[:bus][j]["vmin"]*x[(i,j),t])
            # @constraint(model, vl[(j,i),t] <= ref[:bus][j]["vmax"]*x[(i,j),t])
            # @constraint(model, vl[(i,j),t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-x[(i,j),t]))
            # @constraint(model, vl[(i,j),t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-x[(i,j),t]))
            # @constraint(model, vl[(j,i),t] >= v[j,t] - ref[:bus][j]["vmax"]*(1-x[(i,j),t]))
            # @constraint(model, vl[(j,i),t] <= v[j,t] - ref[:bus][j]["vmin"]*(1-x[(i,j),t]))

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
            @constraint(model, u[i,t] + u[j,t] >= x[(i,j),t])     # original: u[i,t] >= x[(i,j),t]
#             @constraint(model, u[j,t] >= x[(i,j),t])   # original: u[j,t] >= x[(i, j),t]

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

            # on-line buses cannot be shut down
            if t > 1
                @constraint(model, u[i,t] >= u[i,t-1])
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

    return model
end


function initial_gen_bus(model, ref, stages)
    for (i, bus) in ref[:bus]  # loop its keys and entries
        # define the initial status of non-generator bus
        if size(ref[:bus_gens][i], 1) == 0
            @constraint(model, model[:u][i, 1] == 0)
        end
    end

    return model
end


function bus_energization_rule(model, ref, stages)
    # bus energization rule
    # for non-generator bus, there needs to be at least one connected energized line before this bus can be energyized
    # if size(ref[:bus_gens][i],1) == 0
    #     @constraint(model, sum(x[(ref[:branch][r[1]]["f_bus"],ref[:branch][r[1]]["t_bus"]), t] for r in ref[:bus_arcs][i]) >= u[i,t])
    # end
    # nodal (bus) constraints
    for (i, bus) in ref[:bus]  # loop its keys and entries
        for t in stages
            if t > 1
                 if size(ref[:bus_gens][i],1) == 0
                    neighbor_buses = []
                    # find all neighboring buses
                    for r in ref[:bus_arcs][i]
                        if ref[:branch][r[1]]["f_bus"] != i
                            push!(neighbor_buses, ref[:branch][r[1]]["f_bus"])
                        end
                        if ref[:branch][r[1]]["t_bus"] != i
                            push!(neighbor_buses, ref[:branch][r[1]]["t_bus"])
                        end
                    end
                    # add constraints
                    @constraint(model, sum(model[:u][k,t-1] for k in neighbor_buses) >= model[:u][i,t])
                end
            end
        end
    end

    return model
end


@doc raw"""
Branch (power flow) constraints
- linearized power flow
```math
\begin{align*}
p_{bij,t}=G_{ii}(2vl_{ij,t}-x_{ij,t}) + G_{ij}(vl_{ij,t} + vl_{ji,t}-x_{ij,t}) + B_{ij}(al_{ij,t}-al_{ij,t})\\
q_{bij,t}=-B_{ii}(2vl_{ij,t}-x_{ij,t}) - B_{ij}(vl_{ij,t} + vl_{ji,t}-x_{ij,t}) + G_{ij}(al_{ij,t}-al_{ij,t})\\
\end{align*}
```
"""
function form_branch(model, ref, stages)

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

            ###### TEST ######
            # tr = 1; ti = 0; tm = 1
            # g_fr = 0
            # b_fr = 0
            # g_to = 0
            # b_to = 0

            # AC Line Flow Constraints
            @constraint(model, p_fr ==  (g+g_fr)/tm*(2*v_fr-x[bpf_idx,t]) + (-g*tr+b*ti)/tm*c_br + (-b*tr-g*ti)/tm*s_br)
            @constraint(model, q_fr == -(b+b_fr)/tm*(2*v_fr-x[bpf_idx,t]) - (-b*tr-g*ti)/tm*c_br + (-g*tr+b*ti)/tm*s_br)

            @constraint(model, p_to ==  (g+g_to)*(2*v_to-x[bpf_idx,t]) + (-g*tr-b*ti)/tm*c_br + (-b*tr+g*ti)/tm*(-s_br) )
            @constraint(model, q_to == -(b+b_to)*(2*v_to-x[bpf_idx,t]) - (-b*tr+g*ti)/tm*c_br + (-g*tr-b*ti)/tm*(-s_br) )
        end
    end
    return model
end


function enforce_damage_branch(model, ref, stages, line_damage)

    x = model[:x]

    println("Formulating branch damage constraints")
    for t in stages
        for br in line_damage
            @constraint(model, x[(br[1],br[2]), t] == 0)
        end
    end

    return model
end
