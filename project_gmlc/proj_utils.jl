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
        solution_value = sort!(OrderedDict(solution_value)) # order the dict based on the key
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
