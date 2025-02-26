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
edamame_cli interactive                         # Enter interactive shell mode
```
