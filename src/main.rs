use crate::CORE_VERSION;
use clap::{arg, ArgAction, Command};
use clap_complete::{generate, Generator, Shell};
use edamame_core::api::api_core::*;
use edamame_core::api::api_rpc::*;
use envcrypt::envc;
use lazy_static::lazy_static;
use std::io::{self, BufRead, Write};
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
        Some(("list-methods", _)) => handle_list_methods(verbose),
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
        ip4: "".to_string(),
        ip6: "".to_string(),
        mac: "".to_string(),
        peer_ids: vec![],
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

fn handle_rpc(method: String, json_args_array: String, pretty: bool, verbose: bool) -> i32 {
    initialize_core(verbose);

    // Convert the json_args_array to a Vec<String>
    let args: Vec<String> = match serde_json::from_str(&json_args_array) {
        Ok(args) => args,
        Err(e) => {
            eprintln!(">>>> Error parsing JSON arguments: {:?}", e);
            return ERROR_CODE_PARAM;
        }
    };
    match rpc_call(
        method,
        args,
        &EDAMAME_CA_PEM,
        &EDAMAME_CLIENT_PEM,
        &EDAMAME_CLIENT_KEY,
        &EDAMAME_TARGET,
    ) {
        Ok(result) => {
            if pretty {
                // Try to parse the result as JSON
                if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&result) {
                    // Pretty print the JSON
                    println!("{}", serde_json::to_string_pretty(&json_value).unwrap());
                } else {
                    // If it's not valid JSON, print as is
                    println!("Result: {}", result);
                }
            } else {
                println!("Result: {:?}", result);
            }
        }
        Err(e) => {
            eprintln!(">>>> Error calling RPC method: {:?}", e);
            return ERROR_CODE_SERVER_ERROR;
        }
    }
    0
}

fn handle_list_methods(verbose: bool) -> i32 {
    initialize_core(verbose);

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
    println!("Available RPC methods: {:?}", methods);
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
            println!("Method: {}", api_info.method);
            println!("Return type: {}", api_info.return_type);
            if !api_info.args.is_empty() {
                println!("Arguments:");
                for arg in &api_info.args {
                    println!("  - {}: {}", arg.name, arg.arg_type);
                }
            } else {
                println!("Arguments: None");
            }

            // Provide dynamic usage examples
            println!("\nUsage examples:");
            if !api_info.args.is_empty() {
                // Create example values based on argument types (all as JSON strings since RPC expects Vec<String>)
                let example_args: Vec<String> = api_info
                    .args
                    .iter()
                    .map(|arg| {
                        match arg.arg_type.as_str() {
                            "String" => format!("\"example_{}\"", arg.name),
                            "bool" => "\"true\"".to_string(),
                            "i32" | "u32" | "i64" | "u64" | "usize" => "\"123\"".to_string(),
                            "f32" | "f64" => "\"1.5\"".to_string(),
                            _ => format!("\"example_{}\"", arg.name), // Default to string
                        }
                    })
                    .collect();

                println!(
                    "  edamame_cli rpc {} '[{}]'",
                    method,
                    example_args.join(", ")
                );
                println!(
                    "  edamame_cli rpc {} '[{}]' --pretty",
                    method,
                    example_args.join(", ")
                );

                // Show parameter mapping
                println!("\nParameter mapping:");
                for (i, arg) in api_info.args.iter().enumerate() {
                    println!("  [{}] -> {} ({})", i, arg.name, arg.arg_type);
                }

                println!("\nNote: All arguments must be JSON strings, even for non-string types.");
                println!("Examples of valid argument formats:");
                println!("  - String: \"my_value\"");
                println!("  - Boolean: \"true\" or \"false\"");
                println!("  - Number: \"123\" or \"1.5\"");
            } else {
                println!("  edamame_cli rpc {}", method);
                println!("  edamame_cli rpc {} --pretty", method);
            }
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

        println!("Method: {}, Info: {:?}", method, info);
    }
    0
}

fn interactive_mode(verbose: bool) {
    initialize_core(verbose);

    println!("Entering interactive mode. Type 'exit' to leave.");
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

        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts.is_empty() {
            continue;
        }

        let command = parts[0].to_string();
        let args: Vec<String> = parts[1..].iter().map(|&s| s.to_string()).collect();

        // Check if the command is valid
        match rpc_get_api_methods(
            &EDAMAME_CA_PEM,
            &EDAMAME_CLIENT_PEM,
            &EDAMAME_CLIENT_KEY,
            &EDAMAME_TARGET,
        ) {
            Ok(methods) => {
                if !methods.contains(&command) {
                    eprintln!(">>>> Invalid command");
                    continue;
                }
            }
            Err(e) => {
                eprintln!(">>>> Error getting API methods: {:?}", e);
                continue;
            }
        }

        match rpc_call(
            command,
            args,
            &EDAMAME_CA_PEM,
            &EDAMAME_CLIENT_PEM,
            &EDAMAME_CLIENT_KEY,
            &EDAMAME_TARGET,
        ) {
            Ok(result) => println!("Result: {:?}", result),
            Err(e) => eprintln!(">>>> Error calling RPC method: {:?}", e),
        }
    }
}

pub fn main() {
    run();
}
