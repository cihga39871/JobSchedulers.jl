# API

## Program
```@docs
Program
```

### Command Program
```@docs
CmdProgram()
run(::CmdProgram)
```

### Julia Program
```@docs
JuliaProgram()
run(::JuliaProgram)
```

### Common Methods
```@docs
infer_outputs(::Program, ::Dict{String})
check_dependency(::Program)
```

## Command Dependency
```@docs
CmdDependency()
check_dependency(::CmdDependency)
check_dependency_dir(path::AbstractString; exit_when_false=true)
check_dependency_file(path::AbstractString; exit_when_false=true)
```

## Utils
```@docs
to_str(::Cmd)
to_cmd(::Cmd)
split(::Cmd)
replaceext(::String, ::AbstractString)
removeext(::String)
```
