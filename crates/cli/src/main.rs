use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "rustai", about = "AI-generate-safe Rust CLI template")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 등록된 도메인 목록 (ncl/domains.ncl 기준)
    List,
    /// 도메인 레지스트리 진단
    Doctor,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::List => {
            let reg = rustai_core::Registry::load()?;
            if reg.domains.is_empty() {
                eprintln!("(nickel 미설치 또는 ncl eval 실패 — 폴백 모드)");
            }
            for name in reg.names() {
                println!("{name}");
            }
        }
        Commands::Doctor => {
            let nickel = rustai_core::common::has_cmd("nickel");
            println!("nickel CLI: {}", if nickel { "✓" } else { "✗ (brew install nickel)" });
            let reg = rustai_core::Registry::load()?;
            println!("domains loaded: {}", reg.domains.len());
        }
    }
    Ok(())
}
