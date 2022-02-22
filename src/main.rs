#![allow(non_snake_case)]

mod app;

#[macro_use]
extern crate objc;
use anyhow::Error;

use std::process::{Command, Stdio};
use structopt::StructOpt;

/// Watcher for macOS 10.14+ light/dark mode changes
///
/// Will print "light" or "dark" as it changes. By default, it also prints the current appearance
/// at startup. Use Ctrl-C or type "quit<enter>" to quit.
#[derive(StructOpt)]
struct Options {
    /// Get the current appearance, print it or execute the command once, and exit.
    #[structopt(short = "e", long = "exit")]
    exit: bool,

    /// Run a command instead of printing
    #[structopt(short = "c")]
    command: Option<String>,

    /// Does not print the initial value, only prints actual changes.
    #[structopt(short = "o", long = "only-changes")]
    only_changes: bool,
}

fn handle_quit() -> Result<(), Error> {
    std::thread::spawn(move || {
        use std::io::BufRead;
        let stdin = std::io::stdin();
        for line in stdin.lock().lines() {
            if line.unwrap().trim() == "quit" {
                std::process::exit(0);
            }
        }
    });
    Ok(())
}

fn main() -> Result<(), Error> {
    let options = Options::from_args();
    handle_quit()?;
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
