using PyPlot
using CSV
cd(@__DIR__)
push!(LOAD_PATH,"../src/")
using EGRIP

ref = load_network("WECC_dataset/sec_N.json", "json")


res_path = "results_sec_N"
# res_path = "results_sec_2_gap100"
# res_path = "results"

u = CSV.read(string(res_path, "/", "res_u_30_300.csv"))
x = CSV.read(string(res_path, "/", "res_x_30_300.csv"))
y = CSV.read(string(res_path, "/", "res_y_30_300.csv"))

# # results in stages
println("")
adj_matrix = Dict()
for (i,j) in keys(ref[:buspairs])
    adj_matrix[(i,j)] = 0
end
println("Line energization: ")
for t in 1:10
    print("stage ", t, ": ")
    for (i,j) in keys(ref[:buspairs])
        if (abs(value(model[:x][(i,j),t]) - 1) < 1e-6) && (adj_matrix[(i,j)] == 0)
            print("(", i, ",", j, ") ")
            adj_matrix[(i,j)] = 1
        end
    end
    println("")
end

println("")
println("Generator energization: ")
for t in stages
    print("stage ", t, ": ")
    for g in keys(ref[:gen])
        if (abs(value(model[:y][g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:y][g,t-1]) + value(model[:y][g,t]) - 1) < 1e-6)
            print(ref[:gen][g]["gen_bus"], " ")
        end
    end
    println("")
end

println("")
println("Bus energization: ")
for t in stages
    print("stage ", t, ": ")
    for b in keys(ref[:bus])
        if (abs(value(model[:u][b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:u][b,t-1]) + value(model[:u][b,t]) - 1) < 1e-6)
            print(b, " ")
        end
    end
    println("")
end