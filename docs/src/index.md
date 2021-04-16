# Pipelines.jl

```@meta
CurrentModule = Pipelines
```

*A lightweight Julia package for computational pipelines.*

Building reusable pipelines and workflows is easier than you have ever thought.

## Package Features

- Easy to build both simple and complex tasks.

- Supports external command lines and pure Julia functions.

- Supports **resuming** interrupted tasks, **skipping** finished tasks.

- Supports dependency check.

- Supports inputs, outputs validation, and so on.

## Installation

Pipelines.jl can be installed using the Julia package manager. From the Julia REPL, type ] to enter the Pkg REPL mode and run

```julia
pkg> add Pipelines
# If it fails, use
pkg> add https://github.com/cihga39871/Pipelines.jl.git
```

To use the package, type

```julia
using Pipelines
```

## Quick Start

Pipelines are built with multiple `CmdProgram`s. A `CmdProgram` contains a command template and name lists of inputs/outputs. The names of inputs/outputs will be replaced by real values when executing the program.

Let's set up a simple program to print values using `echo`:

```julia
using Pipelines

echo = CmdProgram(
    inputs = ["INPUT1", "INPUT2"],
    cmd = `echo INPUT1 INPUT2`   
)
```

Running the program is just like running other `Cmd`,  but here we need to specify inputs by using `Dict{String}`.

```julia
inputs = Dict(
    "INPUT1" => "Hello,",
    "INPUT2" => `Pipeline.jl`
)
run(echo, inputs)
```

!!! note "Program will not run twice by default!"
    If you run a program with the same inputs again, the program will just return the same result, display a warning message without running the command twice.
    ```julia
    run(echo, inputs)
    ```

    This is because the program will generate a file (run id file) in the current directory indicating the program has been run. Several methods can be used to re-run a program:
    
    ```julia
    # Method 1: stop checking finished program
    run(echo, inputs; skip_when_done = false)
    
    # Method 2: delete the run_id_file before running again:
    cmd, run_id_file = run(echo, inputs; dry_run = true) # Dry-run returns the command and run id file without running it.
    rm(run_id_file)  # remove the run_id_file
    
    # Method 3: Do not generate run_id_file when first running.
    run(echo, inputs; touch_run_id_file=false)
    ```

### Program with Outputs

Unlike the first example, many programs write files as outputs. Pipelines.jl has an elegant way to handle it.

The following program prints values simultaneously, sort them, and save to a file.

```julia
prog = CmdProgram(
    inputs = ["INPUT1", "INPUT2", "INPUT3"],
    outputs = ["OUTPUT_FILE"],
    cmd = pipeline(`echo INPUT1 INPUT2` & `echo INPUT3`, `sort`, "OUTPUT_FILE")
)

inputs = Dict(
    "INPUT1" => "Hello,",
    "INPUT2" => `Pipeline.jl`,
    "INPUT3" => 39871
)
outputs = Dict("OUTPUT_FILE" => "out.txt")

run(prog, inputs, outputs) # will return (success::Bool, outputs)
```

It is inconvenient to specify outputs every time, so we provide an argument (`infer_outputs::Function`) in `CmdProgram` to generate default outputs from inputs.

```julia
prog = CmdProgram(
    inputs = ["INPUT1", "INPUT2", "INPUT3"],
    outputs = ["OUTPUT_FILE"],
    cmd = pipeline(`echo INPUT1 INPUT2` & `echo INPUT3`, `sort`, "OUTPUT_FILE"),
    infer_outputs = inputs -> Dict(
    	"OUTPUT_FILE" => inputs["INPUT1"] * ".txt"
    )
)
success, outputs = run(prog, inputs)
```

We can also generate default outputs without running the program:

```julia
outputs = infer_outputs(prog, inputs)
```

### Julia Program

Pipelines also defined `JuliaProgram` type for pure Julia functions. It is like `CmdProgram` and remain most compatibility. More details are in the Julia Program, Manual Page.

## Future Development

- Support running competitive tasks with **locks**.

## Change log

### v0.2.1

- Fix examples in docs.

### v0.2.0

#### CmdDependency

- Better interpolation in `Cmd`.

  ```julia
  dep::CmdDepencendy

  # old version
  `$(dep.exec) --args`
  # or
  `$(exec(dep)) --args`

  # now
  `$dep --args`
  ```

#### Program

- New `JuliaProgram` for pure Julia implementation.

- `Program` is the Abstract type containing `CmdProgram` and `JuliaProgram` substypes.
