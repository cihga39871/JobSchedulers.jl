# Command Program

Please read the Quick Start section in Home page first.

Pipelines are built with multiple `Program`s. `Program` is the abstract type contains `CmdProgram` and `JuliaProgram`.

A `CmdProgram` contains a command template, lists of dependencies/inputs/outputs, and predefined methods to prepare run-time environment, validate dependencies/inputs/outputs, and so on.


## An Example

We will go through an example to illustrate how to write a `CmdProgram`.

The example is a **robust** Bowtie2 mapping program. It shows every functionality of `CmdProgram`, but in reality, we do not need that much validation.

### Define the Name
```julia
program_bowtie2 = CmdProgram(
	name = "Bowtie2 Mapping",# The name of CmdProgram
	id_file = ".bowtie2"     # When job completed, a file ".bowtie2.xxxxxx" will
	                         # be created to indicate the job is finished to
							 # avoid re-run.
)
```

### Main Command (Required)

In Bash script, the main code is

```bash
REF=/path/to/reference_genome
FASTQ=/path/to/input_fastq_file
BAM=/path/to/output_bam_file

bowtie2 -x $REF -q $FASTQ | samtools sort -O bam -o $BAM
```

Code in CmdProgram:

```julia
program_bowtie2 = CmdProgram(
	...,
	inputs = ["FASTQ", "REF"],
	outputs = ["BAM"],
	cmd = pipeline(`bowtie2 -x REF -q FASTQ`, `samtools sort -O bam -o BAM`)
)
```

Now, the code can be run by invoking `run(program_bowtie2, inputs, outputs)`, but to illustrate the full functionality, we will add more things to make it robust and easy to use.

### Command Dependency (Robustness↑)

We use `samtools` and `bowtie2` as command dependencies. They can be wrapped in `CmdDependency`, which is illustrated in another page. Please allow me to skip it for now.

### Infer Outputs (Convenience↑)

We can set a default method to generate `outputs::Dict{String}` from inputs, which allows us run the program without specifying outputs (`run(program_bowtie2, inputs)`.)

```julia
program_bowtie2 = CmdProgram(
	...,
	outputs = ["BAM"],
	infer_outputs = inputs -> begin
		Dict("BAM" => to_str(inputs["FASTQ"]) * ".bam")
	end,
	...
)
```

!!! note "to_str(x) and to_cmd(x)"
    `to_str` converts most types to `String`, and `to_cmd` to `Cmd`. They are tailored for parsing `inputs["x"]` and `outputs["x"]`.

    User-defined `inputs, outputs::Dict{String}` only confine the key type (`String`), does not confine the value type because of flexibility. When writing functions using inputs/outputs, we should consider this. It can be a Number, a Cmd, a String, and even a Vector. Pipeline.jl provides `to_str` and `to_cmd` to elegantly convert those types to `String` or `Cmd` as you wish.

    Other conversions are also available, such as `replaceext` (replace extension) and `removeext` (remove extension). More details are in API/Utils page.


### Validate Inputs (Robustness↑)

To make the code robust, we can check whether the inputs exists by using `validate_inputs`. It is a function takes `inputs::Dict{String}` as the argument.

```julia
program_bowtie2 = CmdProgram(
	...,
	inputs = ["FASTQ", "REF"],
	validate_inputs = inputs -> begin
		check_dependency_file(inputs["FASTQ"]) &&
		check_dependency_file(inputs["REF"])
	end,
	...
)
```

### Prerequisites (Robustness↑)

We also need to prepare something (`prerequisites`) before running the main command. For example, create the output directory if not exist. (`prerequisites`) is a function takes `inputs::Dict{String}, outputs::Dict{String}` as the arguments.

```julia
program_bowtie2 = CmdProgram(
	...,
	prerequisites = (inputs, outputs) -> begin
		mkpath(dirname(to_str(outputs["BAM"])))
	end
)
```

### Validate Outputs (Robustness↑)

After running the main command, we can validate outputs by using `validate_outputs`. It is a function takes `outputs::Dict{String}` as the argument.

```julia
program_bowtie2 = CmdProgram(
	...,
	outputs = ["BAM"],
	validate_outputs = outputs -> begin
		check_dependency_file(outputs["BAM"])
	end,
	...
)
```

### Wrap Up (Convenience↑)

After validating outputs, we may also do something to wrap up, such as removing temporary files. Here, we build an index for output BAM file. wrap_up function takes `inputs::Dict{String}, outputs::Dict{String}` as the arguments.

```julia
program_bowtie2 = CmdProgram(
	...,
	wrap_up = (inputs, outputs) -> run(`samtools index $(outputs["BAM"])`)
)
```

### The Final Code

All in all, the final program is like this:

