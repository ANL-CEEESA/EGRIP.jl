# Code Loading
* The current confusion is on how Julia load packages and modules that are not registered through `Pkg`.


## Working Directory
* The working directory, which can be obtained by `pwd()`, has to be the one containing our packages for things to be loaded correctly.
* We can add the command `cd(@__DIR__)` at the beginning of our code to navigate the directory to where our code is running.

## Package Loading
Assmue we would like to use our developed but unregistered package `EGRIP.jl` at a Julia file named `testrun.jl`.
There are two ways to load `EGRIP.jl`.

### Include the package and corresponding modules
We can include the main jl file of the package at the top of `testrun.jl`:
```Julia
cd(@__DIR__) # navigate to correct working directory containing `testrun.jl`
include("path to the source code from current working directory/src/EGRIP.jl")
```
Then, we can use the package through relative path import of the main module since it cannot be identified by Julia Environment:
```Julia
using .EGRIP # It tells Julia to find the module around the current working directory instead of Julia Environment
```

Due to the similar reason, other modules in the package cannot be identified by Julia Environment.
When `module_a` in `file_module_a.jl` needs to use a function `fun_b` from `module_b` in `file_module_b.jl`, we need to do the following
at the beginning of `file_module_a.jl` (assmue `file_module_a.jl` and `file_module_b.jl` are in the same directory):
```Julia
include("file_module_b.jl")
using .module_b
```
Then, if `fun_b` has been exported, we can directly access it.
Otherwise. we need to use `module_b.fun_b`.
This is not very convenient.


### Add source code directory into Julia Environment
We can make source directory accessible through Julia's LOAD_PATH.
We can add the following line at the top of `testrun.jl`:
```Julia
cd(@__DIR__) # navigate to correct working directory `testrun.jl`
push!(LOAD_PATH,"path to the source code from current working directory/src/")
```
Then, we can use the package through absolute path import of the main module since it can be identified by Julia Environment:
```Julia
using EGRIP # It tells Julia to find the module in Julia Environment LOAD_PATH
```

In addition, all other modules can be used in the same way.


## Discussion on `include`
* Julia’s include is a function, not a simple input redirector (as in C, Fortran, or Matlab).
* Evaluate the contents of a source file in the current context. “The current context” means the global scope of the current module when the evaluation takes place.
* This function is typically used to load source interactively, or to combine files in packages that are broken into multiple source files.
* Include works in the dynamically-current module, not the lexically-current one.
* It is really a load-time function, not a run-time one.





# Package Organization
## Option 1
We could build one main module called EGRIP and several submodules.
*In this way, we will declare certain submodule to access its function in another module once the source code is loaded into `LOAD_PATH`.*
For example:
`EGRIP/src/`
---------`EGRIP.jl`
              ```Julia
              module EGRIP
                include("power_flow.jl")
                include("load_restoration.jl")
                using PowerFlow
                using LoadRestoration
                function fun_bs()
                  fun_pf()
                  fun_lr()
                end
                export fun_bs
              end
              ```
---------`power_flow.jl`
              ```Julia
              module PowerFlow
              export func_pf
                function func_pf()
                end
              end
                ```
---------`load_restoration.jl`
            ```Julia
            module LoadRestoration
            using PowerFlow
            export func_lr
              function func_lr()
                func_pf()
              end
            end
              ```

Then, in a testing script, we can use the package by
```Julia
using EGRIP
fun_bs()
```
In addition, we can use the module independently from `EGRIP`
```Julia
using PowerFlow
fun_pf()
```

A different but not good way to do `include` file.
*This is suggested to do the `include` in the main module. And once it is loaded to `LOAD_PATH`, every included script is accessible.*
`EGRIP/src/`
---------`EGRIP.jl`
              ```Julia
              module EGRIP
                include("load_restoration.jl")
                using PowerFlow
                using LoadRestoration
                function fun_bs()
                  fun_pf()
                  fun_lr()
                end
                export fun_bs
              end
              ```
---------`power_flow.jl`
              ```Julia
              module PowerFlow
              export func_pf
                function func_pf()
                end
              end
                ```
---------`load_restoration.jl`
            ```Julia
            module LoadRestoration
            include("power_flow.jl")
            using PowerFlow
            export func_lr
              function func_lr()
                func_pf()
              end
            end
              ```




## Option 2
We just build one main module `EGRIP`. The rest functionalities are implemented by functions in different scripts.
Then, we just need to include the scripts in the main module.
*Once the main module is loaded into `LOAD_PATH`, we can these functions freely between different scripts without further declaration.*
Some Julia packages like `PowerModels.jl` are organized in this way.
Take an example:
`EGRIP/src/`
---------`EGRIP.jl`
              ```Julia
              module EGRIP
                include("power_flow.jl")
                include("load_restoration.jl")
                function fun_bs()
                  fun_pf()
                  fun_lr()
                end
                export fun_bs
              end
              ```
---------`power_flow.jl`
              ```Julia
              function func_pf()
              end
                ```
---------`load_restoration.jl`
            ```Julia
            function func_lr()
                func_pf()
            end
              ```



# Documentation
We use `Documenter.jl`.
