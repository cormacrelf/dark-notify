#![allow(non_snake_case)]

mod app;

use clap::Parser;
use std::process::{Command, Stdio};

/// Watcher for macOS 10.14+ light/dark mode changes
///
/// Will print "light" or "dark" as it changes. By default, it also prints the current appearance
/// at startup. Use Ctrl-C to exit.
#[derive(Parser)]
struct Options {
    /// Get the current appearance, print it or execute the command once, and exit.
    #[arg(short = 'e', long = "exit")]
    exit: bool,

    /// Run a command instead of printing
    #[arg(short = 'c')]
    command: Option<String>,

    /// Does not print the initial value, only prints actual changes.
    #[arg(short = 'o', long = "only-changes")]
    only_changes: bool,
}

fn main() {
    let options = Options::parse();
    app::run(!options.only_changes || options.exit, move |appearance| {
        if let Some(command) = options.command.as_ref() {
            let cmd = format!("{} {}", command, appearance);
            let result = Command::new("sh")
                .arg("-c")
                .arg(&cmd)
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .spawn();
            match result {
                Ok(_) => {}
                Err(_) => {}
            }
        } else {
            println!("{}", appearance);
        }
        if options.exit {
            std::process::exit(0);
        }
    })
}
