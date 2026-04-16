#!/usr/bin/env bash
# ── new-domain.sh ──
# 새 도메인 스캐폴딩 + 즉시 Nickel 계약 검증.
# 검증 실패 시 생성된 파일 전부 롤백.
#
# 사용:
#   scripts/new-domain.sh <name> [description]
#
# 예:
#   scripts/new-domain.sh wave "파동 도메인 예시"

set -euo pipefail

NAME="${1:-}"
DESC="${2:-TODO: write description}"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <name> [description]"
  exit 1
fi

if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9]*$'; then
  echo "Error: domain name must be lowercase alphanumeric, no dashes. Got: $NAME"
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

DIR="crates/domains/$NAME"
if [ -e "$DIR" ]; then
  echo "Error: $DIR already exists"
  exit 1
fi

echo "[1/4] scaffolding $DIR"
mkdir -p "$DIR/src"

cat > "$DIR/Cargo.toml" <<EOF
[package]
name = "PROJECT-$NAME"
version.workspace = true
edition.workspace = true

[[bin]]
name = "PROJECT-$NAME"
path = "src/main.rs"

[dependencies]
clap = { workspace = true }
PROJECT-core = { workspace = true }
anyhow = { workspace = true }

[build-dependencies]
hardcoded-lint = { git = "https://github.com/dalsoop/hardcoded-lint", rev = "c943f1f" }
EOF

# PROJECT 자동 치환 (루트 Cargo.toml에서 rustai 감지)
CRATE_PREFIX=$(grep -E '^rustai-core =|^[a-z0-9_-]+-core = \{ path' Cargo.toml | head -1 | sed -E 's/^([a-z0-9_-]+)-core.*/\1/' || echo "rustai")
sed -i.bak "s|PROJECT|$CRATE_PREFIX|g" "$DIR/Cargo.toml" && rm -f "$DIR/Cargo.toml.bak"

cat > "$DIR/build.rs" <<'EOF'
fn main() {
    hardcoded_lint::check("src")
        .ipv4()
        .credentials()
        .env_fallback()
        .const_config()
        .domain()
        .email()
        .run();
}
EOF

cat > "$DIR/domain.ncl" <<EOF
let { Domain } = import "../../../ncl/contract.ncl" in
{
  name = "$NAME",
  description = "$DESC",
  tags = { product = 'template, layer = 'app },
  provides = ["$NAME status"],
} | Domain
EOF

cat > "$DIR/src/main.rs" <<EOF
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "${CRATE_PREFIX}-${NAME}", about = "${NAME} 도메인")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 상태 출력
    Status,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Status => println!("$NAME: ok"),
    }
    Ok(())
}
EOF

echo "[2/4] updating ncl/domains.ncl"
# Insert entry into domains = { ... } block (before the closing brace of domains)
python3 - "$NAME" "$DESC" <<'PY'
import re, sys, pathlib
name, desc = sys.argv[1], sys.argv[2]
p = pathlib.Path("ncl/domains.ncl")
src = p.read_text()
entry = f'''
    {name} = {{
      name = "{name}",
      description = "{desc}",
      tags = {{ product = 'template, layer = 'app }},
      provides = ["{name} status"],
    }} | Domain,
'''
# 마지막 도메인 엔트리 뒤, domains = { ... } 의 닫는 } 앞에 삽입
m = re.search(r"(\n  \},\n\})\s*$", src)
if not m:
    print("ncl/domains.ncl 구조가 예상과 다름", file=sys.stderr); sys.exit(1)
new = src[:m.start()] + entry + src[m.start():]
p.write_text(new)
PY

echo "[3/4] nickel eval (스키마 검증)"
if command -v nickel >/dev/null 2>&1; then
  if ! nickel export --format json "$DIR/domain.ncl" > /dev/null 2>&1 \
    || ! nickel export --format json ncl/domains.ncl > /dev/null 2>&1; then
    echo "✗ Nickel 계약 위반 — 롤백"
    rm -rf "$DIR"
    git checkout -- ncl/domains.ncl 2>/dev/null || true
    exit 1
  fi
fi

echo "[4/4] cargo check (컴파일 검증)"
if ! cargo check --workspace --quiet 2>&1 | tail -5; then
  echo "✗ cargo check 실패 — 롤백"
  rm -rf "$DIR"
  git checkout -- ncl/domains.ncl 2>/dev/null || true
  exit 1
fi

echo ""
echo "✓ 도메인 '$NAME' 생성 완료"
echo "  실행: cargo run -p ${CRATE_PREFIX}-${NAME} -- status"
