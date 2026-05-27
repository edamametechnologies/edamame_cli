# EDAMAME CLI Architecture

Complete command-line interface to EDAMAME Core services via RPC.

## Overview

EDAMAME CLI provides direct access to all edamame_core functionality, enabling method discovery, interactive exploration, and scripted RPC calls.

## Module Structure

Single-file architecture in `src/main.rs`:

```rust
src/main.rs (~700 lines)
├── build_cli()          # CLI construction with clap
├── initialize_core()    # edamame_core initialization  
├── handle_rpc()         # RPC call handler with JSON parsing
├── interactive_mode()   # Interactive shell (REPL)
├── fetch_method_meta()  # RPC method metadata retrieval
└── best_suggestion()    # Fuzzy matching for error recovery
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CLI Interface (clap)                       │
│                edamame-cli <command> [options]                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Command Dispatcher                           │
│  • list-methods       → Enumerate all RPC methods               │
│  • list-method-infos  → Get all methods with details            │
│  • get-method-info    → Get specific method info                │
│  • rpc                → Execute RPC call                        │
│  • interactive        → Start REPL                              │
│  • completion         → Generate shell completions              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RPC Dispatcher                             │
│  • Parse JSON arguments (array or object form)                  │
│  • For positional args: query daemon for arg names              │
│  • Build named-arg JSON object                                  │
│  • Forward (method, args) to daemon over mTLS gRPC              │
│  • Format and return result                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              edamame_core daemon (gRPC execute)                 │
│        (daemon's HANDLER_REGISTRY does the dispatch)            │
└─────────────────────────────────────────────────────────────────┘
```

### Registry-independent dispatch (the daemon catalog is the source of truth)

The CLI does **not** require a client-side stub for the methods it
forwards. RPC calls go through
`edamame_core::api::api_rpc::rpc_call_remote`, which is a thin
pass-through to the gRPC `execute` endpoint:

```text
edamame_cli  ──(method, json_args_object)──►  daemon
                                                │
                                                ▼
                                        HANDLER_REGISTRY (daemon-side)
                                                │
                                                ▼
                                          <method>_async(...)
```

The wire protocol is just `(command: String, args: Vec<String>)`.
There is no client-side method-name lookup, no client-side type
re-validation of the arg object, and no client-side return-type
deserialization. The daemon is the single source of truth for the
RPC catalog: it owns the dispatch table and emits "Command not
found" itself when the method is unknown.

Operational consequence:

* **Adding a new RPC method in `edamame_core` does NOT require
  rebuilding/redeploying `edamame_cli`** -- as long as the daemon
  on the host has the method registered, any CLI version that ships
  this dispatch model can call it. This was specifically motivated
  by the FP-collection loop (`export_attack_pattern_finding_details`
  shipped in core before brew/choco/apt had pushed a refreshed CLI
  to the dogfood hosts).
* The `list-methods`, `list-method-infos`, and `get-method-info`
  commands ask the daemon for its catalog via the stable
  `get_api_methods` / `get_api_info` RPC, so even discovery is
  daemon-driven and doesn't rely on the CLI's compile-time view of
  the API.
* The CLI binary still needs to be rebuilt when the **wire
  protocol** changes (proto schema, mTLS handshake, command/args
  framing) or when the CLI's own subcommand surface needs to
  evolve. Those are infrequent.

The legacy registry-based `rpc_call` function in `edamame_core` is
preserved for callers that have the local stub and want the
client-side argument typing it provides; the CLI no longer uses it.

## Commands

### Method Discovery
```bash
edamame-cli list-methods              # List all available RPC methods
edamame-cli list-method-infos         # List methods with signatures
edamame-cli get-method-info <METHOD>  # Get specific method details
```

### RPC Execution
```bash
# Simple call (no arguments)
edamame-cli rpc get_score

# Array arguments
edamame-cli rpc some_method '["arg1", "arg2"]'

# Object arguments
edamame-cli rpc some_method '{"param": "value"}'

# Pretty-print JSON output
edamame-cli rpc get_score --pretty
```

### Interactive Mode
```bash
edamame-cli interactive
> get_score
{"stars": 4.2, "dimensions": {...}}
> compute_score
Computing...
> help
Available commands: ...
> exit
```

### Shell Completions
```bash
edamame-cli completion bash > ~/.bash_completion.d/edamame-cli
edamame-cli completion zsh > ~/.zsh/completions/_edamame-cli
edamame-cli completion fish > ~/.config/fish/completions/edamame-cli.fish
```

## Verbosity Levels

| Flag | Level | Description |
|------|-------|-------------|
| (none) | Warn | Warnings and errors only |
| `-v` | Info | Informational messages |
| `-vv` | Debug | Debug information |
| `-vvv` | Trace | Trace-level logging |

## JSON Argument Parsing

The CLI accepts two forms of JSON arguments:

```bash
# Array form (positional arguments)
edamame-cli rpc method_name '["arg1", 42, true]'

# Object form (named arguments)
edamame-cli rpc method_name '{"name": "value", "count": 42}'
```

Invalid JSON or type mismatches result in clear error messages with suggestions.

## Error Handling

The CLI provides helpful error recovery:

```bash
$ edamame-cli rpc get_scor  # Typo
Error: Method 'get_scor' not found
Did you mean: get_score?
```

## Dependencies

- `edamame_core` (with `swiftrs` feature) - Core functionality. See **[EDAMAME Core API](https://github.com/edamametechnologies/edamame_core_api)** for public API documentation
- `clap` + `clap_complete` - CLI framework
- `serde_json` - JSON parsing

## Cross-Platform Targets

Defined in `Cross.toml`:
- x86_64-unknown-linux-gnu
- x86_64-unknown-linux-musl (Alpine)
- i686-unknown-linux-gnu
- aarch64-unknown-linux-gnu
- aarch64-unknown-linux-musl (Alpine)
- armv7-unknown-linux-gnueabihf

## Installation

See [README.md](README.md) for installation instructions:
- APT repository (Debian/Ubuntu)
- APK repository (Alpine)
- Homebrew (macOS)
- Chocolatey (Windows)
- Direct binary download

## Related Documentation

- [README.md](README.md) - Installation and usage guide
