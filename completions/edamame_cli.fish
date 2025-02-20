# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
function __fish_edamame_cli_global_optspecs
	string join \n v/verbose h/help V/version
end

function __fish_edamame_cli_needs_command
	# Figure out if the current invocation already has a command.
	set -l cmd (commandline -opc)
	set -e cmd[1]
	argparse -s (__fish_edamame_cli_global_optspecs) -- $cmd 2>/dev/null
	or return
	if set -q argv[1]
		# Also print the command, so this can be used to figure out what it is.
		echo $argv[1]
		return 1
	end
	return 0
end

function __fish_edamame_cli_using_subcommand
	set -l cmd (__fish_edamame_cli_needs_command)
	test -z "$cmd"
	and return 1
	contains -- $cmd[1] $argv
end

complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -s V -l version -d 'Print version'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "completion" -d 'Generate shell completion scripts'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "list-methods" -d 'List all available RPC methods'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "get-method-info" -d 'Get information about a specific RPC method'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "list-method-infos" -d 'List information about all available RPC methods'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "interactive" -d 'Enter interactive mode'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "rpc" -d 'Call a specific RPC method'
complete -c edamame_cli -n "__fish_edamame_cli_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand completion" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand completion" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand list-methods" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand list-methods" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand get-method-info" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand get-method-info" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand list-method-infos" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand list-method-infos" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand interactive" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand interactive" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand rpc" -s v -l verbose -d 'Verbosity level (-v: info, -vv: debug, -vvv: trace)'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand rpc" -s h -l help -d 'Print help'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "completion" -d 'Generate shell completion scripts'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "list-methods" -d 'List all available RPC methods'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "get-method-info" -d 'Get information about a specific RPC method'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "list-method-infos" -d 'List information about all available RPC methods'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "interactive" -d 'Enter interactive mode'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "rpc" -d 'Call a specific RPC method'
complete -c edamame_cli -n "__fish_edamame_cli_using_subcommand help; and not __fish_seen_subcommand_from completion list-methods get-method-info list-method-infos interactive rpc help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
