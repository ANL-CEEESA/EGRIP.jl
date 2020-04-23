
# # If we use module, then it is convenient to export
# # If we do not use module, then it is not necessary to export
# module ReadMFile
# export parse_mfile  # Either we export this function or we use ReadMFile.parse_mfile

using LinearAlgebra, Memento

"checks if a given network data is a multinetwork"
ismultinetwork(data::Dict{String,Any}) = (haskey(data, "multinetwork") && data["multinetwork"] == true)

# Create our module level logger (this will get precompiled)
const LOGGER = getlogger(@__MODULE__)

function parse_matlab_string(data_string::String; extended=false)
    data_lines = split(data_string, '\n')

    matlab_dict = Dict{String,Any}()
    struct_name = nothing
    function_name = nothing
    column_names = Dict{String,Any}()

    last_index = length(data_lines)
    index = 1
    while index <= last_index
        line = strip(data_lines[index])
        # line = "$(line)"

        # if length(line) <= 0 || strip(line)[1] == '%'
        if length(line) <= 0 || line[1] == '%'
            index = index + 1
            continue
        end

        if occursin("function", line)
            func, value = extract_matlab_assignment(line)
            struct_name = strip(replace(func, "function" => ""))
            function_name = value
        elseif occursin("=",line)
            if struct_name != nothing && !occursin("$(struct_name).", line)
                warn(LOGGER, "assignments are expected to be made to \"$(struct_name)\" but given: $(line)")
            end

            if occursin("[", line)
                matrix_dict = parse_matlab_matrix(data_lines, index)
                matlab_dict[matrix_dict["name"]] = matrix_dict["data"]
                if haskey(matrix_dict, "column_names")
                    column_names[matrix_dict["name"]] = matrix_dict["column_names"]
                end
                index = index + matrix_dict["line_count"]-1
            elseif occursin("{", line)
                cell_dict = parse_matlab_cells(data_lines, index)
                matlab_dict[cell_dict["name"]] = cell_dict["data"]
                if haskey(cell_dict, "column_names")
                    column_names[cell_dict["name"]] = cell_dict["column_names"]
                end
                index = index + cell_dict["line_count"]-1
            else
                name, value = extract_matlab_assignment(line)
                value = type_value(value)
                matlab_dict[name] = value
            end
        else
            warn(LOGGER, "Matlab parser skipping the following line:\n  $(line)")
        end

        index += 1
    end

    if extended
        return matlab_dict, function_name, column_names
    else
        return matlab_dict
    end
end

function extract_matlab_assignment(string::AbstractString)
    statement = split(string, ';')[1]
    statement_parts = split(statement, '=')
    @assert(length(statement_parts) == 2)
    name = strip(statement_parts[1])
    value = strip(statement_parts[2])
    return name, value
end

"Attempts to determine the type of a string extracted from a matlab file"
function type_value(value_string::AbstractString)
    value_string = strip(value_string)

    if occursin("'", value_string) # value is a string
        value = strip(value_string, '\'')
    else
        # if value is a float
        if occursin(".", value_string) || occursin("e", value_string)
            value = check_type(Float64, value_string)
        else # otherwise assume it is an int
            value = check_type(Int, value_string)
        end
    end

    return value
end

"Attempts to determine the type of an array of strings extracted from a matlab file"
function type_array(string_array::Vector{T}) where {T <: AbstractString}
    value_string = [strip(value_string) for value_string in string_array]

    return if any(occursin("'",value_string) for value_string in string_array)
        [strip(value_string, '\'') for value_string in string_array]
    elseif any(occursin(".", value_string) || occursin("e", value_string) for value_string in string_array)
        [check_type(Float64, value_string) for value_string in string_array]
    else # otherwise assume it is an int
        [check_type(Int, value_string) for value_string in string_array]
    end
end


""
parse_matlab_cells(lines, index) = parse_matlab_data(lines, index, '{', '}')

""
parse_matlab_matrix(lines, index) = parse_matlab_data(lines, index, '[', ']')

""
function parse_matlab_data(lines, index, start_char, end_char)
    last_index = length(lines)
    line_count = 0
    columns = -1

    @assert(occursin("=",lines[index+line_count]))
    matrix_assignment = split(lines[index+line_count], '%')[1]
    matrix_assignment = strip(matrix_assignment)

    @assert(occursin(".",matrix_assignment))
    matrix_assignment_parts = split(matrix_assignment, '=')
    matrix_name = strip(matrix_assignment_parts[1])

    matrix_assignment_rhs = ""
    if length(matrix_assignment_parts) > 1
        matrix_assignment_rhs = strip(matrix_assignment_parts[2])
    end

    line_count = line_count + 1
    matrix_body_lines = [matrix_assignment_rhs]
    found_close_bracket = occursin(string(end_char),matrix_assignment_rhs)

    while index + line_count < last_index && !found_close_bracket
        line = strip(lines[index+line_count])

        if length(line) == 0 || line[1] == '%'
            line_count += 1
            continue
        end

        line = strip(split(line, '%')[1])

        if occursin(string(end_char),line)
            found_close_bracket = true
        end

        push!(matrix_body_lines, line)

        line_count = line_count + 1
    end

    #print(matrix_body_lines)
    matrix_body_lines = [add_line_delimiter(line, start_char, end_char) for line in matrix_body_lines]
    #print(matrix_body_lines)

    matrix_body = join(matrix_body_lines, ' ')
    matrix_body = strip(replace(strip(strip(matrix_body), start_char), "$(end_char);" => ""))
    matrix_body_rows = split(matrix_body, ';')
    matrix_body_rows = matrix_body_rows[1:(length(matrix_body_rows)-1)]

    matrix = []
    for row in matrix_body_rows
        row_items = split_line(strip(row))
        #println(row_items)
        push!(matrix, row_items)
        if columns < 0
            columns = length(row_items)
        elseif columns != length(row_items)
            error(LOGGER, "matrix parsing error, inconsistent number of items in each row\n$(row)")
        end
    end

    rows = length(matrix)
    typed_columns = [type_array([ matrix[r][c] for r in 1:rows ]) for c in 1:columns]
    for r in 1:rows
        matrix[r] = [typed_columns[c][r] for c in 1:columns]
    end


    matrix_dict = Dict("name" => matrix_name, "data" => matrix, "line_count" => line_count)

    if index > 1 && occursin("%column_names%", lines[index-1])
        column_names_string = lines[index-1]
        column_names_string = replace(column_names_string, "%column_names%" => "")
        column_names = split(column_names_string)
        if length(matrix[1]) != length(column_names)
            error(LOGGER, "column name parsing error, data rows $(length(matrix[1])), column names $(length(column_names)) \n$(column_names)")
        end
        if any([column_name == "index" for column_name in column_names])
            error(LOGGER, "column name parsing error, \"index\" is a reserved column name \n$(column_names)")
        end
        matrix_dict["column_names"] = column_names
    end

    return matrix_dict
end

const single_quote_expr = r"\'((\\.|[^\'])*?)\'"

""
function split_line(mp_line::AbstractString)
    if occursin(single_quote_expr, mp_line)
        # splits a string on white space while escaping text quoted with "'"
        # note that quotes will be stripped later, when data typing occurs

        #println(mp_line)
        tokens = []
        while length(mp_line) > 0 && occursin(single_quote_expr, mp_line)
            #println(mp_line)
            m = match(single_quote_expr, mp_line)

            if m.offset > 1
                push!(tokens, mp_line[1:m.offset-1])
            end
            push!(tokens, replace(m.match, "\\'" => "'")) # replace escaped quotes

            mp_line = mp_line[m.offset+length(m.match):end]
        end
        if length(mp_line) > 0
            push!(tokens, mp_line)
        end
        #println(tokens)

        items = []
        for token in tokens
            if occursin("'",token)
                push!(items, strip(token))
            else
                for parts in split(token)
                    push!(items, strip(parts))
                end
            end
        end
        #println(items)

        #return [strip(mp_line, '\'')]
        return items
    else
        return split(mp_line)
    end
end

