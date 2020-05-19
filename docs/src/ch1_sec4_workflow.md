# Restoration Planning and Verification Workflow

- Integrated restoration optimization model produces an initial parallel recovery plan
- Cranking path module finds transmission path to energize to crank a generator
- Transient stability and static security constraints are validated by simulation
- Three options to fix a restoration plan
  - Add compensation devices
  - Switch to another cranking path
  - Re-optimize startup sequences
- If a restoration plan cannot be repaired (or sacrifice too much solution quality), remove current plan from solution space and resolve the integrated restoration optimization model

![Restoration workflow](fig_workflow.png)


## Restoration Planning
We can use the package by declaring it:
```julia
using EGRIP
```
First, we need to tell the package where our problem data is:
```julia
dir_case_network = "./case39.m"
dir_case_blackstart = "./BS_generator.csv"
```
Second, we need to tell the package where our results are going to be stored:
```julia
dir_case_result = "./results/"
```
Then, we define the restoration duration and time steps:
```julia
t_final = 500
t_step = 250
```
Once everything is ready, we can call `solve_restoration` function to solve the problem:
```julia
solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step)
```

Part of the results will be printed once the algorithm terminates.
```julia
Line energization:
stage 1.0:
stage 2.0:

Generator energization:
stage 1.0: 39
stage 2.0:

Bus energization:
stage 1.0: 39
stage 2.0:
```
Detailed results will be stored in `results` folder under the directory containing the case file.



## Restoration Plan Verification
