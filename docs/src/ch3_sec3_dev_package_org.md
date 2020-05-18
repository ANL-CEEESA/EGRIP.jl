# Package Organization

## Option 1
We could build one main module called EGRIP and several submodules.

*In this way, we will declare certain submodule to access its function in another module once the source code is loaded into `LOAD_PATH`.*

For example:

`EGRIP/src/`

-`EGRIP.jl`
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

-`power_flow.jl`
```Julia
module PowerFlow
export func_pf
function func_pf()
end
end
```

-`load_restoration.jl`
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

-`EGRIP.jl`
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

-`power_flow.jl`
```Julia
module PowerFlow
export func_pf
function func_pf()
end
end
```

-`load_restoration.jl`
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

-`EGRIP.jl`
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

-`power_flow.jl`
```Julia
function func_pf()
end
```

-`load_restoration.jl`
```Julia
function func_lr()
  func_pf()
end
```