""
function add_line_delimiter(mp_line::AbstractString, start_char, end_char)
    if strip(mp_line) == string(start_char)
        return mp_line
    end

    if !occursin(";",mp_line,) && !occursin(string(end_char),mp_line)
        mp_line = "$(mp_line);"
    end

    if occursin(string(end_char),mp_line)
        prefix = strip(split(mp_line, end_char)[1])
        if length(prefix) > 0 && ! occursin(";",prefix)
            mp_line = replace(mp_line, end_char => ";$(end_char)")
        end
    end

    return mp_line
end


"Checks if the given value is of a given type, if not tries to make it that type"
function check_type(typ, value)
    if isa(value, typ)
        return value
    elseif isa(value, String) || isa(value, SubString)
        try
            value = parse(typ, value)
            return value
        catch e
            error(LOGGER, "parsing error, the matlab string \"$(value)\" can not be parsed to $(typ) data")
            rethrow(e)
        end
    else
        try
            value = typ(value)
            return value
        catch e
            error(LOGGER, "parsing error, the matlab value $(value) of type $(typeof(value)) can not be parsed to $(typ) data")
            rethrow(e)
        end
    end
end

function row_to_typed_dict(row_data, columns)
    dict_data = Dict{String,Any}()
    for (i,v) in enumerate(row_data)
        if i <= length(columns)
            name, typ = columns[i]
            dict_data[name] = check_type(typ, v)
        else
            dict_data["col_$(i)"] = v
        end
    end
    return dict_data
end

"takes a row from a matrix and assigns the values names"
function row_to_dict(row_data, columns)
    dict_data = Dict{String,Any}()
    for (i,v) in enumerate(row_data)
        if i <= length(columns)
            dict_data[columns[i]] = v
        else
            dict_data["col_$(i)"] = v
        end
    end
    return dict_data
end

row_to_dict(row_data) = row_to_dict(row_data, [])














"Parses the matpower data from either a filename or an IO object"
function parse_mfile(file::Union{IO, String}; validate=true)
    mp_data = parse_matpower_file(file)
    pm_data = matpower_to_powermodels(mp_data)
    if validate
        check_network_data(pm_data)
    end
    return pm_data
end


### Data and functions specific to Matpower format ###
mp_data_names = ["mpc.version", "mpc.baseMVA", "mpc.bus", "mpc.gen",
"mpc.branch", "mpc.dcline", "mpc.gencost", "mpc.dclinecost",
"mpc.bus_name", "mpc.storage"
]

mp_bus_columns = [
("bus_i", Int),
("bus_type", Int),
("pd", Float64), ("qd", Float64),
("gs", Float64), ("bs", Float64),
("area", Int),
("vm", Float64), ("va", Float64),
("base_kv", Float64),
("zone", Int),
("vmax", Float64), ("vmin", Float64),
("lam_p", Float64), ("lam_q", Float64),
("mu_vmax", Float64), ("mu_vmin", Float64)
]

mp_bus_name_columns = [
("bus_name", Union{String,SubString{String}})
]

mp_gen_columns = [
("gen_bus", Int),
("pg", Float64), ("qg", Float64),
("qmax", Float64), ("qmin", Float64),
("vg", Float64),
("mbase", Float64),
("gen_status", Int),
("pmax", Float64), ("pmin", Float64),
("pc1", Float64),
("pc2", Float64),
("qc1min", Float64), ("qc1max", Float64),
("qc2min", Float64), ("qc2max", Float64),
("ramp_agc", Float64),
("ramp_10", Float64),
("ramp_30", Float64),
("ramp_q", Float64),
("apf", Float64),
("mu_pmax", Float64), ("mu_pmin", Float64),
("mu_qmax", Float64), ("mu_qmin", Float64)
]

mp_branch_columns = [
("f_bus", Int),
("t_bus", Int),
("br_r", Float64), ("br_x", Float64),
("br_b", Float64),
("rate_a", Float64),
("rate_b", Float64),
("rate_c", Float64),
("tap", Float64), ("shift", Float64),
("br_status", Int),
("angmin", Float64), ("angmax", Float64),
("pf", Float64), ("qf", Float64),
("pt", Float64), ("qt", Float64),
("mu_sf", Float64), ("mu_st", Float64),
("mu_angmin", Float64), ("mu_angmax", Float64)
]

mp_dcline_columns = [
("f_bus", Int),
("t_bus", Int),
("br_status", Int),
("pf", Float64), ("pt", Float64),
("qf", Float64), ("qt", Float64),
("vf", Float64), ("vt", Float64),
("pmin", Float64), ("pmax", Float64),
("qminf", Float64), ("qmaxf", Float64),
("qmint", Float64), ("qmaxt", Float64),
("loss0", Float64),
("loss1", Float64),
("mu_pmin", Float64), ("mu_pmax", Float64),
("mu_qminf", Float64), ("mu_qmaxf", Float64),
("mu_qmint", Float64), ("mu_qmaxt", Float64)
]

mp_storage_columns = [
("storage_bus", Int),
("energy", Float64), ("energy_rating", Float64),
("charge_rating", Float64), ("discharge_rating", Float64),
("charge_efficiency", Float64), ("discharge_efficiency", Float64),
("thermal_rating", Float64),
("qmin", Float64), ("qmax", Float64),
("r", Float64), ("x", Float64),
("standby_loss", Float64),
("status", Int)
]


""
function parse_matpower_file(file_string::String)
    mp_data = open(file_string) do io
        parse_matpower_file(io)
    end

    return mp_data
end


""
function parse_matpower_file(io::IO)
    data_string = read(io, String)

    return parse_matpower_string(data_string)
end


