using JSON
using DataStructures

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