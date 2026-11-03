# Shared implementation for the two distribution entrypoints. Not executable.
PREFIX="${ETMACS_PREFIX:-$HOME/.config/emacs/.local}"
SKIP_SYSTEM=0
SKIP_TESTS=0
DRY_RUN=0
CHECK=0

et_usage() {
  cat <<'EOF'
Usage: ./install-{ubuntu,arch}.sh [options]

Install the complete Etmacs toolchain, Emacs packages, native modules,
language servers, debug adapters, grammars, fonts and document-export tools.
Ubuntu targets 22.04 LTS and builds Emacs 31.1 when no suitable Emacs exists.

  --prefix DIR    Local dependency prefix (default ~/.config/emacs/.local)
  --skip-system   Do not use sudo/apt/pacman; prerequisites must already exist
  --skip-tests    Skip ERT after installation (verification still runs)
  --dry-run       Print the plan without downloads, writes, or sudo
  --check         Audit the installed tools without changing anything
  -h, --help      Show this help

EMACS may select an existing compatible Emacs. ETMACS_PREFIX selects the prefix.
APT/pacman operations require sudo; downloads and builds run as the current user.
No accounts, credentials, project virtualenvs, or Docker services are configured.
EOF
}

et_parse() {
  while (($#)); do
    case "$1" in
      --prefix) [[ $# -gt 1 && -n "$2" ]] || { et_usage >&2; exit 2; }
        PREFIX="$2"; shift ;;
      --skip-system) SKIP_SYSTEM=1 ;;
      --skip-tests) SKIP_TESTS=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --check) CHECK=1; SKIP_SYSTEM=1 ;;
      -h|--help) et_usage; exit 0 ;;
      *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
  done
  [[ "$PREFIX" = /* ]] || { printf 'Prefix must be absolute\n' >&2; exit 2; }
  [[ $EUID -ne 0 || $DRY_RUN -eq 1 || $CHECK -eq 1 ]] || {
    printf 'Run as your ordinary user, not root; sudo is used only for system packages.\n' >&2
    exit 1
  }
}

et_platform() {
  [[ $DRY_RUN -eq 1 || $CHECK -eq 1 ]] && return 0
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "$ID" = "$1" && ( $# -eq 1 || "$VERSION_ID" = "$2" ) ]] || {
    printf 'This entrypoint targets %s %s, not %s %s\n' "$1" "${2:-}" "$ID" "${VERSION_ID:-}" >&2
    exit 1
  }
}

et_system() {
  [[ $CHECK -eq 1 ]] && return 0
  [[ $SKIP_SYSTEM -eq 1 ]] && return 0
  if [[ $DRY_RUN -eq 1 ]]; then
    printf 'System prerequisites: '; printf '%q ' sudo "$@"; printf '\n'
  elif [[ $SKIP_SYSTEM -eq 0 ]]; then
    sudo "$@"
  fi
}

et_finish() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '%s\n' \
      "Local prefix: $PREFIX" \
      'Verify Emacs >=31.1 with SQLite, tree-sitter and modules; build 31.1 if needed.' \
      'Install missing/newer runtimes, LSPs, formatters, adapters, export/mail tools and fonts.' \
      'Tangle; install Emacs packages; compile and load vterm; install all grammars and Parinfer.' \
      'Verify every dependency and run ERT (unless --skip-tests).'
    return
  fi
  export ETMACS_PREFIX="$PREFIX"
  export PATH="$PREFIX/bin:$PATH"
  local args=(--prefix "$PREFIX" --root "$ROOT" --distro "$1")
  [[ $CHECK -eq 0 ]] || args+=(--check)
  [[ $SKIP_TESTS -eq 0 ]] || args+=(--skip-tests)
  python3 "$ROOT/scripts/install-dependencies.py" "${args[@]}"
}
