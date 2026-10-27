#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EMACS="${EMACS:-emacs}"
INSTALL_FONTS=0
SKIP_TESTS=0
SKIP_PARINFER=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Tangle config.org, install the Emacs packages needed by this configuration,
verify the installation, and run the ERT test suite.

Options:
  --fonts          Also install the Nerd Fonts glyphs used by doom-modeline.
  --skip-parinfer  Do not download the parinfer-rust native library.
  --skip-tests     Install only; do not run the ERT suite.
  -h, --help       Show this message.

Environment:
  EMACS            Emacs executable to use (default: emacs).

The script never installs system packages, language servers, debug adapters,
tree-sitter grammars, or Python/Node tooling. It only installs Emacs packages
into .local/elpa and the optional native parinfer-rust library into .local/.
EOF
}

step() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fonts)
      INSTALL_FONTS=1
      ;;
    --skip-parinfer)
      SKIP_PARINFER=1
      ;;
    --skip-tests)
      SKIP_TESTS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$ROOT"

step "Checking prerequisites"

if ! command -v "$EMACS" >/dev/null 2>&1; then
  printf 'Emacs executable not found: %s\n' "$EMACS" >&2
  exit 1
fi

if ! "$EMACS" -Q --batch --eval '(progn
  (when (version< emacs-version "31.1")
    (error "Etmacs requires Emacs 31.1 or newer"))
  (unless (and (fboundp (quote sqlite-available-p))
               (sqlite-available-p))
    (error "Etmacs requires Emacs built with SQLite support")))'; then
  printf 'Emacs prerequisite check failed.\n' >&2
  exit 1
fi

for command in git curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

for command in rg opencode; do
  if ! command -v "$command" >/dev/null 2>&1; then
    warn "$command is not on PATH; related features will be unavailable."
  fi
done

step "Tangling config.org"
"$EMACS" -Q --batch --load "$ROOT/scripts/tangle.el"

step "Installing Emacs packages into .local/elpa"
"$EMACS" -Q --batch --load "$ROOT/init.el" --funcall et/install-packages

step "Verifying package installation"
"$EMACS" -Q --batch --load "$ROOT/init.el" --eval '(let ((missing (et/missing-packages)))
  (when missing
    (error "Missing packages after install: %S" missing)))'

if [ "$SKIP_PARINFER" -eq 0 ]; then
  step "Installing parinfer-rust native library"
  "$EMACS" -Q --batch --load "$ROOT/init.el" --eval '(progn
    (require (quote parinfer-rust-mode))
    (unless (file-exists-p parinfer-rust-library)
      (et/install-parinfer-rust)))'
fi

if [ "$INSTALL_FONTS" -eq 1 ]; then
  step "Installing Nerd Fonts"
  font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
  if [ -f "$font_dir/NFM.ttf" ] || [ -f "$HOME/Library/Fonts/NFM.ttf" ]; then
    printf 'Nerd Fonts already present; skipping download.\n'
  else
    "$EMACS" -Q --batch --load "$ROOT/init.el" --eval '(progn
      (require (quote nerd-icons))
      (nerd-icons-install-fonts t))'
  fi
fi

if [ "$SKIP_TESTS" -eq 0 ]; then
  step "Running ERT test suite"
  "$EMACS" -Q --batch --load "$ROOT/tests/et-core-tests.el" \
    --funcall ert-run-tests-batch-and-exit
fi

step "Installation complete"
cat <<EOF
Etmacs is ready.

Start it with:
  emacs --init-directory "$ROOT" --debug-init

For terminal Emacs:
  emacs -nw --init-directory "$ROOT" --debug-init

Optional Nerd Fonts installation:
  ./install.sh --fonts

Generated runtime state lives under:
  "$ROOT/.local"
EOF
