# edamame_cli
This is a complete interface to EDAMAME core services.
It's useable with both EDAMAME Security application and EDAMAME Posture service.

## Usage

```bash
# Basic usage
edamame_cli [OPTIONS] <COMMAND>

# Global options
-v, --verbose     # Increase verbosity (-v: info, -vv: debug, -vvv: trace)
-h, --help        # Print help
-V, --version     # Print version

# Available commands:
list-methods      # List all available RPC methods
list-method-infos # List information about all available RPC methods
get-method-info   # Get information about a specific RPC method
interactive       # Enter interactive mode
rpc               # Call a specific RPC method

# Examples:
edamame_cli list-methods
edamame_cli get-method-info <METHOD>
edamame_cli list-method-infos
edamame_cli rpc <METHOD> '[JSON_ARGS_ARRAY]'     # JSON arguments
edamame_cli rpc <METHOD> '[JSON_ARGS_ARRAY]' --pretty  # Pretty-print JSON response
edamame_cli interactive                         # Enter interactive shell mode
```

## RPC Command

The `rpc` command allows calling specific methods with JSON arguments:

```bash
edamame_cli rpc <METHOD> '[JSON_ARGS_ARRAY]'
```

### Options

- `--pretty` - Format the JSON response with proper indentation and without escape characters

## EDAMAME Ecosystem

This CLI tool is part of the broader EDAMAME security ecosystem:

- **EDAMAME Core**: The core implementation used by all EDAMAME components (closed source)
- **[EDAMAME Security](https://github.com/edamametechnologies)**: Desktop/mobile security application with full UI and enhanced capabilities (closed source)
- **[EDAMAME Foundation](https://github.com/edamametechnologies/edamame_foundation)**: Foundation library providing security assessment functionality
- **[EDAMAME Posture](https://github.com/edamametechnologies/edamame_posture_cli)**: CLI tool for security posture assessment and remediation
- **[EDAMAME Helper](https://github.com/edamametechnologies/edamame_helper)**: Helper application for executing privileged security checks
- **[EDAMAME CLI](https://github.com/edamametechnologies/edamame_cli)**: Interface to EDAMAME core services
- **[GitHub Integration](https://github.com/edamametechnologies/edamame_posture_action)**: GitHub Action for integrating posture checks in CI/CD
- **[GitLab Integration](https://gitlab.com/edamametechnologies/edamame_posture_action)**: Similar integration for GitLab CI/CD workflows
- **[Threat Models](https://github.com/edamametechnologies/threatmodels)**: Threat model definitions used throughout the system
- **[EDAMAME Hub](https://hub.edamame.tech)**: Web portal for centralized management when using these components in team environments
