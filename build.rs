use vergen_gitcl::{Build, Cargo, Emitter, Gitcl, Rustc};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Emit the instructions (vergen-gitcl 10.x API)
    // Try without idempotent first to get real values on native builds.
    // Fall back to idempotent mode only if it fails (e.g., no git metadata).
    // No vergen sysinfo instructions: they refresh every process on the build
    // host (sysinfo's System::new_all), the enumeration the Windows CI
    // detection gates flag, and nothing here reads VERGEN_SYSINFO_*.
    let build = Build::all_build();
    let cargo = Cargo::all_cargo();
    let gitcl = Gitcl::all_git();
    let rustc = Rustc::all_rustc();

    if Emitter::default()
        .add_instructions(&build)?
        .add_instructions(&cargo)?
        .add_instructions(&gitcl)?
        .add_instructions(&rustc)?
        .emit()
        .is_err()
    {
        eprintln!(
            "cargo:warning=vergen failed to collect build metadata, using idempotent defaults"
        );
        Emitter::default()
            .idempotent()
            .add_instructions(&build)?
            .add_instructions(&cargo)?
            .add_instructions(&gitcl)?
            .add_instructions(&rustc)?
            .emit()?;
    }

    Ok(())
}
