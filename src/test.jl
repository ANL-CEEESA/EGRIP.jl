# This function is to test "parse" and "ARGS"

function print_sum(a,b)
    c = a+b
    println()
    println("The first argument is $a")
    println("The second argument is $b")
    println("The summation is $c")
    return a+c,b+c
end

a = parse(Int64, ARGS[1])
b = parse(Int64, ARGS[2])
a_new, b_new = print_sum(a,b)
println("The new a is $a_new")
println("The new b is $b_new")