""
function parse_matpower_string(data_string::String)
    matlab_data, func_name, colnames = parse_matlab_string(data_string, extended=true)

    case = Dict{String,Any}()

    if func_name != nothing
        case["name"] = func_name
    else
        warn(LOGGER, string("no case name found in matpower file.  The file seems to be missing \"function mpc = ...\""))
        case["name"] = "no_name_found"
    end

    case["source_type"] = "matpower"
    if haskey(matlab_data, "mpc.version")
        case["source_version"] = VersionNumber(matlab_data["mpc.version"])
    else
        warn(LOGGER, string("no case version found in matpower file.  The file seems to be missing \"mpc.version = ...\""))
        case["source_version"] = "0.0.0+"
    end

    if haskey(matlab_data, "mpc.baseMVA")
        case["baseMVA"] = matlab_data["mpc.baseMVA"]
    else
        warn(LOGGER, string("no baseMVA found in matpower file.  The file seems to be missing \"mpc.baseMVA = ...\""))
        case["baseMVA"] = 1.0
    end


    if haskey(matlab_data, "mpc.bus")
        buses = []
        for bus_row in matlab_data["mpc.bus"]
            bus_data = row_to_typed_dict(bus_row, mp_bus_columns)
            bus_data["index"] = check_type(Int, bus_row[1])
            push!(buses, bus_data)
        end
        case["bus"] = buses
    else
        error(string("no bus table found in matpower file.  The file seems to be missing \"mpc.bus = [...];\""))
    end

    if haskey(matlab_data, "mpc.gen")
        gens = []
        for (i, gen_row) in enumerate(matlab_data["mpc.gen"])
            gen_data = row_to_typed_dict(gen_row, mp_gen_columns)
            gen_data["index"] = i
            push!(gens, gen_data)
        end
        case["gen"] = gens
    else
        error(string("no gen table found in matpower file.  The file seems to be missing \"mpc.gen = [...];\""))
    end

    if haskey(matlab_data, "mpc.branch")
        branches = []
        for (i, branch_row) in enumerate(matlab_data["mpc.branch"])
            branch_data = row_to_typed_dict(branch_row, mp_branch_columns)
            branch_data["index"] = i
            push!(branches, branch_data)
        end
        case["branch"] = branches
    else
        error(string("no branch table found in matpower file.  The file seems to be missing \"mpc.branch = [...];\""))
    end

    if haskey(matlab_data, "mpc.dcline")
        dclines = []
        for (i, dcline_row) in enumerate(matlab_data["mpc.dcline"])
            dcline_data = row_to_typed_dict(dcline_row, mp_dcline_columns)
            dcline_data["index"] = i
            push!(dclines, dcline_data)
        end
        case["dcline"] = dclines
    end

    if haskey(matlab_data, "mpc.storage")
        storage = []
        for (i, storage_row) in enumerate(matlab_data["mpc.storage"])
            storage_data = row_to_typed_dict(storage_row, mp_storage_columns)
            storage_data["index"] = i
            push!(storage, storage_data)
        end
        case["storage"] = storage
    end


    if haskey(matlab_data, "mpc.bus_name")
        bus_names = []
        for (i, bus_name_row) in enumerate(matlab_data["mpc.bus_name"])
            bus_name_data = row_to_typed_dict(bus_name_row, mp_bus_name_columns)
            bus_name_data["index"] = i
            push!(bus_names, bus_name_data)
        end
        case["bus_name"] = bus_names

        if length(case["bus_name"]) != length(case["bus"])
            error(LOGGER, "incorrect Matpower file, the number of bus names ($(length(case["bus_name"]))) is inconsistent with the number of buses ($(length(case["bus"]))).\n")
        end
    end

    if haskey(matlab_data, "mpc.gencost")
        gencost = []
        for (i, gencost_row) in enumerate(matlab_data["mpc.gencost"])
            gencost_data = mp_cost_data(gencost_row)
            gencost_data["index"] = i
            push!(gencost, gencost_data)
        end
        case["gencost"] = gencost

        if length(case["gencost"]) != length(case["gen"]) && length(case["gencost"]) != 2*length(case["gen"])
            error(LOGGER, "incorrect Matpower file, the number of generator cost functions ($(length(case["gencost"]))) is inconsistent with the number of generators ($(length(case["gen"]))).\n")
        end
    end

    if haskey(matlab_data, "mpc.dclinecost")
        dclinecosts = []
        for (i, dclinecost_row) in enumerate(matlab_data["mpc.dclinecost"])
            dclinecost_data = mp_cost_data(dclinecost_row)
            dclinecost_data["index"] = i
            push!(dclinecosts, dclinecost_data)
        end
        case["dclinecost"] = dclinecosts

        if length(case["dclinecost"]) != length(case["dcline"])
            error(LOGGER, "incorrect Matpower file, the number of dcline cost functions ($(length(case["dclinecost"]))) is inconsistent with the number of dclines ($(length(case["dcline"]))).\n")
        end
    end

    for k in keys(matlab_data)
        if !in(k, mp_data_names) && startswith(k, "mpc.")
            case_name = k[5:length(k)]
            value = matlab_data[k]
            if isa(value, Array)
                column_names = []
                if haskey(colnames, k)
                    column_names = colnames[k]
                end
                tbl = []
                for (i, row) in enumerate(matlab_data[k])
                    row_data = row_to_dict(row, column_names)
                    row_data["index"] = i
                    push!(tbl, row_data)
                end
                case[case_name] = tbl
                @info(LOGGER, "extending matpower format with data: $(case_name) $(length(tbl))x$(length(tbl[1])-1)")
            else
                case[case_name] = value
                @info(LOGGER, "extending matpower format with constant data: $(case_name)")
            end
        end
    end

    return case
end


""
function mp_cost_data(cost_row)
    ncost = cost_row[4]
    model = cost_row[1]
    if model == 1
        nr_parameters = ncost*2
    elseif model == 2
        nr_parameters = ncost
    end
    cost_data = Dict{String,Any}(
    "model" => check_type(Int, cost_row[1]),
    "startup" => check_type(Float64, cost_row[2]),
    "shutdown" => check_type(Float64, cost_row[3]),
    "ncost" => check_type(Int, cost_row[4]),
    "cost" => [check_type(Float64, x) for x in cost_row[5:5+nr_parameters-1]]
    )
    return cost_data
end



### Data and functions specific to PowerModels format ###

"""
Converts a Matpower dict into a PowerModels dict
"""
function matpower_to_powermodels(mp_data::Dict{String,Any})
    pm_data = deepcopy(mp_data)

    # required default values
    if !haskey(pm_data, "dcline")
        pm_data["dcline"] = []
    end
    if !haskey(pm_data, "gencost")
        pm_data["gencost"] = []
    end
    if !haskey(pm_data, "dclinecost")
        pm_data["dclinecost"] = []
    end
    if !haskey(pm_data, "storage")
        pm_data["storage"] = []
    end

    # translate component models
    mp2pm_branch(pm_data)
    mp2pm_dcline(pm_data)

    # translate cost models
    add_dcline_costs(pm_data)

    # merge data tables
    merge_bus_name_data(pm_data)
    merge_generator_cost_data(pm_data)
    merge_generic_data(pm_data)

    # split loads and shunts from buses
    split_loads_shunts(pm_data)

    # use once available
    arrays_to_dicts!(pm_data)

    for optional in ["dcline", "load", "shunt", "storage"]
        if length(pm_data[optional]) == 0
            pm_data[optional] = Dict{String,Any}()
        end
    end

    return pm_data
end


"""
split_loads_shunts(data)
Seperates Loads and Shunts in `data` under separate "load" and "shunt" keys in the
PowerModels data format. Includes references to originating bus via "load_bus"
and "shunt_bus" keys, respectively.
"""
function split_loads_shunts(data::Dict{String,Any})
    data["load"] = []
    data["shunt"] = []

    load_num = 1
    shunt_num = 1
    for (i,bus) in enumerate(data["bus"])
        if bus["pd"] != 0.0 || bus["qd"] != 0.0
            append!(data["load"], [Dict{String,Any}("pd" => bus["pd"],
            "qd" => bus["qd"],
            "load_bus" => bus["bus_i"],
            "status" => convert(Int8, bus["bus_type"] != 4),
            "index" => load_num)])
            load_num += 1
        end

        if bus["gs"] != 0.0 || bus["bs"] != 0.0
            append!(data["shunt"], [Dict{String,Any}("gs" => bus["gs"],
            "bs" => bus["bs"],
            "shunt_bus" => bus["bus_i"],
            "status" => convert(Int8, bus["bus_type"] != 4),
            "index" => shunt_num)])
            shunt_num += 1
        end

        for key in ["pd", "qd", "gs", "bs"]
            delete!(bus, key)
        end
    end
end


"sets all branch transformer taps to 1.0, to simplify branch models"
function mp2pm_branch(data::Dict{String,Any})
    branches = [branch for branch in data["branch"]]
    if haskey(data, "ne_branch")
        append!(branches, data["ne_branch"])
    end
    for branch in branches
        if branch["tap"] == 0.0
            branch["transformer"] = false
            branch["tap"] = 1.0
        else
            branch["transformer"] = true
        end

        branch["g_fr"] = 0.0
        branch["g_to"] = 0.0

        branch["b_fr"] = branch["br_b"] / 2.0
        branch["b_to"] = branch["br_b"] / 2.0

        delete!(branch, "br_b")

        if branch["rate_a"] == 0.0
            delete!(branch, "rate_a")
        end
        if branch["rate_b"] == 0.0
            delete!(branch, "rate_b")
        end
        if branch["rate_c"] == 0.0
            delete!(branch, "rate_c")
        end
    end
end


"adds pmin and pmax values at to and from buses"
function mp2pm_dcline(data::Dict{String,Any})
    for dcline in data["dcline"]
        pmin = dcline["pmin"]
        pmax = dcline["pmax"]
        loss0 = dcline["loss0"]
        loss1 = dcline["loss1"]

        delete!(dcline, "pmin")
        delete!(dcline, "pmax")

        if pmin >= 0 && pmax >=0
            pminf = pmin
            pmaxf = pmax
            pmint = loss0 - pmaxf * (1 - loss1)
            pmaxt = loss0 - pminf * (1 - loss1)
        end
        if pmin >= 0 && pmax < 0
            pminf = pmin
            pmint = pmax
            pmaxf = (-pmint + loss0) / (1-loss1)
            pmaxt = loss0 - pminf * (1 - loss1)
        end
        if pmin < 0 && pmax >= 0
            pmaxt = -pmin
            pmaxf = pmax
            pminf = (-pmaxt + loss0) / (1-loss1)
            pmint = loss0 - pmaxf * (1 - loss1)
        end
        if pmin < 0 && pmax < 0
            pmaxt = -pmin
            pmint = pmax
            pmaxf = (-pmint + loss0) / (1-loss1)
            pminf = (-pmaxt + loss0) / (1-loss1)
        end

        dcline["pmaxt"] = pmaxt
        dcline["pmint"] = pmint
        dcline["pmaxf"] = pmaxf
        dcline["pminf"] = pminf

        # preserve the old pmin and pmax values
        dcline["mp_pmin"] = pmin
        dcline["mp_pmax"] = pmax

        dcline["pt"] = -dcline["pt"] # matpower has opposite convention
        dcline["qf"] = -dcline["qf"] # matpower has opposite convention
        dcline["qt"] = -dcline["qt"] # matpower has opposite convention
    end
