using JSON
using DataStructures

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

samples = OrderedDict()
samples = JSON.parsefile("samples.json")

for s in keys(samples)
    println("")
    println("sample ", s)
    ordered_sample = sort(samples[s]["node_energization_sequence"])
    for t in keys(ordered_sample)
        println("stage ", t, ": ", samples[s]["node_energization_sequence"][t])
    end
    println(samples[s]["restored_load"])
end
