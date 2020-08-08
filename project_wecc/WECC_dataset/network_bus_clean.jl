using CSV
using DataFrames

cd(@__DIR__)
data_bus = CSV.read("WECC_Bus_all.csv")

# clear unit name
num_bus = size(data_bus)[1]
for l in 1:num_bus
    name_str = split(data_bus[l, :BusName], "-")   # split bus name by - if exist
    if length(name_str) > 1
        data_bus["BusName"][l] = name_str[2]
    end
end

CSV.write("WECC_Bus_all_julia.csv", data_bus)
