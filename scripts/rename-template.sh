#!/usr/bin/env bash
# ── rename-template.sh ──
# cargo-generate 미설치 환경용 fallback.
# `rustai` / `rustai-core` 토큰을 새 프로젝트 이름으로 일괄 치환.
#
# 사용:
#   scripts/rename-template.sh <new-project-name> [--apply]
#
# 인자:
#   new-project-name  kebab-case (예: vibe-stack). 내부적으로 snake_case도 생성.
#   --apply           실제 변경. 생략하면 dry-run (변경 목록만 출력).
#
# 권장 경로: cargo-generate 쓰는 게 더 안전함. 이건 의존성 최소화용 fallback.

set -euo pipefail

# UTF-8 안전 처리 (한글 주석 보존)
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8
export LANG="$LC_ALL"

NAME="${1:-}"
APPLY="${2:-}"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <new-project-name> [--apply]"
  echo "Example: $0 vibe-stack --apply"
  exit 1
fi

# 이름 검증 (kebab-case)
if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9-]*[a-z0-9]$'; then
  echo "Error: project name must be kebab-case (a-z, 0-9, -). Got: $NAME"
  exit 1
fi

KEBAB="$NAME"
SNAKE=$(echo "$NAME" | tr '-' '_')
KEBAB_CORE="${KEBAB}-core"
SNAKE_CORE="${SNAKE}_core"

echo "Will replace:"
echo "  rustai-core  →  $KEBAB_CORE (crate name)"
echo "  rustai_core  →  $SNAKE_CORE (Rust ident)"
echo "  rustai       →  $KEBAB      (crate name)"
echo "  rustai_      →  ${SNAKE}_   (Rust ident prefix, if any)"
echo ""

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# 치환 대상 파일: Cargo.toml, *.rs, *.ncl, *.sh, *.md
FILES=$(find . -type f \
  \( -name "Cargo.toml" -o -name "*.rs" -o -name "*.ncl" -o -name "*.sh" -o -name "*.md" \) \
  -not -path "./target/*" \
  -not -path "./.git/*" \
  -not -path "./.claude/*")

# 순서 중요: 긴 패턴 먼저 (rustai-core 전에 rustai를 바꾸면 rustai-core가 꼬임)
PATTERNS=(
  "s|rustai-core|$KEBAB_CORE|g"
  "s|rustai_core|$SNAKE_CORE|g"
  "s|rustai|$KEBAB|g"
)

if [ "$APPLY" = "--apply" ]; then
  echo "Applying changes…"
  for f in $FILES; do
    for p in "${PATTERNS[@]}"; do
      sed -i.bak "$p" "$f"
    done
    rm -f "$f.bak"
  done
  echo "Done. Run: cargo check --workspace"
else
  echo "DRY RUN — files that would change:"
  for f in $FILES; do
    if grep -qE "rustai(-core|_core)?" "$f" 2>/dev/null; then
      echo "  $f"
    fi
  done
  echo ""
  echo "Re-run with --apply to execute."
fi
