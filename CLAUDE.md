# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EDAMAME CLI provides a complete command-line interface to EDAMAME Core services via RPC. It supports interactive exploration, method discovery, and direct RPC calls.

Part of the EDAMAME ecosystem - see `../edamame_core/CLAUDE.md` for full ecosystem documentation.

## Build Commands

```bash
# Standard build
cargo build --release

# Platform-specific (via Makefile)
make macos
make linux
make linux_alpine    # MUSL target
make windows

# Generate shell completions
make completions
```

## Testing

```bash
make test  # Runs cargo test -- --nocapture
```

## CLI Commands

```bash
# Method discovery
edamame-cli list-methods              # List all available RPC methods
edamame-cli list-method-infos         # List all methods with details
edamame-cli get-method-info <METHOD>  # Get info about specific method

# RPC calls
edamame-cli rpc <METHOD> [JSON_ARGS]  # Call RPC method with JSON arguments

# Interactive mode
edamame-cli interactive               # REPL for RPC exploration

# Shell completions
edamame-cli completion <SHELL>        # Generate completions (bash/fish/zsh)
```

### RPC Examples

```bash
# Simple call
edamame-cli rpc get_score

# With arguments (array form)
edamame-cli rpc some_method '["arg1", "arg2"]'

# With arguments (object form)
edamame-cli rpc some_method '{"param": "value"}'
```

## Architecture

Single-file architecture in `src/main.rs`:

- `build_cli()` - CLI construction with clap
- `initialize_core()` - EDAMAME Core initialization
- `handle_rpc()` - RPC call handler with JSON parsing
- `interactive_mode()` - Interactive shell implementation
- `fetch_method_meta()` - RPC method metadata retrieval
- `best_suggestion()` - Fuzzy matching for error recovery

## Verbosity Levels

- `-v` - Info logging
- `-vv` - Debug logging
- `-vvv` - Trace logging

## Dependencies

- `edamame_core` (with `swiftrs` feature) - Core functionality
- `clap` + `clap_complete` - CLI framework
- `serde_json` - JSON parsing

## Cross-Platform Targets

Defined in `Cross.toml`:
- x86_64-unknown-linux-gnu/musl
- i686-unknown-linux-gnu
- aarch64-unknown-linux-gnu/musl
- armv7-unknown-linux-gnueabihf

## Local Development

Use `../edamame_app/flip.sh local` to switch to local path dependencies.
