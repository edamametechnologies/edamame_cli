use vergen_gitcl::*;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Emit the instructions
    let build = BuildBuilder::all_build()?;
    let cargo = CargoBuilder::all_cargo()?;
    let gitcl = GitclBuilder::all_git()?;
    let rustc = RustcBuilder::all_rustc()?;
    let si = SysinfoBuilder::all_sysinfo()?;

    match Emitter::default()
        .add_instructions(&build)?
        .add_instructions(&cargo)?
        .add_instructions(&gitcl)?
        .add_instructions(&rustc)?
        .add_instructions(&si)?
        .emit()
    {
        Ok(_) => (),
        Err(e) => {
            eprintln!("Error emitting: {}", e);
            panic!("Error emitting: {}", e);
        }
    }

    Ok(())
}
