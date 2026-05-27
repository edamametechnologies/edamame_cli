use crate::CORE_VERSION;
use clap::{arg, ArgAction, Command};
use clap_complete::{generate, Generator, Shell};
use edamame_core::api::api_core::*;
use edamame_core::api::api_rpc::*;
use envcrypt::envc;
use lazy_static::lazy_static;
use std::io::{self, BufRead, ErrorKind, Write};
use std::process::exit;

const ERROR_CODE_SERVER_ERROR: i32 = 12;
const ERROR_CODE_PARAM: i32 = 3;

lazy_static! {
    pub static ref EDAMAME_TARGET: String =
        envc!("EDAMAME_CORE_TARGET").trim_matches('"').to_string();
    pub static ref EDAMAME_CA_PEM: String = envc!("EDAMAME_CA_PEM").trim_matches('"').to_string();
    pub static ref EDAMAME_CLIENT_PEM: String =
        envc!("EDAMAME_CLIENT_PEM").trim_matches('"').to_string();
    pub static ref EDAMAME_CLIENT_KEY: String =
        envc!("EDAMAME_CLIENT_KEY").trim_matches('"').to_string();
}

/// Write to stdout with retry on WouldBlock/EAGAIN and graceful handling of
/// BrokenPipe. Regular `println!` panics when stdout is non-blocking and the
/// pipe buffer is full (common when the CLI is piped through shell processing
/// that doesn't drain fast enough). This function retries transient errors
/// and silently succeeds on pipe closure.
fn write_stdout(data: &str) -> io::Result<()> {
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    let mut buf = data.as_bytes();
    while !buf.is_empty() {
        match handle.write(buf) {
            Ok(n) => buf = &buf[n..],
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                std::thread::sleep(std::time::Duration::from_millis(1));
                continue;
            }
            Err(e) if e.kind() == ErrorKind::BrokenPipe => return Ok(()),
            Err(e) => return Err(e),
        }
    }
    match handle.write_all(b"\n") {
        Ok(()) => {}
        Err(e) if e.kind() == ErrorKind::BrokenPipe => return Ok(()),
        Err(e) if e.kind() == ErrorKind::WouldBlock => loop {
            std::thread::sleep(std::time::Duration::from_millis(1));
            match handle.write_all(b"\n") {
                Ok(()) => break,
                Err(e) if e.kind() == ErrorKind::WouldBlock => continue,
                Err(e) if e.kind() == ErrorKind::BrokenPipe => return Ok(()),
                Err(e) => return Err(e),
            }
        },
        Err(e) => return Err(e),
    }
    match handle.flush() {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == ErrorKind::BrokenPipe => Ok(()),
        Err(e) if e.kind() == ErrorKind::WouldBlock => {
            std::thread::sleep(std::time::Duration::from_millis(1));
            match handle.flush() {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == ErrorKind::BrokenPipe => Ok(()),
                Err(_) => Ok(()),
            }
        }
        Err(e) => Err(e),
    }
}

fn print_completions<G: Generator>(gen: G, cmd: &mut Command) {
    generate(gen, cmd, cmd.get_name().to_string(), &mut io::stdout());
}

