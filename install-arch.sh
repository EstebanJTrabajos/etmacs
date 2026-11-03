#!/usr/bin/env bash
# Arch: official packages first; no unattended AUR helper or root builds.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/install-common.sh"
et_parse "$@"
et_platform arch
# A full upgrade avoids unsupported partial upgrades on rolling-release Arch.
et_system pacman -Syu --needed --noconfirm \
  base-devel git curl ca-certificates gnupg unzip zip cmake ninja pkgconf \
  emacs tree-sitter libvterm gtk3 gnutls jansson sqlite libgccjit \
  harfbuzz libotf libpng libjpeg-turbo giflib librsvg libwebp libxml2 \
  ncurses gmp openssl glib2 gmime3 xapian-core \
  python python-pip python-virtualenv nodejs npm go jdk-openjdk \
  clang gdb lldb maven chromium ripgrep fd aspell aspell-en aspell-ar hunspell-en_us \
  poppler ghostscript pandoc texlive-latexextra texlive-xetex texlive-binextra \
  texlive-fontsrecommended texlive-bibtexextra biber hugo isync msmtp \
  openssh rsync xdg-utils fontconfig noto-fonts ruby postgresql-libs mariadb-clients \
  docker docker-compose shellcheck
et_finish arch
