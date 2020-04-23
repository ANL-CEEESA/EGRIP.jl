
# # If we use module, then it is convenient to export
# # If we do not use module, then it is not necessary to export
# module Form
# export post_soc_opf

using LinearAlgebra, JuMP, Memento

"checks if a given network data is a multinetwork"
ismultinetwork(data::Dict{String,Any}) = (haskey(data, "multinetwork") && data["multinetwork"] == true)

# Create our module level logger (this will get precompiled)
const LOGGER = getlogger(@__MODULE__)

function post_soc_opf(data::Dict{String,Any}, model=Model())
    @assert !haskey(data, "multinetwork")
    @assert !haskey(data, "conductors")

    standardize_cost_terms(data, order=2)
    ref = build_ref(data)[:nw][0]

    @variable(model, ref[:bus][i]["vmin"]^2 <= w[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"]^2, start=1.001)

    wr_min, wr_max, wi_min, wi_max = calc_voltage_product_bounds(ref[:buspairs])

    @variable(model, wr_min[bp] <= wr[bp in keys(ref[:buspairs])] <= wr_max[bp], start=1.0)
    @variable(model, wi_min[bp] <= wi[bp in keys(ref[:buspairs])] <= wi_max[bp])

    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"])
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"])

    @variable(model, -ref[:branch][l]["rate_a"] <= p[(l,i,j) in ref[:arcs]] <= ref[:branch][l]["rate_a"])
    @variable(model, -ref[:branch][l]["rate_a"] <= q[(l,i,j) in ref[:arcs]] <= ref[:branch][l]["rate_a"])

    @variable(model, ref[:arcs_dc_param][a]["pmin"] <= p_dc[a in ref[:arcs_dc]] <= ref[:arcs_dc_param][a]["pmax"])
    @variable(model, ref[:arcs_dc_param][a]["qmin"] <= q_dc[a in ref[:arcs_dc]] <= ref[:arcs_dc_param][a]["qmax"])

    from_idx = Dict(arc[1] => arc for arc in ref[:arcs_from_dc])
    @objective(model, Min,
        sum(gen["cost"][1]*pg[i]^2 + gen["cost"][2]*pg[i] + gen["cost"][3] for (i,gen) in ref[:gen]) +
        sum(dcline["cost"][1]*p_dc[from_idx[i]]^2 + dcline["cost"][2]*p_dc[from_idx[i]] + dcline["cost"][3] for (i,dcline) in ref[:dcline])
    )

    for (bp, buspair) in ref[:buspairs]
        i,j = bp

        # Voltage Product Relaxation Lowerbound
        @constraint(model, wr[(i,j)]^2 + wi[(i,j)]^2 <= w[i]*w[j])

        vfub = buspair["vm_fr_max"]
        vflb = buspair["vm_fr_min"]
        vtub = buspair["vm_to_max"]
        vtlb = buspair["vm_to_min"]
        tdub = buspair["angmax"]
        tdlb = buspair["angmin"]

        phi = (tdub + tdlb)/2
        d   = (tdub - tdlb)/2

        sf = vflb + vfub
        st = vtlb + vtub

        # Voltage Product Relaxation Upperbound
        @constraint(model, sf*st*(cos(phi)*wr[(i,j)] + sin(phi)*wi[(i,j)]) - vtub*cos(d)*st*w[i] - vfub*cos(d)*sf*w[j] >=  vfub*vtub*cos(d)*(vflb*vtlb - vfub*vtub))
        @constraint(model, sf*st*(cos(phi)*wr[(i,j)] + sin(phi)*wi[(i,j)]) - vtlb*cos(d)*st*w[i] - vflb*cos(d)*sf*w[j] >= -vflb*vtlb*cos(d)*(vflb*vtlb - vfub*vtub))
    end

    for (i,bus) in ref[:bus]
        bus_loads = [ref[:load][l] for l in ref[:bus_loads][i]]
        bus_shunts = [ref[:shunt][s] for s in ref[:bus_shunts][i]]

        # Bus KCL
        @constraint(model,
            sum(p[a] for a in ref[:bus_arcs][i]) +
            sum(p_dc[a_dc] for a_dc in ref[:bus_arcs_dc][i]) ==
            sum(pg[g] for g in ref[:bus_gens][i]) -
            sum(load["pd"] for load in bus_loads) -
            sum(shunt["gs"] for shunt in bus_shunts)*w[i]
        )
        @constraint(model,
            sum(q[a] for a in ref[:bus_arcs][i]) +
            sum(q_dc[a_dc] for a_dc in ref[:bus_arcs_dc][i]) ==
            sum(qg[g] for g in ref[:bus_gens][i]) -
            sum(load["qd"] for load in bus_loads) +
            sum(shunt["bs"] for shunt in bus_shunts)*w[i]
        )
    end

    for (i,branch) in ref[:branch]
        f_idx = (i, branch["f_bus"], branch["t_bus"])
        t_idx = (i, branch["t_bus"], branch["f_bus"])
        bp_idx = (branch["f_bus"], branch["t_bus"])

        p_fr = p[f_idx]
        q_fr = q[f_idx]
        p_to = p[t_idx]
        q_to = q[t_idx]

        w_fr = w[branch["f_bus"]]
        w_to = w[branch["t_bus"]]
        wr_br = wr[bp_idx]
        wi_br = wi[bp_idx]

        # Line Flow
        g, b = calc_branch_y(branch)
        tr, ti = calc_branch_t(branch)
        g_fr = branch["g_fr"]
        b_fr = branch["b_fr"]
        g_to = branch["g_to"]
        b_to = branch["b_to"]
        tm = branch["tap"]^2

        # AC Line Flow Constraints
        @constraint(model, p_fr ==  (g+g_fr)/tm*w_fr + (-g*tr+b*ti)/tm*(wr_br) + (-b*tr-g*ti)/tm*(wi_br) )
        @constraint(model, q_fr == -(b+b_fr)/tm*w_fr - (-b*tr-g*ti)/tm*(wr_br) + (-g*tr+b*ti)/tm*(wi_br) )

        @constraint(model, p_to ==  (g+g_to)*w_to + (-g*tr-b*ti)/tm*(wr_br) + (-b*tr+g*ti)/tm*(-wi_br) )
        @constraint(model, q_to == -(b+b_to)*w_to - (-b*tr+g*ti)/tm*(wr_br) + (-g*tr-b*ti)/tm*(-wi_br) )

        # Phase Angle Difference Limit
        @constraint(model, wi_br <= tan(branch["angmax"])*wr_br)
        @constraint(model, wi_br >= tan(branch["angmin"])*wr_br)

        # Apparent Power Limit, From and To
        @constraint(model, p[f_idx]^2 + q[f_idx]^2 <= branch["rate_a"]^2)
        @constraint(model, p[t_idx]^2 + q[t_idx]^2 <= branch["rate_a"]^2)
    end

    for (i,dcline) in ref[:dcline]
        # DC Line Flow Constraint
        f_idx = (i, dcline["f_bus"], dcline["t_bus"])
        t_idx = (i, dcline["t_bus"], dcline["f_bus"])

        @constraint(model, (1-dcline["loss1"])*p_dc[f_idx] + (p_dc[t_idx] - dcline["loss0"]) == 0)
    end

    return model
end

function calc_branch_t(branch::Dict{String,Any})
    tap_ratio = branch["tap"]
    angle_shift = branch["shift"]

    tr = tap_ratio .* cos.(angle_shift)
    ti = tap_ratio .* sin.(angle_shift)

    return tr, ti
end

""
function calc_branch_y(branch::Dict{String,Any})
    y = pinv(branch["br_r"] + im * branch["br_x"])
    g, b = real(y), imag(y)
    return g, b
end

""
function calc_voltage_product_bounds(buspairs, conductor::Int=1)
    wr_min = Dict((bp, -Inf) for bp in keys(buspairs))
    wr_max = Dict((bp,  Inf) for bp in keys(buspairs))
    wi_min = Dict((bp, -Inf) for bp in keys(buspairs))
    wi_max = Dict((bp,  Inf) for bp in keys(buspairs))

    buspairs_conductor = Dict()
    for (bp, buspair) in buspairs
        # buspairs_conductor[bp] = Dict((k, getmcv(v, conductor)) for (k,v) in buspair)
        buspairs_conductor[bp] = Dict((k, v) for (k,v) in buspair)
    end

    for (bp, buspair) in buspairs_conductor
        i,j = bp

        if buspair["angmin"] >= 0
            wr_max[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*cos(buspair["angmin"])
            wr_min[bp] = buspair["vm_fr_min"]*buspair["vm_to_min"]*cos(buspair["angmax"])
            wi_max[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*sin(buspair["angmax"])
            wi_min[bp] = buspair["vm_fr_min"]*buspair["vm_to_min"]*sin(buspair["angmin"])
        end
        if buspair["angmax"] <= 0
            wr_max[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*cos(buspair["angmax"])
            wr_min[bp] = buspair["vm_fr_min"]*buspair["vm_to_min"]*cos(buspair["angmin"])
            wi_max[bp] = buspair["vm_fr_min"]*buspair["vm_to_min"]*sin(buspair["angmax"])
            wi_min[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*sin(buspair["angmin"])
        end
        if buspair["angmin"] < 0 && buspair["angmax"] > 0
            wr_max[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*1.0
            wr_min[bp] = buspair["vm_fr_min"]*buspair["vm_to_min"]*min(cos(buspair["angmin"]), cos(buspair["angmax"]))
            wi_max[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*sin(buspair["angmax"])
            wi_min[bp] = buspair["vm_fr_max"]*buspair["vm_to_max"]*sin(buspair["angmin"])
        end

    end

    return wr_min, wr_max, wi_min, wi_max
end

"ensures all polynomial costs functions have the same number of terms"
function standardize_cost_terms(data::Dict{String,Any}; order=-1)
    comp_max_order = 1

    if ismultinetwork(data)
        networks = data["nw"]
    else
        networks = [("0", data)]
    end

    for (i, network) in networks
        if haskey(network, "gen")
            for (i, gen) in network["gen"]
                if haskey(gen, "model") && gen["model"] == 2
                    max_nonzero_index = 1
                    for i in 1:length(gen["cost"])
                        max_nonzero_index = i
                        if gen["cost"][i] != 0.0
                            break
                        end
                    end

                    max_oder = length(gen["cost"]) - max_nonzero_index + 1

                    comp_max_order = max(comp_max_order, max_oder)
                end
            end
        end

        if haskey(network, "dcline")
            for (i, dcline) in network["dcline"]
                if haskey(dcline, "model") && dcline["model"] == 2
                    max_nonzero_index = 1
                    for i in 1:length(dcline["cost"])
                        max_nonzero_index = i
                        if dcline["cost"][i] != 0.0
                            break
                        end
                    end

                    max_oder = length(dcline["cost"]) - max_nonzero_index + 1

                    comp_max_order = max(comp_max_order, max_oder)
                end
            end
        end

    end

    if comp_max_order <= order+1
        comp_max_order = order+1
    else
        if order != -1 # if not the default
            warn(LOGGER, "a standard cost order of $(order) was requested but the given data requires an order of at least $(comp_max_order-1)")
        end
    end

    for (i, network) in networks
        if haskey(network, "gen")
            _standardize_cost_terms(network["gen"], comp_max_order, "generator")
        end
        if haskey(network, "dcline")
            _standardize_cost_terms(network["dcline"], comp_max_order, "dcline")
        end
    end

end


"ensures all polynomial costs functions have at exactly comp_order terms"
function _standardize_cost_terms(components::Dict{String,Any}, comp_order::Int, cost_comp_name::String)
    modified = Set{Int}()
    for (i, comp) in components
        if haskey(comp, "model") && comp["model"] == 2 && length(comp["cost"]) != comp_order
            std_cost = [0.0 for i in 1:comp_order]
            current_cost = reverse(comp["cost"])
            #println("gen cost: $(comp["cost"])")
            for i in 1:min(comp_order, length(current_cost))
                std_cost[i] = current_cost[i]
            end
            comp["cost"] = reverse(std_cost)
            comp["ncost"] = comp_order
            #println("std gen cost: $(comp["cost"])")

            warn(LOGGER, "Updated $(cost_comp_name) $(comp["index"]) cost function with order $(length(current_cost)) to a function of order $(comp_order): $(comp["cost"])")
            push!(modified, comp["index"])
        end
    end
    return modified
end

""
function calc_theta_delta_bounds(data::Dict{String,Any})
    bus_count = length(data["bus"])
    branches = [branch for branch in values(data["branch"])]
    if haskey(data, "ne_branch")
        append!(branches, values(data["ne_branch"]))
    end

    angle_min = Real[]
    angle_max = Real[]

    conductors = 1
    if haskey(data, "conductors")
        conductors = data["conductors"]
    end
    conductor_ids = 1:conductors

    for c in conductor_ids
        angle_mins = [branch["angmin"][c] for branch in branches]
        angle_maxs = [branch["angmax"][c] for branch in branches]

        sort!(angle_mins)
        sort!(angle_maxs, rev=true)

        if length(angle_mins) > 1
            # note that, this can occur when dclines are present
            angle_count = min(bus_count-1, length(branches))

            angle_min_val = sum(angle_mins[1:angle_count])
            angle_max_val = sum(angle_maxs[1:angle_count])
        else
            angle_min_val = angle_mins[1]
            angle_max_val = angle_maxs[1]
        end

        push!(angle_min, angle_min_val)
        push!(angle_max, angle_max_val)
    end

    if haskey(data, "conductors")
        # amin = MultiConductorVector(angle_min)
        # amax = MultiConductorVector(angle_max)
        # return amin, amax
    else
        return angle_min[1], angle_max[1]
    end
end

"""
Returns a dict that stores commonly used pre-computed data form of the data dictionary,
primarily for converting data-types, filtering out deactivated components, and storing
system-wide values that need to be computed globally.
Some of the common keys include:
* `:off_angmin` and `:off_angmax` (see `calc_theta_delta_bounds(data)`),
* `:bus` -- the set `{(i, bus) in ref[:bus] : bus["bus_type"] != 4}`,
* `:gen` -- the set `{(i, gen) in ref[:gen] : gen["gen_status"] == 1 && gen["gen_bus"] in keys(ref[:bus])}`,
* `:branch` -- the set of branches that are active in the network (based on the component status values),
* `:arcs_from` -- the set `[(i,b["f_bus"],b["t_bus"]) for (i,b) in ref[:branch]]`,
* `:arcs_to` -- the set `[(i,b["t_bus"],b["f_bus"]) for (i,b) in ref[:branch]]`,
* `:arcs` -- the set of arcs from both `arcs_from` and `arcs_to`,
* `:bus_arcs` -- the mapping `Dict(i => [(l,i,j) for (l,i,j) in ref[:arcs]])`,
* `:buspairs` -- (see `buspair_parameters(ref[:arcs_from], ref[:branch], ref[:bus])`),
* `:bus_gens` -- the mapping `Dict(i => [gen["gen_bus"] for (i,gen) in ref[:gen]])`.
* `:bus_loads` -- the mapping `Dict(i => [load["load_bus"] for (i,load) in ref[:load]])`.
* `:bus_shunts` -- the mapping `Dict(i => [shunt["shunt_bus"] for (i,shunt) in ref[:shunt]])`.
* `:arcs_from_dc` -- the set `[(i,b["f_bus"],b["t_bus"]) for (i,b) in ref[:dcline]]`,
* `:arcs_to_dc` -- the set `[(i,b["t_bus"],b["f_bus"]) for (i,b) in ref[:dcline]]`,
* `:arcs_dc` -- the set of arcs from both `arcs_from_dc` and `arcs_to_dc`,
* `:bus_arcs_dc` -- the mapping `Dict(i => [(l,i,j) for (l,i,j) in ref[:arcs_dc]])`, and
* `:buspairs_dc` -- (see `buspair_parameters(ref[:arcs_from_dc], ref[:dcline], ref[:bus])`),
If `:ne_branch` exists, then the following keys are also available with similar semantics:
* `:ne_branch`, `:ne_arcs_from`, `:ne_arcs_to`, `:ne_arcs`, `:ne_bus_arcs`, `:ne_buspairs`.
"""
function build_ref(data::Dict{String,Any})
    refs = Dict{Symbol,Any}()

    nws = refs[:nw] = Dict{Int,Any}()

    if ismultinetwork(data)
        nws_data = data["nw"]
    else
        nws_data = Dict{String,Any}("0" => data)
    end

    for (n, nw_data) in nws_data
        nw_id = parse(Int, n)
        ref = nws[nw_id] = Dict{Symbol,Any}()

        for (key, item) in nw_data
            if isa(item, Dict{String,Any})
                item_lookup = Dict{Int,Any}([(parse(Int, k), v) for (k,v) in item])
                ref[Symbol(key)] = item_lookup
            else
                ref[Symbol(key)] = item
            end
        end

        if !haskey(ref, :conductors)
            ref[:conductor_ids] = 1:1
        else
            ref[:conductor_ids] = 1:ref[:conductors]
        end

        # add connected components
        component_sets = connected_components(nw_data)
        ref[:components] = Dict(i => c for (i,c) in enumerate(sort(collect(component_sets); by=length)))

        # filter turned off stuff
        ref[:bus] = Dict(x for x in ref[:bus] if x.second["bus_type"] != 4)
        ref[:load] = Dict(x for x in ref[:load] if (x.second["status"] == 1 && x.second["load_bus"] in keys(ref[:bus])))
        ref[:shunt] = Dict(x for x in ref[:shunt] if (x.second["status"] == 1 && x.second["shunt_bus"] in keys(ref[:bus])))
        ref[:gen] = Dict(x for x in ref[:gen] if (x.second["gen_status"] == 1 && x.second["gen_bus"] in keys(ref[:bus])))
        ref[:storage] = Dict(x for x in ref[:storage] if (x.second["status"] == 1 && x.second["storage_bus"] in keys(ref[:bus])))
        ref[:branch] = Dict(x for x in ref[:branch] if (x.second["br_status"] == 1 && x.second["f_bus"] in keys(ref[:bus]) && x.second["t_bus"] in keys(ref[:bus])))
        ref[:dcline] = Dict(x for x in ref[:dcline] if (x.second["br_status"] == 1 && x.second["f_bus"] in keys(ref[:bus]) && x.second["t_bus"] in keys(ref[:bus])))


        ref[:arcs_from] = [(i,branch["f_bus"],branch["t_bus"]) for (i,branch) in ref[:branch]]
        ref[:arcs_to]   = [(i,branch["t_bus"],branch["f_bus"]) for (i,branch) in ref[:branch]]
        ref[:arcs] = [ref[:arcs_from]; ref[:arcs_to]]

        ref[:arcs_from_dc] = [(i,dcline["f_bus"],dcline["t_bus"]) for (i,dcline) in ref[:dcline]]
        ref[:arcs_to_dc]   = [(i,dcline["t_bus"],dcline["f_bus"]) for (i,dcline) in ref[:dcline]]
        ref[:arcs_dc]      = [ref[:arcs_from_dc]; ref[:arcs_to_dc]]

        # maps dc line from and to parameters to arcs
        arcs_dc_param = ref[:arcs_dc_param] = Dict()
        for (l,i,j) in ref[:arcs_from_dc]
            arcs_dc_param[(l,i,j)] = Dict{String,Any}(
                "pmin" => ref[:dcline][l]["pminf"],
                "pmax" => ref[:dcline][l]["pmaxf"],
                "pref" => ref[:dcline][l]["pf"],
                "qmin" => ref[:dcline][l]["qminf"],
                "qmax" => ref[:dcline][l]["qmaxf"],
                "qref" => ref[:dcline][l]["qf"]
            )
            arcs_dc_param[(l,j,i)] = Dict{String,Any}(
                "pmin" => ref[:dcline][l]["pmint"],
                "pmax" => ref[:dcline][l]["pmaxt"],
                "pref" => ref[:dcline][l]["pt"],
                "qmin" => ref[:dcline][l]["qmint"],
                "qmax" => ref[:dcline][l]["qmaxt"],
                "qref" => ref[:dcline][l]["qt"]
            )
        end


        bus_loads = Dict((i, []) for (i,bus) in ref[:bus])
        for (i, load) in ref[:load]
            push!(bus_loads[load["load_bus"]], i)
        end
        ref[:bus_loads] = bus_loads

        bus_shunts = Dict((i, []) for (i,bus) in ref[:bus])
        for (i,shunt) in ref[:shunt]
            push!(bus_shunts[shunt["shunt_bus"]], i)
        end
        ref[:bus_shunts] = bus_shunts

        bus_gens = Dict((i, []) for (i,bus) in ref[:bus])
        for (i,gen) in ref[:gen]
            push!(bus_gens[gen["gen_bus"]], i)
        end
        ref[:bus_gens] = bus_gens

        bus_storage = Dict((i, []) for (i,bus) in ref[:bus])
        for (i,strg) in ref[:storage]
            push!(bus_storage[strg["storage_bus"]], i)
        end
        ref[:bus_storage] = bus_storage


        bus_arcs = Dict((i, []) for (i,bus) in ref[:bus])
        for (l,i,j) in ref[:arcs]
            push!(bus_arcs[i], (l,i,j))
        end
        ref[:bus_arcs] = bus_arcs

        bus_arcs_dc = Dict((i, []) for (i,bus) in ref[:bus])
        for (l,i,j) in ref[:arcs_dc]
            push!(bus_arcs_dc[i], (l,i,j))
        end
        ref[:bus_arcs_dc] = bus_arcs_dc

        # a set of buses to support multiple connected components
        ref_buses = Dict()
        for (k,v) in ref[:bus]
            if v["bus_type"] == 3
                ref_buses[k] = v
            end
        end

        if length(ref_buses) == 0
            big_gen = biggest_generator(ref[:gen])
            gen_bus = big_gen["gen_bus"]
            ref_bus = ref_buses[gen_bus] = ref[:bus][gen_bus]
            ref_bus["bus_type"] = 3
            warn(LOGGER, "no reference bus found, setting bus $(gen_bus) as reference based on generator $(big_gen["index"])")
        end

        if length(ref_buses) > 1
            warn(LOGGER, "multiple reference buses found, $(keys(ref_buses)), this can cause infeasibility if they are in the same connected component")
        end

        ref[:ref_buses] = ref_buses

        ref[:buspairs] = buspair_parameters(ref[:arcs_from], ref[:branch], ref[:bus], ref[:conductor_ids], haskey(ref, :conductors))

        off_angmin, off_angmax = calc_theta_delta_bounds(nw_data)
        ref[:off_angmin] = off_angmin
        ref[:off_angmax] = off_angmax

        if haskey(ref, :ne_branch)
            ref[:ne_branch] = Dict(x for x in ref[:ne_branch] if (x.second["br_status"] == 1 && x.second["f_bus"] in keys(ref[:bus]) && x.second["t_bus"] in keys(ref[:bus])))

            ref[:ne_arcs_from] = [(i,branch["f_bus"],branch["t_bus"]) for (i,branch) in ref[:ne_branch]]
            ref[:ne_arcs_to]   = [(i,branch["t_bus"],branch["f_bus"]) for (i,branch) in ref[:ne_branch]]
            ref[:ne_arcs] = [ref[:ne_arcs_from]; ref[:ne_arcs_to]]

            ne_bus_arcs = Dict((i, []) for (i,bus) in ref[:bus])
            for (l,i,j) in ref[:ne_arcs]
                push!(ne_bus_arcs[i], (l,i,j))
            end
            ref[:ne_bus_arcs] = ne_bus_arcs

            ref[:ne_buspairs] = buspair_parameters(ref[:ne_arcs_from], ref[:ne_branch], ref[:bus], ref[:conductor_ids], haskey(ref, :conductors))
        end

    end

    return refs
end

"checks if a given network data is a multinetwork"
ismultinetwork(data::Dict{String,Any}) = (haskey(data, "multinetwork") && data["multinetwork"] == true)

"""
computes the connected components of the network graph
returns a set of sets of bus ids, each set is a connected component
"""
function connected_components(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "connected_components does not yet support multinetwork data")
    end

    active_bus = Dict(x for x in data["bus"] if x.second["bus_type"] != 4)
    #active_bus = filter((i, bus) -> bus["bus_type"] != 4, data["bus"])
    active_bus_ids = Set{Int64}([bus["bus_i"] for (i,bus) in active_bus])
    #println(active_bus_ids)

    neighbors = Dict(i => [] for i in active_bus_ids)
    for (i,branch) in data["branch"]
        if branch["br_status"] != 0 && branch["f_bus"] in active_bus_ids && branch["t_bus"] in active_bus_ids
            push!(neighbors[branch["f_bus"]], branch["t_bus"])
            push!(neighbors[branch["t_bus"]], branch["f_bus"])
        end
    end
    for (i,dcline) in data["dcline"]
        if dcline["br_status"] != 0 && dcline["f_bus"] in active_bus_ids && dcline["t_bus"] in active_bus_ids
            push!(neighbors[dcline["f_bus"]], dcline["t_bus"])
            push!(neighbors[dcline["t_bus"]], dcline["f_bus"])
        end
    end
    #println(neighbors)

    component_lookup = Dict(i => Set{Int64}([i]) for i in active_bus_ids)
    touched = Set{Int64}()

    for i in active_bus_ids
        if !(i in touched)
            _dfs(i, neighbors, component_lookup, touched)
        end
    end

    ccs = (Set(values(component_lookup)))

    return ccs
end


"""
performs DFS on a graph
"""
function _dfs(i, neighbors, component_lookup, touched)
    push!(touched, i)
    for j in neighbors[i]
        if !(j in touched)
            new_comp = union(component_lookup[i], component_lookup[j])
            for k in new_comp
                component_lookup[k] = new_comp
            end
            _dfs(j, neighbors, component_lookup, touched)
        end
    end
end

"find the largest active generator in the network"
function biggest_generator(gens)
    biggest_gen = nothing
    biggest_value = -Inf
    for (k,gen) in gens
        pmax = maximum(gen["pmax"])
        if pmax > biggest_value
            biggest_gen = gen
            biggest_value = pmax
        end
    end
    @assert(biggest_gen != nothing)
    return biggest_gen
end


"compute bus pair level structures"
function buspair_parameters(arcs_from, branches, buses, conductor_ids, ismulticondcutor)
    buspair_indexes = collect(Set([(i,j) for (l,i,j) in arcs_from]))

    bp_branch = Dict((bp, typemax(Int64)) for bp in buspair_indexes)

    if ismulticondcutor
        bp_angmin = Dict((bp, MultiConductorVector([-Inf for c in conductor_ids])) for bp in buspair_indexes)
        bp_angmax = Dict((bp, MultiConductorVector([ Inf for c in conductor_ids])) for bp in buspair_indexes)
    else
        @assert(length(conductor_ids) == 1)
        bp_angmin = Dict((bp, -Inf) for bp in buspair_indexes)
        bp_angmax = Dict((bp,  Inf) for bp in buspair_indexes)
    end

    for (l,branch) in branches
        i = branch["f_bus"]
        j = branch["t_bus"]

        if ismulticondcutor
            for c in conductor_ids
                bp_angmin[(i,j)][c] = max(bp_angmin[(i,j)][c], branch["angmin"][c])
                bp_angmax[(i,j)][c] = min(bp_angmax[(i,j)][c], branch["angmax"][c])
            end
        else
            bp_angmin[(i,j)] = max(bp_angmin[(i,j)], branch["angmin"])
            bp_angmax[(i,j)] = min(bp_angmax[(i,j)], branch["angmax"])
        end

        bp_branch[(i,j)] = min(bp_branch[(i,j)], l)
    end

    buspairs = Dict(((i,j), Dict{String,Any}(
        "branch"=>bp_branch[(i,j)],
        "angmin"=>bp_angmin[(i,j)],
        "angmax"=>bp_angmax[(i,j)],
        "tap"=>branches[bp_branch[(i,j)]]["tap"],
        "vm_fr_min"=>buses[i]["vmin"],
        "vm_fr_max"=>buses[i]["vmax"],
        "vm_to_min"=>buses[j]["vmin"],
        "vm_to_max"=>buses[j]["vmax"]
        )) for (i,j) in buspair_indexes
    )

    # add optional parameters
    for bp in buspair_indexes
        branch = branches[bp_branch[bp]]
        if haskey(branch, "rate_a")
            buspairs[bp]["rate_a"] = branch["rate_a"]
        end
        if haskey(branch, "c_rating_a")
            buspairs[bp]["c_rating_a"] = branch["c_rating_a"]
        end
    end

    return buspairs
end

# end
