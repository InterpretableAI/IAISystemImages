module IAISystemImages

using SystemImageLoader
import REPL.TerminalMenus

const _install = include("install.jl")
const config = ArtifactConfig(_install)

function install()
  if isinteractive()
    names = [split(n, "__") for n in _install.names]

    # Get IAI version selection
    iai_versions = sort!(unique(getindex.(names, 2)), rev=true)
    iai_versions_disp = replace.(iai_versions, "IAI_" => "", "_" => ".")
    printstyled("Pick the IAI version you would like to install.\n"; bold=true, color=:blue)
    iai_menu = TerminalMenus.RadioMenu(iai_versions_disp)
    iai_index = TerminalMenus.request(iai_menu)
    iai_version = iai_versions_disp[iai_index]

    # Get Julia version selection
    julia_versions = sort!(unique(
        # Filter Julia versions to those supported by the selected IAI release
        n[1] for n in names if contains(n[2], iai_versions[iai_index])
    ), rev=true)
    julia_versions_disp = replace.(julia_versions, "Julia_" => "", "_" => ".")
    printstyled("Pick the Julia version you would like to use.\n"; bold=true, color=:blue)
    julia_menu = TerminalMenus.RadioMenu(
        [jv * ifelse(VersionNumber(jv) == VERSION, " (current)", "")
        for jv in julia_versions_disp]
    )
    julia_index = TerminalMenus.request(julia_menu)
    julia_version = julia_versions_disp[julia_index]

    # Get whether to create +IAI channel
    printstyled("Create `+IAI` alias for this version?\n"; bold=true, color=:blue)
    alias_menu = TerminalMenus.RadioMenu(["yes", "no"])
    create_alias = (TerminalMenus.request(alias_menu) == 1)

    # Run install
    install_version(; julia_version, iai_version, create_alias)
  else
    error("cannot use interactive install in non-interactive Julia session.")
  end
end

function install_version(;
    julia_version::Union{AbstractString,VersionNumber},
    iai_version::Union{AbstractString,VersionNumber},
    create_alias::Bool,
  )
  if julia_version isa VersionNumber
    julia_version = "v$julia_version"
  end
  if !startswith(julia_version, "v")
    throw(ArgumentError(
        "`julia_version` must be a `VersionNumber` or a version string " *
        "starting with \"v\""
    ))
  end
  julia_version = julia_version[2:end]

  if iai_version isa VersionNumber
    iai_version = "v$iai_version"
  end
  if startswith(iai_version, "v")
    iai_version = iai_version[2:end]
  else
    if iai_version != "dev"
      throw(ArgumentError(
          "`iai_version` must be a `VersionNumber`, a version string " *
          "starting with \"v\", or \"dev\""
      ))
    end
  end

  # Install corresponding artifact
  name = string(
      "Julia_v",
      replace(julia_version, "." => "_"),
      "__IAI_",
      iai_version == "dev" ? "" : "v",
      replace(iai_version, "." => "_"),
  )
  if name ∉ _install.names
    throw(ArgumentError(
        "No release exists for the chosen Julia and IAI versions"
    ))
  end
  _install.lookup(name)

  # Create juliaup channels
  if SystemImageLoader.has_juliaup()
    package = nameof(_install.mod)
    channel = "$julia_version/IAI/$iai_version"

    for line in readlines(`juliaup status`)
      if contains(line, " $channel ")
        if !success(`juliaup remove $channel`)
          @warn "failed to remove `$channel`."
        end
      end
    end

    loader = ```
        $(SystemImageLoader.system_image_loader()) --
            --julia=$julia_version
            --package=$package
            --image=$name
    --
    ```
    if !success(`juliaup link $channel $loader`)
      @warn "failed to link `$channel`."
    end

    if create_alias
      alias = "IAI"
      if !success(`juliaup remove $alias`)
        @warn "failed to remove `$alias`."
      end
      if !success(`juliaup link $alias julia $("+$channel")`)
        @warn "failed to link `$channel` to `$alias`."
      end
    end

    # Ensure that we actually have the exact channel versions required, and
    # not e.g 1.7 instead of 1.7.3.
    if success(`juliaup add $("$julia_version")`)
      @info "Added `juliaup` channel `$(julia_version)`"
    end

    if VersionNumber(julia_version) != VERSION
      @warn """
      ensure that you install `$package` in your global environment for Julia `$julia_version`. You can do this by running the following command in a terminal:

      julia +$julia_version -e 'using Pkg; Pkg.add(url="https://github.com/InterpretableAI/IAISystemImages.jl")'
      """
    end
  else
    error("`juliaup` is required for this package to work.")
  end
end

end # module