pub fn build_cli() -> Command {
    // Turn it into a &'static str by leaking it
    let core_version_runtime: String = CORE_VERSION.to_string();
    let core_version_static: &'static str = Box::leak(core_version_runtime.into_boxed_str());

    Command::new("edamame_cli")
        .version(core_version_static)
        .author("EDAMAME Technologies")
        .about("CLI RPC interface to edamame_core")
        .subcommand(
            Command::new("completion")
                .about("Generate shell completion scripts")
                .arg(
                    arg!(<SHELL> "The shell to generate completions for")
                        .value_parser(clap::value_parser!(Shell)),
                ),
        )
        .arg(
            arg!(
                -v --verbose ... "Verbosity level (-v: info, -vv: debug, -vvv: trace)"
            )
            .required(false)
            .action(ArgAction::Count)
            .global(true),
        )
        .subcommand(
            Command::new("list-methods")
                .about("List all available RPC methods")
                .long_about("List all available RPC methods\n\nUse this command to discover what methods you can call with 'get-method-info' and 'rpc'")
                .arg(
                    arg!(--pretty "Pretty print the method list")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
        )
        .subcommand(
            Command::new("get-method-info")
                .about("Get information about a specific RPC method")
                .long_about("Get information about a specific RPC method\n\nTo see available methods first:\n  edamame_cli list-methods\n\nThen get info for a specific method:\n  edamame_cli get-method-info <METHOD_NAME>")
                .arg(
                    arg!(<METHOD> "Method name (use 'list-methods' to see available methods)")
                        .required(true)
                        .value_parser(clap::value_parser!(String)),
                ),
        )
        .subcommand(
            Command::new("list-method-infos")
                .about("List information about all available RPC methods")
                .long_about("List information about all available RPC methods\n\nThis shows detailed info for every method, including required parameters")
        )
        .subcommand(Command::new("interactive").about("Enter interactive mode"))
        .subcommand(
            Command::new("rpc")
                .about("Call a specific RPC method")
                .arg(
                    arg!(<METHOD> "Method name")
                        .required(true)
                        .value_parser(clap::value_parser!(String)),
                )
                .arg(
                    arg!([JSON_ARGS_ARRAY] "JSON arguments array")
                        .required(false)
                        .value_parser(clap::value_parser!(String)),
                )
                .arg(
                    arg!(--pretty "Pretty print the JSON response")
                        .required(false)
                        .action(ArgAction::SetTrue),
                ),
        )
}

fn run() {
    let mut cmd = build_cli();
    let matches = cmd.clone().get_matches();

    // Handle completion subcommand before other commands
    if let Some(("completion", sub_matches)) = matches.subcommand() {
        let shell = sub_matches.get_one::<Shell>("SHELL").unwrap();
        print_completions(*shell, &mut cmd);
        return;
    }

    // Check for verbose flag count
    let verbose_level = matches.get_count("verbose");
    let log_level = match verbose_level {
        0 => None,
        1 => {
            eprintln!("Info logging enabled.");
            Some("info")
        }
        2 => {
            eprintln!("Debug logging enabled.");
            Some("debug")
        }
        _ => {
            eprintln!("Trace logging enabled.");
            Some("trace")
        }
    };

    if let Some(level) = log_level {
        std::env::set_var("EDAMAME_LOG_LEVEL", level);
    }

    let verbose = verbose_level > 0;

    let exit_code = match matches.subcommand() {
        Some(("list-methods", args)) => handle_list_methods(args.get_flag("pretty"), verbose),
        Some(("get-method-info", args)) => handle_get_method_info(
            args.get_one::<String>("METHOD").unwrap().to_string(),
            verbose,
        ),
        Some(("list-method-infos", _)) => handle_list_method_infos(verbose),
        Some(("rpc", args)) => handle_rpc(
            args.get_one::<String>("METHOD").unwrap().to_string(),
            match args.get_one::<String>("JSON_ARGS_ARRAY") {
                Some(json_args_array) => json_args_array.to_string(),
                None => "[]".to_string(),
            },
            args.get_flag("pretty"),
            verbose,
        ),
        Some(("interactive", _)) => {
            interactive_mode(verbose);
            0
        }
        _ => {
            initialize_core(verbose);
            eprintln!("Invalid command, use --help for more information");
            ERROR_CODE_PARAM
        }
    };

    // Properly terminate the core
    terminate(false);

    exit(exit_code);
}

fn initialize_core(console_logging: bool) {
    let device = SystemInfoAPI {
        device_id: "".to_string(),
        model: "".to_string(),
        brand: "".to_string(),
        os_name: "".to_string(),
        os_version: "".to_string(),
        ebpf_support: "".to_string(),
        ip4: "".to_string(),
        ip6: "".to_string(),
        mac: "".to_string(),
        peer_ids: vec![],
        is_online: false,
        flutter_app_version: "".to_string(),
    };

    // By changing the executable type, we can have different logging behavior
    // "cli" is a special case in the logger that logs to file
    // "cli_verbose" falls into the default case and logs to stdout
    let executable_type = if console_logging {
        "cli_verbose".to_string()
    } else {
        "cli".to_string()
    };

    initialize(
        executable_type,
        envc!("VERGEN_GIT_BRANCH").to_string(),
        "EN".to_string(),
        device,
        false,
        false,
        false,
        false,
        true,
        false,
    );
}

fn make_example_value(arg_type: &str, arg_name: &str) -> String {
    match arg_type {
        "String" => format!("\"example_{}\"", arg_name),
        "bool" => "true".to_string(),
        "i32" | "u32" | "i64" | "u64" | "usize" => "123".to_string(),
        "f32" | "f64" => "1.5".to_string(),
        t if t.starts_with("Vec<") => "[]".to_string(),
        t if t.starts_with("Option<") => "null".to_string(),
        _ => format!("\"example_{}\"", arg_name),
    }
}

fn print_method_help_with_meta(method: &str, return_type: &str, args_meta: &[(String, String)]) {
    let _ = write_stdout(&format!("Method: {}", method));
    let _ = write_stdout(&format!("Return type: {}", return_type));
    if !args_meta.is_empty() {
        let _ = write_stdout("Arguments:");
        for (name, arg_type) in args_meta {
            let _ = write_stdout(&format!("  - {}: {}", name, arg_type));
        }
    } else {
        let _ = write_stdout("Arguments: None");
    }

    let _ = write_stdout("\nUsage examples:");
    if !args_meta.is_empty() {
        let example_values: Vec<String> = args_meta
            .iter()
            .map(|(name, ty)| make_example_value(ty, name))
            .collect();
        let _ = write_stdout(&format!(
            "  edamame_cli rpc {} '[{}]'",
            method,
            example_values.join(", ")
        ));
        let _ = write_stdout(&format!(
            "  edamame_cli rpc {} '[{}]' --pretty",
            method,
            example_values.join(", ")
        ));

        let example_object_fields: Vec<String> = args_meta
            .iter()
            .map(|(name, ty)| format!("\"{}\": {}", name, make_example_value(ty, name)))
            .collect();
        let _ = write_stdout(&format!(
            "  edamame_cli rpc {} '{{{}}}'",
            method,
            example_object_fields.join(", ")
        ));
        let _ = write_stdout(&format!(
            "  edamame_cli rpc {} '{{{}}}' --pretty",
            method,
            example_object_fields.join(", ")
        ));

        let _ = write_stdout("\nParameter mapping (array form):");
        for (i, (name, arg_type)) in args_meta.iter().enumerate() {
            let _ = write_stdout(&format!("  [{}] -> {} ({})", i, name, arg_type));
        }

        let _ = write_stdout("\nNotes:");
        let _ = write_stdout(
            "  - You can pass arguments as a JSON array of values or a single JSON object.",
        );
        let _ = write_stdout(
            "  - In array form, each element must be a valid JSON literal of the expected type.",
        );
        let _ =
            write_stdout("  - In object form, use the exact argument names shown above as keys.");
    } else {
        let _ = write_stdout(&format!("  edamame_cli rpc {}", method));
        let _ = write_stdout(&format!("  edamame_cli rpc {} --pretty", method));
    }
}

fn fetch_method_meta(method: &str) -> Result<(String, Vec<(String, String)>), String> {
    match rpc_get_api_info(
        method.to_string(),
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(Some(api_info)) => Ok((
            api_info.return_type,
            api_info
                .args
                .into_iter()
                .map(|a| (a.name, a.arg_type))
                .collect(),
        )),
        Ok(None) => Err(format!("No information available for method: {}", method)),
        Err(e) => Err(format!("Could not fetch method info: {:?}", e)),
    }
}

fn print_method_help_from_core(method: &str) {
    match fetch_method_meta(method) {
        Ok((return_type, args_meta)) => {
            print_method_help_with_meta(method, &return_type, &args_meta);
        }
        Err(e) => {
            eprintln!("{}", e);
        }
    }
}

fn levenshtein(a: &str, b: &str) -> usize {
    let mut costs: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.chars().enumerate() {
        let mut last_cost = i;
        let mut current_cost;
        costs[0] = i + 1;
        for (j, cb) in b.chars().enumerate() {
            current_cost = costs[j + 1];
            let mut new_cost = if ca == cb { last_cost } else { last_cost + 1 };
            new_cost = new_cost.min(costs[j + 1] + 1);
            new_cost = new_cost.min(costs[j] + 1);
            last_cost = current_cost;
            costs[j + 1] = new_cost;
        }
    }
    costs[b.len()]
}

fn best_suggestion(input: &str, candidates: &[String]) -> Option<String> {
    let mut best: Option<(usize, String)> = None;
    for cand in candidates {
        let d = levenshtein(input, cand);
        match &mut best {
            Some((bd, _)) => {
                if d < *bd {
                    *bd = d;
                    best = Some((d, cand.clone()));
                }
            }
            None => {
                best = Some((d, cand.clone()));
            }
        }
    }
    if let Some((dist, name)) = best {
        if dist <= 2 {
            Some(name)
        } else {
            None
        }
    } else {
        None
    }
}

fn handle_rpc(method: String, json_args_array: String, pretty: bool, verbose: bool) -> i32 {
    initialize_core(verbose);

    // Parse the user-supplied JSON args into the single JSON-object string
    // the daemon expects on the wire. Supports three input shapes:
    //
    //   * `[]` or omitted        -> zero-argument call (no object sent)
    //   * `{"k": v, ...}`        -> passed through verbatim
    //   * `[v1, v2, ...]`        -> positional; mapped to the named-arg
    //                               object via a `get_api_info` lookup against
    //                               the daemon (the daemon is the source of
    //                               truth for arg names).
    //
    // The wire dispatch goes through `rpc_call_remote`, which forwards
    // `(method, args)` directly to the daemon's gRPC `execute` endpoint
    // without consulting the CLI's local RPC registry. This means
    // `edamame_cli` does NOT have to be rebuilt every time a new RPC
    // method is added to `edamame_core` -- the daemon dispatches by name,
    // not by local stub.
    let args_object_json: Option<String> = match serde_json::from_str::<serde_json::Value>(
        &json_args_array,
    ) {
        Ok(serde_json::Value::Array(values)) => {
            if values.is_empty() {
                None
            } else {
                match fetch_method_meta(&method) {
                    Ok((_ret, args_meta)) => {
                        if values.len() != args_meta.len() {
                            eprintln!(
                                ">>>> Argument count mismatch for {}: provided {}, expected {}",
                                method,
                                values.len(),
                                args_meta.len()
                            );
                            print_method_help_from_core(&method);
                            return ERROR_CODE_PARAM;
                        }
                        let mut map = serde_json::Map::with_capacity(args_meta.len());
                        for ((name, _ty), value) in args_meta.iter().zip(values.into_iter()) {
                            map.insert(name.clone(), value);
                        }
                        match serde_json::to_string(&serde_json::Value::Object(map)) {
                            Ok(s) => Some(s),
                            Err(e) => {
                                eprintln!(">>>> Error serializing positional arguments: {:?}", e);
                                return ERROR_CODE_PARAM;
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("{}", e);
                        eprintln!(
                            ">>>> Cannot map positional arguments without API metadata. \
                             If the daemon supports this method but did not return metadata, \
                             try the object form: edamame_cli rpc {} '{{\"arg1\": value, ...}}'",
                            method
                        );
                        return ERROR_CODE_PARAM;
                    }
                }
            }
        }
        Ok(serde_json::Value::Object(map)) => {
            // Object form: pass through verbatim. We still consult the daemon
            // for a friendlier missing/unknown-fields diagnostic when the
            // daemon knows the method; if it doesn't (or metadata lookup
            // fails for any other reason), we forward the object as-is and
            // let the daemon return the authoritative error.
            if let Ok((_ret, args_meta)) = fetch_method_meta(&method) {
                let expected_names: Vec<String> =
                    args_meta.iter().map(|(n, _)| n.clone()).collect();
                let provided_names: Vec<String> = map.keys().cloned().collect();
                let missing: Vec<String> = expected_names
                    .iter()
                    .filter(|n| !map.contains_key(*n))
                    .cloned()
                    .collect();
                let unknown: Vec<String> = provided_names
                    .iter()
                    .filter(|n| !expected_names.contains(*n))
                    .cloned()
                    .collect();
                if !missing.is_empty() || !unknown.is_empty() {
                    if !missing.is_empty() {
                        for m in &missing {
                            eprintln!(
                                ">>>> Missing field '{}' in provided JSON object for method {}",
                                m, method
                            );
                        }
                    }
                    if !unknown.is_empty() {
                        eprintln!("Unknown fields present: {}", unknown.join(", "));
                        for u in &unknown {
                            if let Some(sugg) = best_suggestion(u, &expected_names) {
                                eprintln!(
                                    "     '{}' is not expected. Did you mean '{}' ?",
                                    u, sugg
                                );
                            }
                        }
                    }
                    print_method_help_from_core(&method);
                    return ERROR_CODE_PARAM;
                }
            }
            match serde_json::to_string(&serde_json::Value::Object(map)) {
                Ok(s) => Some(s),
                Err(e) => {
                    eprintln!(">>>> Error serializing object arguments: {:?}", e);
                    return ERROR_CODE_PARAM;
                }
            }
        }
        Ok(_) => {
            eprintln!(">>>> Error parsing JSON arguments: expected a JSON array or object");
            print_method_help_from_core(&method);
            return ERROR_CODE_PARAM;
        }
        Err(e) => {
            eprintln!(">>>> Error parsing JSON arguments: {:?}", e);
            print_method_help_from_core(&method);
            return ERROR_CODE_PARAM;
        }
    };
    let method_name_for_help = method.clone();
    match rpc_call_remote(
        &method,
        args_object_json.as_deref(),
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(result) => {
            let output = if pretty {
                if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&result) {
                    serde_json::to_string_pretty(&json_value).unwrap()
                } else {
                    format!("Result: {}", result)
                }
            } else {
                format!("Result: {}", result)
            };
            if let Err(e) = write_stdout(&output) {
                eprintln!(">>>> Error writing to stdout: {}", e);
                return ERROR_CODE_SERVER_ERROR;
            }
        }
        Err(e) => {
            eprintln!(">>>> Error calling RPC method: {:?}", e);
            print_method_help_from_core(&method_name_for_help);
            return ERROR_CODE_SERVER_ERROR;
        }
    }
    0
}

fn handle_list_methods(pretty: bool, verbose: bool) -> i32 {
    initialize_core(verbose);

    let mut methods = match rpc_get_api_methods(
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(methods) => methods,
        Err(e) => {
            eprintln!(">>>> Error getting API methods: {:?}", e);
            return ERROR_CODE_SERVER_ERROR;
        }
    };

    // Sort methods alphabetically
    methods.sort();

    if pretty {
        let _ = write_stdout("Available RPC methods:");
        for method in methods {
            let _ = write_stdout(&format!("  {}", method));
        }
    } else {
        let _ = write_stdout(&format!("Available RPC methods: {:?}", methods));
    }
    0
}

fn handle_get_method_info(method: String, verbose: bool) -> i32 {
    initialize_core(verbose);

    let info = match rpc_get_api_info(
        method.clone(),
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(info) => info,
        Err(e) => {
            eprintln!(">>>> Error getting API info: {:?}", e);
            return ERROR_CODE_SERVER_ERROR;
        }
    };

    match &info {
        Some(api_info) => {
            let args_meta: Vec<(String, String)> = api_info
                .args
                .iter()
                .map(|a| (a.name.clone(), a.arg_type.clone()))
                .collect();
            print_method_help_with_meta(&method, &api_info.return_type, &args_meta);
        }
        None => {
            println!("No information available for method: {}", method);
        }
    }

    0
}

fn handle_list_method_infos(verbose: bool) -> i32 {
    initialize_core(verbose);

    // Get the list of all methods
    let methods = match rpc_get_api_methods(
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(methods) => methods,
        Err(e) => {
            eprintln!(">>>> Error getting API methods: {:?}", e);
            return ERROR_CODE_SERVER_ERROR;
        }
    };

    // Iterate over the list of methods and get the info for each one
    for method in methods {
        let info = match rpc_get_api_info(
            method.clone(),
            &EDAMAME_CA_PEM,
            &EDAMAME_CLIENT_PEM,
            &EDAMAME_CLIENT_KEY,
            &EDAMAME_TARGET,
        ) {
            Ok(info) => info,
            Err(e) => {
                eprintln!(">>>> Error getting API info: {:?}", e);
                continue;
            }
        };

        let _ = write_stdout(&format!("Method: {}, Info: {:?}", method, info));
    }
    0
}

fn interactive_mode(verbose: bool) {
    initialize_core(verbose);

    println!("Entering interactive mode. Type 'exit' to leave.");
    println!("Usage: <method> [JSON args object or array]");
    println!("  e.g.  get_score");
    println!("        get_score {{\"complete_only\": false}}");
    let stdin = io::stdin();
    let mut reader = stdin.lock();
    let mut line = String::new();

    loop {
        line.clear();
        print!("> ");
        io::stdout().flush().unwrap();
        reader.read_line(&mut line).unwrap();

        let trimmed = line.trim();
        if trimmed == "exit" {
            break;
        }
        if trimmed.is_empty() {
            continue;
        }

        // Split off the method name; treat the rest of the line as the JSON
        // argument blob (object or array). Anything that is not a JSON object
        // or array is rejected; positional whitespace-split tokens are not
        // supported here because the wire format the daemon dispatcher
        // expects is a single named-arg JSON object.
        let (command, args_blob) = match trimmed.split_once(char::is_whitespace) {
            Some((cmd, rest)) => (cmd.to_string(), rest.trim().to_string()),
            None => (trimmed.to_string(), String::new()),
        };

        let args_object_json: Option<String> = if args_blob.is_empty() {
            None
        } else {
            match serde_json::from_str::<serde_json::Value>(&args_blob) {
                Ok(serde_json::Value::Object(_)) => Some(args_blob.clone()),
                Ok(serde_json::Value::Array(values)) => {
                    if values.is_empty() {
                        None
                    } else {
                        match fetch_method_meta(&command) {
                            Ok((_ret, args_meta)) => {
                                if values.len() != args_meta.len() {
                                    eprintln!(
                                        ">>>> Argument count mismatch for {}: provided {}, expected {}",
                                        command,
                                        values.len(),
                                        args_meta.len()
                                    );
                                    continue;
                                }
                                let mut map = serde_json::Map::with_capacity(args_meta.len());
                                for ((name, _ty), value) in
                                    args_meta.iter().zip(values.into_iter())
                                {
                                    map.insert(name.clone(), value);
                                }
                                match serde_json::to_string(&serde_json::Value::Object(map)) {
                                    Ok(s) => Some(s),
                                    Err(e) => {
                                        eprintln!(
                                            ">>>> Error serializing positional arguments: {:?}",
                                            e
                                        );
                                        continue;
                                    }
                                }
                            }
                            Err(e) => {
                                eprintln!("{}", e);
                                continue;
                            }
                        }
                    }
                }
                Ok(_) => {
                    eprintln!(
                        ">>>> Expected a JSON object {{...}} or array [...] after the method name"
                    );
                    continue;
                }
                Err(e) => {
                    eprintln!(">>>> Error parsing JSON arguments: {:?}", e);
                    continue;
                }
            }
        };

        match rpc_call_remote(
            &command,
            args_object_json.as_deref(),
            &EDAMAME_CA_PEM,
            &EDAMAME_CLIENT_PEM,
            &EDAMAME_CLIENT_KEY,
            &EDAMAME_TARGET,
        ) {
            Ok(result) => {
                let _ = write_stdout(&format!("Result: {}", result));
            }
            Err(e) => eprintln!(">>>> Error calling RPC method: {:?}", e),
        }
    }
}

pub fn main() {
    run();
}
