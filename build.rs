use vergen_gitcl::*;

#[cfg(target_os = "windows")]
use flodbadd::windows_npcap;

#[cfg(target_os = "windows")]
fn copy_npcap_dlls(npcap_dir: &std::path::Path) -> std::io::Result<()> {
    use std::env; use std::fs; use std::path::Path;
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());
    let profile = env::var("PROFILE").unwrap_or_else(|_| "debug".to_string());
    let target_dir = env::var("CARGO_TARGET_DIR").unwrap_or_else(|_| format!("{}{}target", manifest_dir, std::path::MAIN_SEPARATOR));
    let profile_dir = Path::new(&target_dir).join(&profile);
    let deps_dir = profile_dir.join("deps");
    fs::create_dir_all(&profile_dir)?; fs::create_dir_all(&deps_dir)?;
    for (src, dests) in [
        (npcap_dir.join("wpcap.dll"), [profile_dir.join("wpcap.dll"), deps_dir.join("wpcap.dll")]),
        (npcap_dir.join("Packet.dll"), [profile_dir.join("Packet.dll"), deps_dir.join("Packet.dll")])
    ] { let _ = fs::copy(&src, &dests[0]); let _ = fs::copy(&src, &dests[1]); }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "windows")]
    {
        #[cfg(target_env = "msvc")]
        { println!("cargo:rustc-link-arg=/DELAYLOAD:wpcap.dll"); println!("cargo:rustc-link-arg=/DELAYLOAD:Packet.dll"); println!("cargo:rustc-link-lib=dylib=delayimp"); }
        let npcap_dir = windows_npcap::get_npcap_dir();
        if npcap_dir.exists() { let _ = copy_npcap_dlls(&npcap_dir); println!("cargo:rustc-link-search=native={}", npcap_dir.display()); }
    }

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
