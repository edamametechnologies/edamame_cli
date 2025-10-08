.PHONY: clean macos macos_release macos_debug macos_publish windows windows_debug windows_release windows_publish linux linux_debug linux_release linux_publish upgrade unused_dependencies format test completions

# Import and export env for edamame_core and edamame_foundation
-include ../secrets/lambda-signature.env
-include ../secrets/foundation.env
-include ../secrets/sentry.env
export

completions:
	mkdir -p ./completions
	./target/release/edamame_cli completion bash > ./completions/edamame_cli.bash
	./target/release/edamame_cli completion fish > ./completions/edamame_cli.fish
	./target/release/edamame_cli completion zsh > ./completions/_edamame_cli

macos: macos_release completions

macos_release:
	cargo build --release

macos_debug:
	cargo build
	sudo bash -c "export RUST_BACKTRACE=1; export EDAMAME_LOG_LEVEL=info; rust-lldb ./target/debug/edamame_cli"

macos_publish: macos_release
	# Sign + hardened runtime
	./macos/sign.sh ./target/release/edamame_cli

windows: windows_release completions

windows_debug:
	cargo build
 
windows_release:
	cargo build --release

windows_publish: windows_release

linux: linux_release

linux_debug:
	cargo build

linux_release:
	cargo build --release

linux_publish: linux
	cargo deb

linux: linux_release completions

linux_alpine: linux_alpine_release

linux_alpine_debug:
	rustup target add x86_64-unknown-linux-musl
	cargo build --target x86_64-unknown-linux-musl

linux_alpine_release:
	rustup target add x86_64-unknown-linux-musl
	cargo build --release --target x86_64-unknown-linux-musl

linux_alpine_publish: linux_alpine_release

upgrade:
	rustup update
	cargo install -f cargo-upgrades
	cargo upgrades
	cargo update

unused_dependencies:
	cargo +nightly udeps

format:
	cargo fmt

clean:
	cargo clean
	rm -rf ./build/
	rm -rf ./target/

test:
	cargo test -- --nocapture