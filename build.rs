use std::{env, path::PathBuf, process::Command};

use serde::Deserialize;

// A few helpers taken from https://github.com/Brendonovich/swift-rs/blob/master/src-rs/build.rs
// However could not be bothered creating a whole Swift package in Xcode.

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SwiftTargetInfo {
    pub triple: String,
    pub unversioned_triple: String,
    pub module_triple: String,
    //pub swift_runtime_compatibility_version: String,
    #[serde(rename = "librariesRequireRPath")]
    pub libraries_require_rpath: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SwiftPaths {
    pub runtime_library_paths: Vec<String>,
    pub runtime_library_import_paths: Vec<String>,
    pub runtime_resource_path: String,
}

#[derive(Debug, Deserialize)]
pub struct SwiftTarget {
    pub target: SwiftTargetInfo,
    pub paths: SwiftPaths,
}

const MACOS_TARGET_VERSION: &str = "12";

pub fn get_swift_target_info() -> SwiftTarget {
    let mut arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if arch == "aarch64" {
        arch = "arm64".into();
    }
    let target = format!("{}-apple-macosx{}", arch, MACOS_TARGET_VERSION);

    let swift_target_info_str = Command::new("swift")
        .args(&["-target", &target, "-print-target-info"])
        .output()
        .unwrap()
        .stdout;

    serde_json::from_slice(&swift_target_info_str).unwrap()
}

pub fn link_swift() {
    let swift_target_info = get_swift_target_info();
    if swift_target_info.target.libraries_require_rpath {
        panic!("Libraries require RPath! Change minimum MacOS value to fix.")
    }

    swift_target_info
        .paths
        .runtime_library_paths
        .iter()
        .for_each(|path| {
            println!("cargo:rustc-link-search=native={}", path);
        });
}

fn swift_target() -> String {
    let mut arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if arch == "aarch64" {
        arch = "arm64".into();
    }
    format!("{}-apple-macosx12", arch)
}
fn main() {
    println!("cargo:rerun-if-changed=src/observer.swift");
    println!("cargo:rerun-if-changed=src/host.h");
    let profile = env::var("PROFILE").unwrap();
    let out_dir = env::var("OUT_DIR").unwrap();
    let mut out_dir_path = PathBuf::from(&out_dir);
    out_dir_path.push("observer.o");
    let output = out_dir_path.to_str().unwrap();

    let mut args = Vec::new();
    args.push("-o");
    args.push(&output);
    if profile == "release" {
        args.push("-O");
    }
    let t = swift_target();
    args.push("-target");
    args.push(&t);
    args.push("-c");
    args.push("src/observer.swift");
    args.push("-module-name");
    args.push("observer");
    args.push("-emit-dependencies");
    args.push("-parse-as-library");
    args.push("-emit-object");
    args.push("-swift-version");
    args.push("5");
    args.push("-import-objc-header");
    args.push("src/host.h");
    let mut cmd = Command::new("swiftc");
    cmd.args(&args);
    eprintln!("command: {:?}", &cmd);

    if !cmd.status().unwrap().success() {
        panic!("failed to compile swift code");
    }

    let mut archive = Command::new("ar");
    out_dir_path.pop();
    let mut ar_path = out_dir_path.clone();
    ar_path.push("libobserver.a");
    out_dir_path.push("observer.o");

    let library = ar_path.to_str().unwrap();
    let object_file = out_dir_path.to_str().unwrap();

    archive.args(&["-rcs", library, object_file]);
    if !archive.status().unwrap().success() {
        panic!("failed to write static library libobserver.a");
    }
    println!("cargo:rustc-link-lib=static=observer");
    println!("cargo:rustc-link-search=native={}", out_dir);

    link_swift();
}