end


"adds dcline costs, if gen costs exist"
function add_dcline_costs(data::Dict{String,Any})
    if length(data["gencost"]) > 0 && length(data["dclinecost"]) <= 0 && length(data["dcline"]) > 0
        warn(LOGGER, "added zero cost function data for dclines")
        model = data["gencost"][1]["model"]
        if model == 1
            for (i, dcline) in enumerate(data["dcline"])
                dclinecost = Dict(
                "index" => i,
                "model" => 1,
                "startup" => 0.0,
                "shutdown" => 0.0,
                "ncost" => 2,
                "cost" => [dcline["pminf"], 0.0, dcline["pmaxf"], 0.0]
                )
                push!(data["dclinecost"], dclinecost)
            end
        else
            for (i, dcline) in enumerate(data["dcline"])
                dclinecost = Dict(
                "index" => i,
                "model" => 2,
                "startup" => 0.0,
                "shutdown" => 0.0,
                "ncost" => 3,
                "cost" => [0.0, 0.0, 0.0]
                )
                push!(data["dclinecost"], dclinecost)
            end
        end
    end
end


"merges generator cost functions into generator data, if costs exist"
function merge_generator_cost_data(data::Dict{String,Any})
    if haskey(data, "gencost")
        for (i, gencost) in enumerate(data["gencost"])
            gen = data["gen"][i]
            @assert(gen["index"] == gencost["index"])
            delete!(gencost, "index")

            check_keys(gen, keys(gencost))
            merge!(gen, gencost)
        end
        delete!(data, "gencost")
    end

    if haskey(data, "dclinecost")
        for (i, dclinecost) in enumerate(data["dclinecost"])
            dcline = data["dcline"][i]
            @assert(dcline["index"] == dclinecost["index"])
            delete!(dclinecost, "index")

            check_keys(dcline, keys(dclinecost))
            merge!(dcline, dclinecost)
        end
        delete!(data, "dclinecost")
    end
end


"merges bus name data into buses, if names exist"
function merge_bus_name_data(data::Dict{String,Any})
    if haskey(data, "bus_name")
        # can assume same length is same as bus
        # this is validated during matpower parsing
        for (i, bus_name) in enumerate(data["bus_name"])
            bus = data["bus"][i]
            delete!(bus_name, "index")

            check_keys(bus, keys(bus_name))
            merge!(bus, bus_name)
        end
        delete!(data, "bus_name")
    end
end


"merges Matpower tables based on the table extension syntax"
function merge_generic_data(data::Dict{String,Any})
    mp_matrix_names = [name[5:length(name)] for name in mp_data_names]

    key_to_delete = []
    for (k,v) in data
        if isa(v, Array)
            for mp_name in mp_matrix_names
                if startswith(k, "$(mp_name)_")
                    mp_matrix = data[mp_name]
                    push!(key_to_delete, k)

                    if length(mp_matrix) != length(v)
                        error(LOGGER, "failed to extend the matpower matrix \"$(mp_name)\" with the matrix \"$(k)\" because they do not have the same number of rows, $(length(mp_matrix)) and $(length(v)) respectively.")
                    end

                    @info(LOGGER, "extending matpower format by appending matrix \"$(k)\" in to \"$(mp_name)\"")

                    for (i, row) in enumerate(mp_matrix)
                        merge_row = v[i]
                        #@assert(row["index"] == merge_row["index"]) # note this does not hold for the bus table
                        delete!(merge_row, "index")
                        for key in keys(merge_row)
                            if haskey(row, key)
                                error(LOGGER, "failed to extend the matpower matrix \"$(mp_name)\" with the matrix \"$(k)\" because they both share \"$(key)\" as a column name.")
                            end
                            row[key] = merge_row[key]
                        end
                    end

                    break # out of mp_matrix_names loop
                end
            end

        end
    end

    for key in key_to_delete
        delete!(data, key)
    end
end

""
function check_keys(data, keys)
    for key in keys
        if haskey(data, key)
            error(LOGGER, "attempting to overwrite value of $(key) in PowerModels data,\n$(data)")
        end
    end
end

"turns top level arrays into dicts"
function arrays_to_dicts!(data::Dict{String,Any})
    # update lookup structure
    for (k,v) in data
        if isa(v, Array) && length(v) > 0 && isa(v[1], Dict)
            #println("updating $(k)")
            dict = Dict{String,Any}()
            for (i,item) in enumerate(v)
                if haskey(item, "index")
                    key = string(item["index"])
                else
                    key = string(i)
                end

                if !(haskey(dict, key))
                    dict[key] = item
                else
                    warn(LOGGER, "skipping component $(item["index"]) from the $(k) table because a component with the same id already exists")
                end
            end
            data[k] = dict
        end
    end
end









































"""
Runs various data quality checks on a PowerModels data dictionary.
Applies modifications in some cases.  Reports modified component ids.
"""
function check_network_data(data::Dict{String,Any})
    mod_bus = Dict{Symbol,Set{Int}}()
    mod_gen = Dict{Symbol,Set{Int}}()
    mod_branch = Dict{Symbol,Set{Int}}()
    mod_dcline = Dict{Symbol,Set{Int}}()

    check_conductors(data)
    make_per_unit(data)
    check_connectivity(data)

    mod_branch[:xfer_fix] = check_transformer_parameters(data)
    mod_branch[:vad_bounds] = check_voltage_angle_differences(data)
    mod_branch[:mva_zero] = check_thermal_limits(data)
    mod_branch[:orientation] = check_branch_directions(data)
    check_branch_loops(data)

    mod_dcline[:losses] = check_dcline_limits(data)

    mod_bus[:type] = check_bus_types(data)
    check_voltage_setpoints(data)

    check_storage_parameters(data)

    gen, dcline = check_cost_functions(data)
    mod_gen[:cost_pwl] = gen
    mod_dcline[:cost_pwl] = dcline

    simplify_cost_terms(data)

    return Dict(
        "bus" => mod_bus,
        "gen" => mod_gen,
        "branch" => mod_branch,
        "dcline" => mod_dcline
    )
end

""
function apply_func(data::Dict{String,Any}, key::String, func)
    if haskey(data, key)
        data[key] = func(data[key])
    end
end

"Transforms network data into per-unit"
function make_per_unit(data::Dict{String,Any})
    if !haskey(data, "per_unit") || data["per_unit"] == false
        data["per_unit"] = true
        mva_base = data["baseMVA"]
        if ismultinetwork(data)
            for (i,nw_data) in data["nw"]
                _make_per_unit(nw_data, mva_base)
            end
        else
            _make_per_unit(data, mva_base)
        end
    end
end


