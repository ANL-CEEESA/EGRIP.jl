cd(@__DIR__)

using JSON
using CSV
using DataFrames

gen_seq = CSV.read("results_startup_density/res_ys.csv", DataFrame)

Seq = Dict()

for t=1:30
    start_index = findall(x->x==1, gen_seq[!,t+2])
    if size(start_index)[1] != 0
        Seq[t] = gen_seq[start_index, 2]
        println("Stage ", t, ": ", Seq[t])
    else
        println("Stage ", t, ": No Started Generators")
    end
end
