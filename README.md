# EDAMAME CLI

This is a complete interface to EDAMAME Core services.
It works with both the EDAMAME Security app and EDAMAME Posture.

## Installation

### Linux (Debian/Ubuntu/Raspbian)

#### APT Repository Method (Recommended)

> **Raspberry Pi Users**: EDAMAME CLI fully supports Raspberry Pi OS (formerly Raspbian) on all Raspberry Pi models.
```bash
# Add the EDAMAME GPG Key
wget -O - https://edamame.s3.eu-west-1.amazonaws.com/repo/public.key | sudo gpg --dearmor -o /usr/share/keyrings/edamame.gpg

# Add the Repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/edamame.gpg] https://edamame.s3.eu-west-1.amazonaws.com/repo stable main" | sudo tee /etc/apt/sources.list.d/edamame.list

# Install EDAMAME CLI
sudo apt update
sudo apt install edamame-cli
```

#### Alpine APK Repository Method
```bash
# Import the public key
wget -O /tmp/edamame.rsa.pub https://edamame.s3.eu-west-1.amazonaws.com/repo/alpine/v3.15/x86_64/edamame.rsa.pub
sudo cp /tmp/edamame.rsa.pub /etc/apk/keys/

# Add the repository
echo "https://edamame.s3.eu-west-1.amazonaws.com/repo/alpine/v3.15/main" | sudo tee -a /etc/apk/repositories

# Install EDAMAME CLI
sudo apk update
sudo apk add edamame-cli
```

#### Manual Binary Installation
Download the appropriate binary for your architecture from the [releases page](https://github.com/edamametechnologies/edamame_cli/releases):
- **x86_64**: `edamame_cli-VERSION-x86_64-unknown-linux-gnu`
- **i686**: `edamame_cli-VERSION-i686-unknown-linux-gnu`
- **aarch64**: `edamame_cli-VERSION-aarch64-unknown-linux-gnu`
- **armv7**: `edamame_cli-VERSION-armv7-unknown-linux-gnueabihf`
- **x86_64 musl (Alpine)**: `edamame_cli-VERSION-x86_64-unknown-linux-musl`
- **aarch64 musl (Alpine)**: `edamame_cli-VERSION-aarch64-unknown-linux-musl`

```bash
chmod +x edamame_cli-*
sudo mv edamame_cli-* /usr/local/bin/edamame_cli
```

### macOS

#### Homebrew Installation (Recommended)
```bash
# Add the EDAMAME tap
brew tap edamametechnologies/tap

# Install EDAMAME CLI
brew install edamame-cli
```

#### Manual Binary Installation
Download the universal macOS binary from the [releases page](https://github.com/edamametechnologies/edamame_cli/releases):
- **Universal**: `edamame_cli-VERSION-universal-apple-darwin`

```bash
chmod +x edamame_cli-*
sudo mv edamame_cli-* /usr/local/bin/edamame_cli
```

### Windows

#### Chocolatey Installation (Recommended)
```powershell
choco install edamame-cli
```

#### Manual Binary Installation
Download the Windows binary from the [releases page](https://github.com/edamametechnologies/edamame_cli/releases):
- **x86_64**: `edamame_cli-VERSION-x86_64-pc-windows-msvc.exe`

Rename to `edamame_cli.exe`, move to a permanent location, and add to your system PATH.

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

- **EDAMAME Core**: The core implementation used by all EDAMAME components (closed source). See **[EDAMAME Core API](https://github.com/edamametechnologies/edamame_core_api)** for public API documentation
- **[EDAMAME Core API](https://github.com/edamametechnologies/edamame_core_api)**: Public API documentation for EDAMAME Core -- architecture, 150+ RPC methods, event system, gRPC and MCP interfaces
- **[EDAMAME Security](https://github.com/edamametechnologies/edamame_security)**: Desktop/mobile security application with full UI and enhanced capabilities (closed source)
- **[EDAMAME Foundation](https://github.com/edamametechnologies/edamame_foundation)**: Foundation library providing security assessment functionality
- **[EDAMAME Posture](https://github.com/edamametechnologies/edamame_posture_cli)**: CLI tool for security posture assessment and remediation
- **[EDAMAME Helper](https://github.com/edamametechnologies/edamame_helper)**: Helper application for executing privileged security checks
- **[EDAMAME CLI](https://github.com/edamametechnologies/edamame_cli)**: Interface to EDAMAME core services
- **[EDAMAME Posture GitHub Action](https://github.com/edamametechnologies/edamame_posture_action)**: CI/CD integration to enforce posture and network controls
- **[EDAMAME Posture GitLab Action](https://gitlab.com/edamametechnologies/edamame_posture_action)**: CI/CD integration to enforce posture and network controls
- **[Threat Models](https://github.com/edamametechnologies/threatmodels)**: Threat model definitions used throughout the system
- **[EDAMAME Hub](https://hub.edamame.tech)**: Web portal for centralized management when using these components in team environments
