
# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../../src/")

# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP


using EGRIP
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
using Interpolations
using Distributions
using StatsBase

# include project utility functions
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup/"
t_final = 300
t_step = 10
gap = 0.0
nstage = Int64(t_final/t_step)
stages = 1:nstage

# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Renewable", "W Renewable: Prob 0.05",
                            "W Renewable: Prob 0.10",
                            "W Renewable: Prob 0.15",
                            "W Renewable: Prob 0.20"]

# ------------------- obtain approximated density function (histogram) from historical data-------------
# load real wind power data
# note that we ignore the ERCOT wind data in the version control for security
# Each time we may need to add the data folder manually
wind_data = CSV.read("../../ERCOT_wind/wind_farm3_POE.csv", DataFrame)
wind_data = convert(Matrix, wind_data)

# --demo--
demo_number = 1

# ---------------- method 1: resample based on constructed histogram ---------
# (1) obtain the risk interpolation
prob = 1.0:-0.1:0.1
itp = interpolate((wind_data[demo_number, :],), prob, Gridded(Linear()))
# plot
using PyPlot
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(9, 6))
ax.plot(wind_data[demo_number, :], prob, color="b", linewidth=2)
# ax.scatter(wind_data[1, :], prob, color="b", linewidth=2)
ax.set_title("Wind Power POE (Delivering Risk)", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Wind Power (MW)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Probability", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()

# (2) discretize the risk level
histogram_approximation_number = 100
wind_power_sample = range(minimum(wind_data[demo_number, :]), maximum(wind_data[demo_number, :]), length=histogram_approximation_number)
wind_hist = Dict()
wind_hist["a"] = Float64[]
wind_hist["b"] = Float64[]
wind_hist["ab"] = Float64[]
wind_hist["p"] = Float64[]
for i in range(1, stop=histogram_approximation_number-1, length=histogram_approximation_number-1)
    i = Int(i)
    a = wind_power_sample[i]
    b = wind_power_sample[i + 1]
    push!(wind_hist["a"], a)
    push!(wind_hist["b"], b)
    push!(wind_hist["ab"], (a + b)/2)
    itp_a = itp(a)
    itp_b = itp(b)
    itp_avg = (itp_a + itp_b)/2
    push!(wind_hist["p"], itp_avg)
end
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(9, 6))
ax.plot(wind_data[demo_number, :], prob, color="b", linewidth=4)
ax.bar(wind_hist["ab"], wind_hist["p"], width=wind_hist["b"]-wind_hist["a"], color=(0.1, 0.1, 0.1, 0.1), edgecolor="b")
ax.set_title("Wind Power POE (Delivering Risk)", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Wind Power (MW)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Probability", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()

# (3) estimate the histogram
wind_hist["d"] = Float64[]
for i in range(1, stop=histogram_approximation_number-2, length=histogram_approximation_number-2)
    i = Int(i)
    height = (wind_hist["p"][i] - wind_hist["p"][i + 1])/(wind_hist["b"][i]-wind_hist["a"][i])
    push!(wind_hist["d"], height)
end
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(9, 6))
ax.bar(wind_hist["ab"][1:end-1], wind_hist["d"], width=wind_hist["b"][1]-wind_hist["a"][1], color=(0.1, 0.1, 0.1, 0.1), edgecolor="b")
ax.set_title("Wind Power Approximated Density (Histogram)", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Wind Power (MW)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Probability", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()

# (4) finally we can use sampling function in StatsBase.jl that can sample from population with analytical weight
# our analytical weight will be equal to the density since the band length is the same
using Random
Random.seed!(1523) # Setting the seed
w = ProbabilityWeights(wind_hist["d"])
wind_resample = sample(wind_hist["ab"][1:end-1], w, 50000)
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(9, 6))
ax.hist(wind_resample, bins=500, color=(0.1, 0.1, 0.1, 0.1), edgecolor="r")
ax.set_title("Wind Power Resampling Histogram", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Wind Power (MW)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Frequency", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()



# ---------------- method 2: resample based on interpolation ---------
prob_ins = 0.1:0.1:1.0
itp_x_prob = interpolate((prob_ins,), reverse(wind_data[demo_number, :]), Gridded(Linear()))
wind_resample_1 = itp_x_prob(rand(Uniform(0.1, 1), 50000))
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(9, 6))
ax.hist(wind_resample, bins=500, color="b", edgecolor="b")
ax.hist(wind_resample_1, bins=500, color="r", edgecolor="r", alpha=0.5)
ax.set_title("Wind Power Resampling Histogram", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Wind Power (MW)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Frequency", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
