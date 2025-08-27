use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let target_dir = PathBuf::from(&crate_dir).join("../../../target");
    
    let config = cbindgen::Config {
        language: cbindgen::Language::C,
        ..Default::default()
    };
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_config(config)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(target_dir.join("relay_client_mobile.h"));
}