""
function _make_per_unit(data::Dict{String,Any}, mva_base::Real)
    # to be consistent with matpower's opf.flow_lim= 'I' with current magnitude
    # limit defined in MVA at 1 p.u. voltage
    ka_base = mva_base

    rescale        = x -> x/mva_base
    rescale_dual   = x -> x*mva_base
    rescale_ampere = x -> x/ka_base


    if haskey(data, "bus")
        for (i, bus) in data["bus"]
            apply_func(bus, "va", deg2rad)

            apply_func(bus, "lam_kcl_r", rescale_dual)
            apply_func(bus, "lam_kcl_i", rescale_dual)
        end
    end

    if haskey(data, "load")
        for (i, load) in data["load"]
            apply_func(load, "pd", rescale)
            apply_func(load, "qd", rescale)
        end
    end

    if haskey(data, "shunt")
        for (i, shunt) in data["shunt"]
            apply_func(shunt, "gs", rescale)
            apply_func(shunt, "bs", rescale)
        end
    end

    if haskey(data, "gen")
        for (i, gen) in data["gen"]
            apply_func(gen, "pg", rescale)
            apply_func(gen, "qg", rescale)

            apply_func(gen, "pmax", rescale)
            apply_func(gen, "pmin", rescale)

            apply_func(gen, "qmax", rescale)
            apply_func(gen, "qmin", rescale)

            _rescale_cost_model(gen, mva_base)
        end
    end

    if haskey(data, "storage")
        for (i, strg) in data["storage"]
            apply_func(strg, "energy", rescale)
            apply_func(strg, "energy_rating", rescale)
            apply_func(strg, "charge_rating", rescale)
            apply_func(strg, "discharge_rating", rescale)
            apply_func(strg, "thermal_rating", rescale)
            apply_func(strg, "current_rating", rescale)
            apply_func(strg, "qmin", rescale)
            apply_func(strg, "qmax", rescale)
            apply_func(strg, "standby_loss", rescale)
        end
    end


    branches = []
    if haskey(data, "branch")
        append!(branches, values(data["branch"]))
    end

    if haskey(data, "ne_branch")
        append!(branches, values(data["ne_branch"]))
    end

    for branch in branches
        apply_func(branch, "rate_a", rescale)
        apply_func(branch, "rate_b", rescale)
        apply_func(branch, "rate_c", rescale)

        apply_func(branch, "c_rating_a", rescale_ampere)
        apply_func(branch, "c_rating_b", rescale_ampere)
        apply_func(branch, "c_rating_c", rescale_ampere)

        apply_func(branch, "shift", deg2rad)
        apply_func(branch, "angmax", deg2rad)
        apply_func(branch, "angmin", deg2rad)

        apply_func(branch, "pf", rescale)
        apply_func(branch, "pt", rescale)
        apply_func(branch, "qf", rescale)
        apply_func(branch, "qt", rescale)

        apply_func(branch, "mu_sm_fr", rescale_dual)
        apply_func(branch, "mu_sm_to", rescale_dual)
    end

    if haskey(data, "dcline")
        for (i, dcline) in data["dcline"]
            apply_func(dcline, "loss0", rescale)
            apply_func(dcline, "pf", rescale)
            apply_func(dcline, "pt", rescale)
            apply_func(dcline, "qf", rescale)
            apply_func(dcline, "qt", rescale)
            apply_func(dcline, "pmaxt", rescale)
            apply_func(dcline, "pmint", rescale)
            apply_func(dcline, "pmaxf", rescale)
            apply_func(dcline, "pminf", rescale)
            apply_func(dcline, "qmaxt", rescale)
            apply_func(dcline, "qmint", rescale)
            apply_func(dcline, "qmaxf", rescale)
            apply_func(dcline, "qminf", rescale)

            _rescale_cost_model(dcline, mva_base)
        end
    end

end


"Transforms network data into mixed-units (inverse of per-unit)"
function make_mixed_units(data::Dict{String,Any})
    if haskey(data, "per_unit") && data["per_unit"] == true
        data["per_unit"] = false
        mva_base = data["baseMVA"]
        if InfrastructureModels.ismultinetwork(data)
            for (i,nw_data) in data["nw"]
                _make_mixed_units(nw_data, mva_base)
            end
        else
             _make_mixed_units(data, mva_base)
        end
    end
end


""
function _make_mixed_units(data::Dict{String,Any}, mva_base::Real)
    # to be consistent with matpower's opf.flow_lim= 'I' with current magnitude
    # limit defined in MVA at 1 p.u. voltage
    ka_base = mva_base

    rescale        = x -> x*mva_base
    rescale_dual   = x -> x/mva_base
    rescale_ampere = x -> x*ka_base

    if haskey(data, "bus")
        for (i, bus) in data["bus"]
            apply_func(bus, "va", rad2deg)

            apply_func(bus, "lam_kcl_r", rescale_dual)
            apply_func(bus, "lam_kcl_i", rescale_dual)
        end
    end

    if haskey(data, "load")
        for (i, load) in data["load"]
            apply_func(load, "pd", rescale)
            apply_func(load, "qd", rescale)
        end
    end

    if haskey(data, "shunt")
        for (i, shunt) in data["shunt"]
            apply_func(shunt, "gs", rescale)
            apply_func(shunt, "bs", rescale)
        end
    end

    if haskey(data, "gen")
        for (i, gen) in data["gen"]
            apply_func(gen, "pg", rescale)
            apply_func(gen, "qg", rescale)

            apply_func(gen, "pmax", rescale)
            apply_func(gen, "pmin", rescale)

            apply_func(gen, "qmax", rescale)
            apply_func(gen, "qmin", rescale)

            _rescale_cost_model(gen, 1.0/mva_base)
        end
    end

    if haskey(data, "storage")
        for (i, strg) in data["storage"]
            apply_func(strg, "energy", rescale)
            apply_func(strg, "energy_rating", rescale)
            apply_func(strg, "charge_rating", rescale)
            apply_func(strg, "discharge_rating", rescale)
            apply_func(strg, "thermal_rating", rescale)
            apply_func(strg, "current_rating", rescale)
            apply_func(strg, "qmin", rescale)
            apply_func(strg, "qmax", rescale)
            apply_func(strg, "standby_loss", rescale)
        end
    end


    branches = []
    if haskey(data, "branch")
        append!(branches, values(data["branch"]))
    end

    if haskey(data, "ne_branch")
        append!(branches, values(data["ne_branch"]))
    end

    for branch in branches
        apply_func(branch, "rate_a", rescale)
        apply_func(branch, "rate_b", rescale)
        apply_func(branch, "rate_c", rescale)

        apply_func(branch, "c_rating_a", rescale_ampere)
        apply_func(branch, "c_rating_b", rescale_ampere)
        apply_func(branch, "c_rating_c", rescale_ampere)

        apply_func(branch, "shift", rad2deg)
        apply_func(branch, "angmax", rad2deg)
        apply_func(branch, "angmin", rad2deg)

        apply_func(branch, "pf", rescale)
        apply_func(branch, "pt", rescale)
        apply_func(branch, "qf", rescale)
        apply_func(branch, "qt", rescale)

        apply_func(branch, "mu_sm_fr", rescale_dual)
        apply_func(branch, "mu_sm_to", rescale_dual)
    end

    if haskey(data, "dcline")
        for (i,dcline) in data["dcline"]
            apply_func(dcline, "loss0", rescale)
            apply_func(dcline, "pf", rescale)
            apply_func(dcline, "pt", rescale)
            apply_func(dcline, "qf", rescale)
            apply_func(dcline, "qt", rescale)
            apply_func(dcline, "pmaxt", rescale)
            apply_func(dcline, "pmint", rescale)
            apply_func(dcline, "pmaxf", rescale)
            apply_func(dcline, "pminf", rescale)
            apply_func(dcline, "qmaxt", rescale)
            apply_func(dcline, "qmint", rescale)
            apply_func(dcline, "qmaxf", rescale)
            apply_func(dcline, "qminf", rescale)

            _rescale_cost_model(dcline, 1.0/mva_base)
        end
    end

end


""
function _rescale_cost_model(comp::Dict{String,Any}, scale::Real)
    if "model" in keys(comp) && "cost" in keys(comp)
        if comp["model"] == 1
            for i in 1:2:length(comp["cost"])
                comp["cost"][i] = comp["cost"][i]/scale
            end
        elseif comp["model"] == 2
            degree = length(comp["cost"])
            for (i, item) in enumerate(comp["cost"])
                comp["cost"][i] = item*(scale^(degree-i))
            end
        else
            warn(LOGGER, "Skipping cost model of type $(comp["model"]) in per unit transformation")
        end
    end
end


""
function check_conductors(data::Dict{String,Any})
    if ismultinetwork(data)
        for (i,nw_data) in data["nw"]
            _check_conductors(nw_data)
        end
    else
         _check_conductors(data)
    end
end


