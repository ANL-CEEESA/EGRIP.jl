# a = 0
a = []
for i in 1:10
    # a = a + 1
    println("Value: ", a, ", Type: ", typeof(a))
    push!(a, 1)
end
