#!/usr/bin/env bash
# Ubuntu 22.04 LTS: use apt for available libraries; build newer tools locally.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/install-common.sh"
et_parse "$@"
et_platform ubuntu 22.04
et_system apt-get update
et_system apt-get install -y --no-install-recommends \
  build-essential autoconf automake libtool libtool-bin pkg-config cmake ninja-build flex bison \
  git curl ca-certificates gnupg unzip zip texinfo python3 python3-venv python3-dev \
  libgtk-3-dev libgnutls28-dev libjansson-dev libsqlite3-dev libgccjit-11-dev \
  libncurses-dev libharfbuzz-dev libotf-dev libpng-dev libjpeg-dev libgif-dev \
  libtiff-dev librsvg2-dev libwebp-dev libxml2-dev zlib1g-dev libgmp-dev \
  libssl-dev libvterm-dev libglib2.0-dev libgmime-3.0-dev libxapian-dev \
  clang clangd clang-format maven libnss3 libxss1 libasound2 libgbm1 \
  ripgrep fd-find aspell aspell-en aspell-ar hunspell-en-us \
  poppler-utils ghostscript pandoc texlive-latex-extra texlive-xetex \
  texlive-fonts-recommended texlive-bibtex-extra biber latexmk hugo maildir-utils mu4e isync msmtp \
  fonts-noto-core \
  openssh-client rsync xdg-utils fontconfig ruby sqlite3 postgresql-client \
  default-mysql-client shellcheck
et_finish ubuntu
