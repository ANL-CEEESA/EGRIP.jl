# get values from optimization variables with less or equal to two dimension
function get_value(A)
    n_dim = ndims(A)
    if n_dim == 1
        if axes(A)[1] isa Base.KeySet
            # Input variable use dict key as axis"
            solution_value = Dict()
            for i in axes(A)[1]
                solution_value[i] = value(A[i])
            end
        else
            # Input variable use time steps as axis"
            solution_value = []
            for i in axes(A)[1]
                push!(solution_value, value(A[i]))
            end
        end
    elseif n_dim == 2
        solution_value = Dict()
        for i in axes(A)[1]
            solution_value[i] = []
            for j in axes(A)[2]
                push!(solution_value[i], value(A[i,j]))
            end
        end
    else
        println("Currently does not support higher dimensional variables")
    end
    return solution_value
end

function check_load(ref)
    for k in keys(ref[:load])
        if ref[:load][k]["pd"] <= 0
            println("Load bus: ", ref[:load][k]["load_bus"], ", active power: ", ref[:load][k]["pd"])
        end
    end
end

function density_est_from_risk(data, risk, histogram_approximation_number)
    # interpolate
    itp = interpolate((data,), risk, Gridded(Linear()))

    # discretize the risk level
    data_sample = range(minimum(data), maximum(data), length=histogram_approximation_number)
    data_hist = Dict()
    data_hist["a"] = Float64[]
    data_hist["b"] = Float64[]
    data_hist["ab"] = Float64[]
    data_hist["p"] = Float64[]
    for i in range(1, stop=histogram_approximation_number-1, length=histogram_approximation_number-1)
        i = Int(i)
        a = data_sample[i]
        b = data_sample[i + 1]
        push!(data_hist["a"], a)
        push!(data_hist["b"], b)
        push!(data_hist["ab"], (a + b)/2)
        itp_a = itp(a)
        itp_b = itp(b)
        itp_avg = (itp_a + itp_b)/2
        push!(data_hist["p"], itp_avg)
    end

    # estimate the histogram
    data_hist["d"] = Float64[]
    for i in range(1, stop=histogram_approximation_number-2, length=histogram_approximation_number-2)
        i = Int(i)
        height = (data_hist["p"][i] - data_hist["p"][i + 1])/(data_hist["b"][i] - data_hist["a"][i])
        push!(data_hist["d"], height)
    end

    return data_hist
end


function form_gen_plan_enforce(model, ref, stages, plan_gen)

    println("Formulating generator plan enforcement constraint")

    for t in stages
        for g in keys(ref[:gen])
            t = Int(t)
            g = Int(g)

            if plan_gen[g][t] == 0
                @constraint(model, model[:y][g,t] == 0)
                @constraint(model, model[:pg][g,t] == plan_gen[g][t])
            elseif plan_gen[g][t] <= 0
                @constraint(model, model[:y][g,t] == 1)
                @constraint(model, model[:pg][g,t] == plan_gen[g][t])
            elseif plan_gen[g][t] >= 0
                @constraint(model, model[:y][g,t] == 1)
                @constraint(model, model[:pg][g,t] <= plan_gen[g][t])
                @constraint(model, model[:pg][g,t] >= 0)
            end

            # # reactive power limits associated with the generator status
            @constraint(model, model[:qg][g,t] >= ref[:gen][g]["qmin"] * model[:y][g,t])
            @constraint(model, model[:qg][g,t] <= ref[:gen][g]["qmax"] * model[:y][g,t])
        end

        # define the total generation
        @constraint(model, model[:pg_total][t] == sum(model[:pg][g,t] for g in keys(ref[:gen])))
    end

    return model
end

function form_load_plan_enforce(model, ref, stages, plan_load)

    println("Formulating load plan enforcement constraint")

    # generate an array of the plan_load key
    key_plan_load = [k for (k,v) in plan_load]

    for t in stages
        for i in keys(ref[:load])
            t = Int(t)
            i = Int(i)
            pl = model[:pl]
            u = model[:u]
            
            # check if the load is a critical load
            # only critical load is in the plan
            if isempty(findall(x->x==i, key_plan_load))
                # not in the plan: make the load dispatch if the bus is energized

                # find bus index
                idx_bus = ref[:load][i]["load_bus"]
                @constraint(model, pl[i,t] >= 0)
                @constraint(model, pl[i,t] <= ref[:load][i]["pd"] * u[idx_bus,t])
            else
                # otherwise: enforce status
                @constraint(model, model[:pl][i,t] == plan_load[i][t])      
            end

            
        end
    end
    
    return model
end


function form_bus_plan_enforce(model, ref, stages, plan_bus)

    println("Formulating bus plan enforcement constraint")

    for t in stages
        for b in keys(ref[:bus])
            t = Int(t)
            b = Int(b)
            # enforce status
            @constraint(model, model[:u][b,t] == plan_bus[b][t])
        end
    end
    
    return model
end