```julia
program_bowtie2 = CmdProgram(
	name = "Bowtie2 Mapping",
	id_file = ".bowtie2",

	inputs = ["FASTQ", "REF"],
	validate_inputs = inputs -> begin
		check_dependency_file(inputs["FASTQ"]) &&
		check_dependency_file(inputs["REF"])
	end,

	prerequisites = (inputs, outputs) -> begin
		mkpath(dirname(to_str(outputs["BAM"])))
	end,

	outputs = ["BAM"],
	infer_outputs = inputs -> begin
		Dict("BAM" => str(inputs["FASTQ"]) * ".bam")
	end,
	validate_outputs = outputs -> begin
		check_dependency_file(outputs["BAM"])
	end,

	cmd = pipeline(`bowtie2 -x REF -q FASTQ`, `samtools sort -O bam -o BAM`),

	wrap_up = (inputs, outputs) -> run(`samtools index $(outputs["BAM"])`)
)
```

## Structure

`CmdProgram` can be built with this method:

```julia
CmdProgram(;
	name::String               = "Unnamed Command Program",
	id_file::String            = "",
	info_before::String        = "auto",
	info_after::String         = "auto",
	cmd_dependencies::Vector{CmdDependency} = Vector{CmdDependency}(),
	inputs::Vector{String}     = Vector{String}(),
	validate_inputs::Function  = do_nothing,  # positional arguments: inputs::Dict{String}
	prerequisites::Function    = do_nothing,  # positional arguments: inputs, outputs::Dict{String}
	cmd::Base.AbstractCmd      = ``,
	infer_outputs::Function    = do_nothing,  # positional arguments: inputs::Dict{String}
	outputs::Vector{String}    = Vector{String}(),
	validate_outputs::Function = do_nothing,  # positional arguments: outputs::Dict{String},
	wrap_up::Function          = do_nothing   # positional arguments: inputs, outputs::Dict{String}
) -> CmdProgram
```

In this way, all preparation and post-evaluation can be wrapped in a single `CmdProgram`. It is easy to maintain and use.

To run a `CmdProgram`, use one of the following methods:

```julia
run(
	p::CmdProgram;
	inputs::Dict{String}=Dict{String, Cmd}(),
	outputs::Dict{String}=Dict{String, Cmd}(),
	skip_when_done::Bool=true,
	check_dependencies::Bool=true,
	stdout=nothing,
	stderr=nothing,
	append::Bool=false,
	verbose::Bool=true,
	touch_run_id_file::Bool=true,
	dry_run::Bool=false
) -> (success::Bool, outputs::Dict{String})

run(
	p::CmdProgram,
	inputs::Dict{String},
	outputs::Dict{String};
	kwargs...
)

run(
	p::CmdProgram,
	inputs::Dict{String},
	kwargs...
)  # only usable when `p.infer_outputs` is defined.
```

The explanation of arguments is in the next section.

## Workflow

1. **Check keywords consistency:** Inputs/outputs keywords should be consistent in both `p::CmdProgram` and `run(p; inputs, outputs)`.

   > For example, if inputs and outputs in `p::CmdProgram` is defined this way
   >
   > ```julia
   > p = CmdProgram(..., inputs = ["I", "J"], outputs = ["K"])
   > ```
   >
   > The inputs and outputs in `run(...)` has to be
   >
   > ```julia
   > run(p;
   >     inputs = Dict(
   >         "I" => something,
   >         "J" => something
   >     ),
   >     outputs = Dict("K" => something)
   > )
   > ```

2. Print info about starting program.

   > The content can set by `p.info_before::String`.
   >
   > Disable: `run(..., verbose=false)`

3. Check whether the program ran successfully before. If so, return `(true, outputs::Dict{String})` without running it.

   > **How does the program know it ran before?**
   >
   > a. `run(..., skip_when_down=true)` enables the functionality.
   >
   > b. Run id file is generated. The prefix of run id file is set by `p.id_file`. After given inputs and outputs, a unique ID will be appended to the prefix. You can use `run(..., touch_run_id_file=false)` to skip creating the run id file.
   >
   > c. `p.validate_outputs(outputs)` run successfully without returning `false`.

4. Check command dependencies (`CmdDependency`).

   > Disable: `run(..., check_dependencies=false)`
   >
   > Read **Command Dependency** portion for details.

5. Remove the run id file if exists.

6. Validate inputs by invoking `p.validate_inputs(inputs)`.

7. Preparing the main command.

   > If you specify `run(...; stdout=something, stderr=something, append::Bool)`, the command (`cmd`) will be wrapped with `pipeline(cmd; stdout=something, stderr=something, append::Bool)`. If `cmd` has its own file redirection, the outer wrapper may not work as you expect.

8. Meet prerequisites by invoking `p.prerequisites(inputs, outputs)`.

   > It is the last function before running the main command.  For example, you can create a directory if  the main command cannot create itself.

9. Run the main command.

10. Validate outputs by invoking `p.validate_outputs(outputs)`.

11. Run the wrap up function by invoking `p.wrap_up(inputs, outputs)`

    > It is the last function to do after-command jobs. For example, you can delete intermediate files if necessary.

12. Create run id file if `run(..., touch_run_id_file=true)`. Read Step 3 for details.

13. Print info about finishing program.

    > The content can set by `p.info_after::String`.
    >
    > Disable: `run(..., verbose=false)`

14. Return `(success::Bool, outputs{String})`

!!! note "Dry Run"
    `run(..., dry_run=true)` will return `(mature_command::AbstractCmd, run_id_file::String)` instead.