""
function _check_conductors(data::Dict{String,Any})
    if haskey(data, "conductors") && data["conductors"] < 1
        error(LOGGER, "conductor values must be positive integers, given $(data["conductors"])")
    end
end


"checks that voltage angle differences are within 90 deg., if not tightens"
function check_voltage_angle_differences(data::Dict{String,Any}, default_pad = 1.0472)
    if ismultinetwork(data)
        error(LOGGER, "check_voltage_angle_differences does not yet support multinetwork data")
    end

    @assert("per_unit" in keys(data) && data["per_unit"])
    default_pad_deg = round(rad2deg(default_pad), digits=2)

    modified = Set{Int}()

    for c in 1:get(data, "conductors", 1)
        cnd_str = haskey(data, "conductors") ? ", conductor $(c)" : ""
        for (i, branch) in data["branch"]
            angmin = branch["angmin"][c]
            angmax = branch["angmax"][c]

            if angmin <= -pi/2
                warn(LOGGER, "this code only supports angmin values in -90 deg. to 90 deg., tightening the value on branch $i$(cnd_str) from $(rad2deg(angmin)) to -$(default_pad_deg) deg.")
                if haskey(data, "conductors")
                    branch["angmin"][c] = -default_pad
                else
                    branch["angmin"] = -default_pad
                end
                push!(modified, branch["index"])
            end

            if angmax >= pi/2
                warn(LOGGER, "this code only supports angmax values in -90 deg. to 90 deg., tightening the value on branch $i$(cnd_str) from $(rad2deg(angmax)) to $(default_pad_deg) deg.")
                if haskey(data, "conductors")
                    branch["angmax"][c] = default_pad
                else
                    branch["angmax"] = default_pad
                end
                push!(modified, branch["index"])
            end

            if angmin == 0.0 && angmax == 0.0
                warn(LOGGER, "angmin and angmax values are 0, widening these values on branch $i$(cnd_str) to +/- $(default_pad_deg) deg.")
                if haskey(data, "conductors")
                    branch["angmin"][c] = -default_pad
                    branch["angmax"][c] =  default_pad
                else
                    branch["angmin"] = -default_pad
                    branch["angmax"] =  default_pad
                end
                push!(modified, branch["index"])
            end
        end
    end

    return modified
end


