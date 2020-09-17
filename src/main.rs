#![feature(raw)]
#![allow(non_snake_case)]

mod app;

#[macro_use]
extern crate objc;
use anyhow::Error;

use std::process::{Command, Stdio};
use structopt::StructOpt;

#[derive(StructOpt)]
struct Options {
    #[structopt(short = "c")]
    command: Option<String>,
}

fn main() -> Result<(), Error> {
    let options = Options::from_args();
    unsafe {
        app::run(true, move |appearance| {
            if let Some(command) = options.command.as_ref() {
                let cmd = format!("{} {:?}", command, appearance);
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
                println!("{:?}", appearance);
            }
        })
    }
}