"checks that each branch has a reasonable thermal rating-a, if not computes one"
function check_thermal_limits(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_thermal_limits does not yet support multinetwork data")
    end

    @assert("per_unit" in keys(data) && data["per_unit"])
    mva_base = data["baseMVA"]

    modified = Set{Int}()

    branches = [branch for branch in values(data["branch"])]
    if haskey(data, "ne_branch")
        append!(branches, values(data["ne_branch"]))
    end

    for branch in branches
        if !haskey(branch, "rate_a")
            branch["rate_a"] = 0.0
        end

        for c in 1:get(data, "conductors", 1)
            cnd_str = haskey(data, "conductors") ? ", conductor $(c)" : ""
            if branch["rate_a"][c] <= 0.0
                theta_max = max(abs(branch["angmin"][c]), abs(branch["angmax"][c]))

                r = branch["br_r"]
                x = branch["br_x"]
                z = r + im * x
                y = pinv(z)
                y_mag = abs.(y[c,c])

                fr_vmax = data["bus"][string(branch["f_bus"])]["vmax"][c]
                to_vmax = data["bus"][string(branch["t_bus"])]["vmax"][c]
                m_vmax = max(fr_vmax, to_vmax)

                c_max = sqrt(fr_vmax^2 + to_vmax^2 - 2*fr_vmax*to_vmax*cos(theta_max))

                new_rate = y_mag*m_vmax*c_max

                if haskey(branch, "c_rating_a") && branch["c_rating_a"][c] > 0.0
                    new_rate = min(new_rate, branch["c_rating_a"][c]*m_vmax)
                end

                warn(LOGGER, "this code only supports positive rate_a values, changing the value on branch $(branch["index"])$(cnd_str) to $(round(mva_base*new_rate, digits=4))")

                if haskey(data, "conductors")
                    branch["rate_a"][c] = new_rate
                else
                    branch["rate_a"] = new_rate
                end

                push!(modified, branch["index"])
            end
        end
    end

    return modified
end


"checks that each branch has a reasonable current rating-a, if not computes one"
function check_current_limits(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_current_limits does not yet support multinetwork data")
    end

    @assert("per_unit" in keys(data) && data["per_unit"])
    mva_base = data["baseMVA"]

    modified = Set{Int}()

    branches = [branch for branch in values(data["branch"])]
    if haskey(data, "ne_branch")
        append!(branches, values(data["ne_branch"]))
    end

    for branch in branches

        if !haskey(branch, "c_rating_a")
            if haskey(data, "conductors")
                branch["c_rating_a"] = MultiConductorVector(0.0, data["conductors"])
            else
                branch["c_rating_a"] = 0.0
            end
        end

        for c in 1:get(data, "conductors", 1)
            cnd_str = haskey(data, "conductors") ? ", conductor $(c)" : ""
            if branch["c_rating_a"][c] <= 0.0
                theta_max = max(abs(branch["angmin"][c]), abs(branch["angmax"][c]))

                r = branch["br_r"]
                x = branch["br_x"]
                z = r + im * x
                y = pinv(z)
                y_mag = abs.(y[c,c])

                fr_vmax = data["bus"][string(branch["f_bus"])]["vmax"][c]
                to_vmax = data["bus"][string(branch["t_bus"])]["vmax"][c]
                m_vmax = max(fr_vmax, to_vmax)

                new_c_rating = y_mag*sqrt(fr_vmax^2 + to_vmax^2 - 2*fr_vmax*to_vmax*cos(theta_max))

                if haskey(branch, "rate_a") && branch["rate_a"][c] > 0.0
                    fr_vmin = data["bus"][string(branch["f_bus"])]["vmin"][c]
                    to_vmin = data["bus"][string(branch["t_bus"])]["vmin"][c]
                    vm_min = min(fr_vmin, to_vmin)

                    new_c_rating = min(new_c_rating, branch["rate_a"]/vm_min)
                end

                warn(LOGGER, "this code only supports positive c_rating_a values, changing the value on branch $(branch["index"])$(cnd_str) to $(mva_base*new_c_rating)")
                if haskey(data, "conductors")
                    branch["c_rating_a"][c] = new_c_rating
                else
                    branch["c_rating_a"] = new_c_rating
                end

                push!(modified, branch["index"])
            end
        end
    end

    return modified
end


"checks that all parallel branches have the same orientation"
function check_branch_directions(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_branch_directions does not yet support multinetwork data")
    end

    modified = Set{Int}()

    orientations = Set()
    for (i, branch) in data["branch"]
        orientation = (branch["f_bus"], branch["t_bus"])
        orientation_rev = (branch["t_bus"], branch["f_bus"])

        if in(orientation_rev, orientations)
            warn(LOGGER, "reversing the orientation of branch $(i) $(orientation) to be consistent with other parallel branches")
            branch_orginal = copy(branch)
            branch["f_bus"] = branch_orginal["t_bus"]
            branch["t_bus"] = branch_orginal["f_bus"]
            branch["g_to"] = branch_orginal["g_fr"] .* branch_orginal["tap"]'.^2
            branch["b_to"] = branch_orginal["b_fr"] .* branch_orginal["tap"]'.^2
            branch["g_fr"] = branch_orginal["g_to"] ./ branch_orginal["tap"]'.^2
            branch["b_fr"] = branch_orginal["b_to"] ./ branch_orginal["tap"]'.^2
            branch["tap"] = 1 ./ branch_orginal["tap"]
            branch["br_r"] = branch_orginal["br_r"] .* branch_orginal["tap"]'.^2
            branch["br_x"] = branch_orginal["br_x"] .* branch_orginal["tap"]'.^2
            branch["shift"] = -branch_orginal["shift"]
            branch["angmin"] = -branch_orginal["angmax"]
            branch["angmax"] = -branch_orginal["angmin"]

            push!(modified, branch["index"])
        else
            push!(orientations, orientation)
        end

    end

    return modified
end


"checks that all branches connect two distinct buses"
function check_branch_loops(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_branch_loops does not yet support multinetwork data")
    end

    for (i, branch) in data["branch"]
        if branch["f_bus"] == branch["t_bus"]
            error(LOGGER, "both sides of branch $(i) connect to bus $(branch["f_bus"])")
        end
    end
end


"checks that all buses are unique and other components link to valid buses"
function check_connectivity(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_connectivity does not yet support multinetwork data")
    end

    bus_ids = Set([bus["index"] for (i,bus) in data["bus"]])
    @assert(length(bus_ids) == length(data["bus"])) # if this is not true something very bad is going on

    for (i, load) in data["load"]
        if !(load["load_bus"] in bus_ids)
            error(LOGGER, "bus $(load["load_bus"]) in load $(i) is not defined")
        end
    end

    for (i, shunt) in data["shunt"]
        if !(shunt["shunt_bus"] in bus_ids)
            error(LOGGER, "bus $(shunt["shunt_bus"]) in shunt $(i) is not defined")
        end
    end

    for (i, gen) in data["gen"]
        if !(gen["gen_bus"] in bus_ids)
            error(LOGGER, "bus $(gen["gen_bus"]) in generator $(i) is not defined")
        end
    end

    for (i, strg) in data["storage"]
        if !(strg["storage_bus"] in bus_ids)
            error(LOGGER, "bus $(strg["storage_bus"]) in storage unit $(i) is not defined")
        end
    end

    for (i, branch) in data["branch"]
        if !(branch["f_bus"] in bus_ids)
            error(LOGGER, "from bus $(branch["f_bus"]) in branch $(i) is not defined")
        end

        if !(branch["t_bus"] in bus_ids)
            error(LOGGER, "to bus $(branch["t_bus"]) in branch $(i) is not defined")
        end
    end

    for (i, dcline) in data["dcline"]
        if !(dcline["f_bus"] in bus_ids)
            error(LOGGER, "from bus $(dcline["f_bus"]) in dcline $(i) is not defined")
        end

        if !(dcline["t_bus"] in bus_ids)
            error(LOGGER, "to bus $(dcline["t_bus"]) in dcline $(i) is not defined")
        end
    end
end


"""
checks that each branch has a reasonable transformer parameters
this is important because setting tap == 0.0 leads to NaN computations, which are hard to debug
"""
function check_transformer_parameters(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_transformer_parameters does not yet support multinetwork data")
    end

    @assert("per_unit" in keys(data) && data["per_unit"])

    modified = Set{Int}()

    for (i, branch) in data["branch"]
        if !haskey(branch, "tap")
            warn(LOGGER, "branch found without tap value, setting a tap to 1.0")
            branch["tap"] = 1.0
            push!(modified, branch["index"])
        else
            for c in 1:get(data, "conductors", 1)
                cnd_str = haskey(data, "conductors") ? " on conductor $(c)" : ""
                if branch["tap"][c] <= 0.0
                    warn(LOGGER, "branch found with non-positive tap value of $(branch["tap"][c]), setting a tap to 1.0$(cnd_str)")
                    if haskey(data, "conductors")
                        branch["tap"][c] = 1.0
                    else
                        branch["tap"] = 1.0
                    end
                    push!(modified, branch["index"])
                end
            end
        end
        if !haskey(branch, "shift")
            warn(LOGGER, "branch found without shift value, setting a shift to 0.0")
            branch["shift"] = 0.0
            push!(modified, branch["index"])
        end
    end

    return modified
end


"""
checks that each storage unit has a reasonable parameters
"""
function check_storage_parameters(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_storage_parameters does not yet support multinetwork data")
    end

    for (i, strg) in data["storage"]
        if strg["energy"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive energy level $(strg["energy"])")
        end
        if strg["energy_rating"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive energy rating $(strg["energy_rating"])")
        end
        if strg["charge_rating"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive charge rating $(strg["energy_rating"])")
        end
        if strg["discharge_rating"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive discharge rating $(strg["energy_rating"])")
        end
        if strg["r"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive resistance $(strg["r"])")
        end
        if strg["x"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive reactance $(strg["x"])")
        end
        if strg["standby_loss"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive standby losses $(strg["standby_loss"])")
        end

        if haskey(strg, "thermal_rating") && strg["thermal_rating"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive thermal rating $(strg["thermal_rating"])")
        end
        if haskey(strg, "current_rating") && strg["current_rating"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive current rating $(strg["thermal_rating"])")
        end


        if strg["charge_efficiency"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive charge efficiency of $(strg["charge_efficiency"])")
        end
        if strg["charge_efficiency"] <= 0.0 || strg["charge_efficiency"] > 1.0
            warn(LOGGER, "storage unit $(strg["index"]) charge efficiency of $(strg["charge_efficiency"]) is out of the valid range (0.0. 1.0]")
        end

        if strg["discharge_efficiency"] < 0.0
            error(LOGGER, "storage unit $(strg["index"]) has a non-positive discharge efficiency of $(strg["discharge_efficiency"])")
        end
        if strg["discharge_efficiency"] <= 0.0 || strg["discharge_efficiency"] > 1.0
            warn(LOGGER, "storage unit $(strg["index"]) discharge efficiency of $(strg["discharge_efficiency"]) is out of the valid range (0.0. 1.0]")
        end

        if !isapprox(strg["x"], 0.0, atol=1e-6, rtol=1e-6)
            warn(LOGGER, "storage unit $(strg["index"]) has a non-zero reactance $(strg["x"]), which is currently ignored")
        end


        if strg["standby_loss"] > 0.0 && strg["energy"] <= 0.0
            warn(LOGGER, "storage unit $(strg["index"]) has standby losses but zero initial energy.  This can lead to model infeasiblity.")
        end
    end

end


"checks bus types are consistent with generator connections, if not, fixes them"
function check_bus_types(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_bus_types does not yet support multinetwork data")
    end

    modified = Set{Int}()

    bus_gens = Dict((i, []) for (i,bus) in data["bus"])

    for (i,gen) in data["gen"]
        #println(gen)
        if gen["gen_status"] == 1
            push!(bus_gens[string(gen["gen_bus"])], i)
        end
    end

    for (i, bus) in data["bus"]
        if bus["bus_type"] != 4 && bus["bus_type"] != 3
            bus_gens_count = length(bus_gens[i])

            if bus_gens_count == 0 && bus["bus_type"] != 1
                warn(LOGGER, "no active generators found at bus $(bus["bus_i"]), updating to bus type from $(bus["bus_type"]) to 1")
                bus["bus_type"] = 1
                push!(modified, bus["index"])
            end

            if bus_gens_count != 0 && bus["bus_type"] != 2
                warn(LOGGER, "active generators found at bus $(bus["bus_i"]), updating to bus type from $(bus["bus_type"]) to 2")
                bus["bus_type"] = 2
                push!(modified, bus["index"])
            end

        end
    end

    return modified
end


"checks that parameters for dc lines are reasonable"
function check_dcline_limits(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_dcline_limits does not yet support multinetwork data")
    end

    @assert("per_unit" in keys(data) && data["per_unit"])
    mva_base = data["baseMVA"]

    modified = Set{Int}()

    for c in 1:get(data, "conductors", 1)
        cnd_str = haskey(data, "conductors") ? ", conductor $(c)" : ""
        for (i, dcline) in data["dcline"]
            if dcline["loss0"][c] < 0.0
                new_rate = 0.0
                warn(LOGGER, "this code only supports positive loss0 values, changing the value on dcline $(dcline["index"])$(cnd_str) from $(mva_base*dcline["loss0"][c]) to $(mva_base*new_rate)")
                if haskey(data, "conductors")
                    dcline["loss0"][c] = new_rate
                else
                    dcline["loss0"] = new_rate
                end
                push!(modified, dcline["index"])
            end

            if dcline["loss0"][c] >= dcline["pmaxf"][c]*(1-dcline["loss1"][c] )+ dcline["pmaxt"][c]
                new_rate = 0.0
                warn(LOGGER, "this code only supports loss0 values which are consistent with the line flow bounds, changing the value on dcline $(dcline["index"])$(cnd_str) from $(mva_base*dcline["loss0"][c]) to $(mva_base*new_rate)")
                if haskey(data, "conductors")
                    dcline["loss0"][c] = new_rate
                else
                    dcline["loss0"] = new_rate
                end
                push!(modified, dcline["index"])
            end

            if dcline["loss1"][c] < 0.0
                new_rate = 0.0
                warn(LOGGER, "this code only supports positive loss1 values, changing the value on dcline $(dcline["index"])$(cnd_str) from $(dcline["loss1"][c]) to $(new_rate)")
                if haskey(data, "conductors")
                    dcline["loss1"][c] = new_rate
                else
                    dcline["loss1"] = new_rate
                end
                push!(modified, dcline["index"])
            end

            if dcline["loss1"][c] >= 1.0
                new_rate = 0.0
                warn(LOGGER, "this code only supports loss1 values < 1, changing the value on dcline $(dcline["index"])$(cnd_str) from $(dcline["loss1"][c]) to $(new_rate)")
                if haskey(data, "conductors")
                    dcline["loss1"][c] = new_rate
                else
                    dcline["loss1"] = new_rate
                end
                push!(modified, dcline["index"])
            end

            if dcline["pmint"][c] <0.0 && dcline["loss1"][c] > 0.0
                #new_rate = 0.0
                warn(LOGGER, "the dc line model is not meant to be used bi-directionally when loss1 > 0, be careful interpreting the results as the dc line losses can now be negative. change loss1 to 0 to avoid this warning")
                #dcline["loss0"] = new_rate
            end
        end
    end

    return modified
end


"throws warnings if generator and dc line voltage setpoints are not consistent with the bus voltage setpoint"
function check_voltage_setpoints(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_voltage_setpoints does not yet support multinetwork data")
    end

    for c in 1:get(data, "conductors", 1)
        cnd_str = haskey(data, "conductors") ? "conductor $(c) " : ""
        for (i,gen) in data["gen"]
            bus_id = gen["gen_bus"]
            bus = data["bus"]["$(bus_id)"]
            if gen["vg"][c] != bus["vm"][c]
                warn(LOGGER, "the $(cnd_str)voltage setpoint on generator $(i) does not match the value at bus $(bus_id)")
            end
        end

        for (i, dcline) in data["dcline"]
            bus_fr_id = dcline["f_bus"]
            bus_to_id = dcline["t_bus"]

            bus_fr = data["bus"]["$(bus_fr_id)"]
            bus_to = data["bus"]["$(bus_to_id)"]

            if dcline["vf"][c] != bus_fr["vm"][c]
                warn(LOGGER, "the $(cnd_str)from bus voltage setpoint on dc line $(i) does not match the value at bus $(bus_fr_id)")
            end

            if dcline["vt"][c] != bus_to["vm"][c]
                warn(LOGGER, "the $(cnd_str)to bus voltage setpoint on dc line $(i) does not match the value at bus $(bus_to_id)")
            end
        end
    end
end



"throws warnings if cost functions are malformed"
function check_cost_functions(data::Dict{String,Any})
    if ismultinetwork(data)
        error(LOGGER, "check_cost_functions does not yet support multinetwork data")
    end

    modified_gen = Set{Int}()
    for (i,gen) in data["gen"]
        if _check_cost_function(i, gen, "generator")
            push!(modified_gen, gen["index"])
        end
    end

    modified_dcline = Set{Int}()
    for (i, dcline) in data["dcline"]
        if _check_cost_function(i, dcline, "dcline")
            push!(modified_dcline, dcline["index"])
        end
    end

    return (modified_gen, modified_dcline)
end


""
function _check_cost_function(id, comp, type_name)
    #println(comp)
    modified = false

    if "model" in keys(comp) && "cost" in keys(comp)
        if comp["model"] == 1
            if length(comp["cost"]) != 2*comp["ncost"]
                error(LOGGER, "ncost of $(comp["ncost"]) not consistent with $(length(comp["cost"])) cost values on $(type_name) $(id)")
            end
            if length(comp["cost"]) < 4
                error(LOGGER, "cost includes $(comp["ncost"]) points, but at least two points are required on $(type_name) $(id)")
            end
            for i in 3:2:length(comp["cost"])
                if comp["cost"][i-2] >= comp["cost"][i]
                    error(LOGGER, "non-increasing x values in pwl cost model on $(type_name) $(id)")
                end
            end
            if "pmin" in keys(comp) && "pmax" in keys(comp)
                pmin = sum(comp["pmin"]) # sum supports multi-conductor case
                pmax = sum(comp["pmax"])
                for i in 3:2:length(comp["cost"])
                    if comp["cost"][i] < pmin || comp["cost"][i] > pmax
                        warn(LOGGER, "pwl x value $(comp["cost"][i]) is outside the bounds $(pmin)-$(pmax) on $(type_name) $(id)")
                    end
                end
            end
            modified = _simplify_pwl_cost(id, comp, type_name)
        elseif comp["model"] == 2
            if length(comp["cost"]) != comp["ncost"]
                error(LOGGER, "ncost of $(comp["ncost"]) not consistent with $(length(comp["cost"])) cost values on $(type_name) $(id)")
            end
        else
            warn(LOGGER, "Unknown cost model of type $(comp["model"]) on $(type_name) $(id)")
        end
    end

    return modified
end


"checks the slope of each segment in a pwl function, simplifies the function if the slope changes is below a tolerance"
function _simplify_pwl_cost(id, comp, type_name, tolerance = 1e-2)
    @assert comp["model"] == 1

    slopes = Float64[]
    smpl_cost = Float64[]
    prev_slope = nothing

    x2, y2 = 0.0, 0.0

    for i in 3:2:length(comp["cost"])
        x1 = comp["cost"][i-2]
        y1 = comp["cost"][i-1]
        x2 = comp["cost"][i-0]
        y2 = comp["cost"][i+1]

        m = (y2 - y1)/(x2 - x1)

        if prev_slope == nothing || (abs(prev_slope - m) > tolerance)
            push!(smpl_cost, x1)
            push!(smpl_cost, y1)
            prev_slope = m
        end

        push!(slopes, m)
    end

    push!(smpl_cost, x2)
    push!(smpl_cost, y2)

    if length(smpl_cost) < length(comp["cost"])
        warn(LOGGER, "simplifying pwl cost on $(type_name) $(id), $(comp["cost"]) -> $(smpl_cost)")
        comp["cost"] = smpl_cost
        comp["ncost"] = length(smpl_cost)/2
        return true
    end
    return false
end


"trims zeros from higher order cost terms"
function simplify_cost_terms(data::Dict{String,Any})
    if ismultinetwork(data)
        networks = data["nw"]
    else
        networks = [("0", data)]
    end

    modified_gen = Set{Int}()
    modified_dcline = Set{Int}()

    for (i, network) in networks
        if haskey(network, "gen")
            for (i, gen) in network["gen"]
                if haskey(gen, "model") && gen["model"] == 2
                    ncost = length(gen["cost"])
                    for j in 1:ncost
                        if gen["cost"][1] == 0.0
                            gen["cost"] = gen["cost"][2:end]
                        else
                            break
                        end
                    end
                    if length(gen["cost"]) != ncost
                        gen["ncost"] = length(gen["cost"])
                        @info(LOGGER, "removing $(ncost - gen["ncost"]) cost terms from generator $(i): $(gen["cost"])")
                        push!(modified_gen, gen["index"])
                    end
                end
            end
        end

        if haskey(network, "dcline")
            for (i, dcline) in network["dcline"]
                if haskey(dcline, "model") && dcline["model"] == 2
                    ncost = length(dcline["cost"])
                    for j in 1:ncost
                        if dcline["cost"][1] == 0.0
                            dcline["cost"] = dcline["cost"][2:end]
                        else
                            break
                        end
                    end
                    if length(dcline["cost"]) != ncost
                        dcline["ncost"] = length(dcline["cost"])
                        @info(LOGGER, "removing $(ncost - dcline["ncost"]) cost terms from dcline $(i): $(dcline["cost"])")
                        push!(modified_dcline, dcline["index"])
                    end
                end
            end
        end
    end

    return (modified_gen, modified_dcline)
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

# end
