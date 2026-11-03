#!/usr/bin/env python3
"""Shared, unprivileged toolchain installer. System packages live in the entrypoints.

Release archives are checked against upstream digests/signatures. Git sources
and package-manager resolved versions are recorded in install-manifest.json.
No curl-to-shell installers, root builds, AUR helpers, or daemon activation.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile


TOOLS = (
    "git", "curl", "rg", "fd", "cmake", "make", "cc", "clangd", "clang-format",
    "gdb", "python", "ipython3", "pytest", "ruff", "basedpyright-langserver",
    "node", "npm", "go", "typescript-language-server", "tsc", "ts-node", "tsx",
    "yaml-language-server", "docker-langserver", "bash-language-server",
    "vscode-json-language-server", "vscode-html-language-server",
    "vscode-css-language-server", "prettier", "jest", "vitest", "yls", "sqls",
    "java", "javac", "jdtls", "mvn", "docker", "opencode", "opencode2",
    "pandoc", "pdflatex", "xelatex", "latexmk", "biber", "hugo", "pdftoppm",
    "gs", "mu", "mbsync", "msmtp", "ssh", "rsync", "sqlite3", "psql", "mysql",
    "ruby", "aspell", "xdg-open", "fc-cache", "chromium",
)
NPM_PACKAGES = (
    "typescript", "typescript-language-server", "ts-node", "tsx",
    "yaml-language-server", "dockerfile-language-server-nodejs",
    "bash-language-server", "vscode-langservers-extracted", "prettier",
    "jest", "vitest", "@opencode/cli@>=2.2.3",
)
PYTHON_PACKAGES = (
    "basedpyright", "ruff", "debugpy", "ipython", "pytest", "yls",
    "meson", "ninja", "yara-python",
)


class Installer:
    def __init__(self, args):
        self.args = args
        self.prefix = Path(args.prefix).expanduser().resolve()
        self.root = Path(args.root).resolve()
        self.arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
        if not self.arch:
            raise RuntimeError("Supported architectures: x86_64 and aarch64")
        self.env = dict(os.environ)
        self.env["PATH"] = f"{self.prefix}/bin:{self.env.get('PATH', '')}"
        self.env["ETMACS_PREFIX"] = str(self.prefix)
        self.env["PKG_CONFIG_PATH"] = f"{self.prefix}/lib/pkgconfig:" + self.env.get("PKG_CONFIG_PATH", "")
        self.env["LD_LIBRARY_PATH"] = f"{self.prefix}/lib:" + self.env.get("LD_LIBRARY_PATH", "")
        self.env["CPPFLAGS"] = f"-I{self.prefix}/include " + self.env.get("CPPFLAGS", "")
        self.env["LDFLAGS"] = f"-L{self.prefix}/lib -Wl,-rpath,{self.prefix}/lib " + self.env.get("LDFLAGS", "")
        self.env["GOPATH"] = str(self.prefix / "go")
        self.env["GOCACHE"] = str(self.prefix / "cache/go-build")
        self.env["GOBIN"] = str(self.prefix / "bin")
        self.env["npm_config_cache"] = str(self.prefix / "cache/npm")
        self.env["PIP_CACHE_DIR"] = str(self.prefix / "cache/pip")
        self.env["XDG_CACHE_HOME"] = str(self.prefix / "cache")
        self.env["PLAYWRIGHT_BROWSERS_PATH"] = str(self.prefix / "share/browsers")
        self.manifest_file = self.prefix / "install-manifest.json"
        self.manifest = json.loads(self.manifest_file.read_text()) if self.manifest_file.exists() else {}
        self.emacs = self.env.get("EMACS", "emacs")

    def run(self, *command, cwd=None, capture=False):
        print("+", shlex.join(map(str, command)), flush=True)
        result = subprocess.run(list(map(str, command)), cwd=cwd, env=self.env,
                                check=True, text=True,
                                stdout=subprocess.PIPE if capture else None)
        return result.stdout.strip() if capture else None

    def available(self, command):
        return shutil.which(command, path=self.env["PATH"])

    def version_ok(self, command, minimum, flag="--version"):
        if not self.available(command):
            return False
        try:
            output = self.run(command, flag, capture=True)
            version = re.search(r"\d+(?:\.\d+)+", output)
            return bool(version and tuple(map(int, version[0].split("."))) >= minimum)
        except subprocess.CalledProcessError:
            return False

    def request(self, url):
        headers = {"User-Agent": "etmacs-dependency-installer"}
        if url.startswith("https://api.github.com/") and self.env.get("GITHUB_TOKEN"):
            headers["Authorization"] = "Bearer " + self.env["GITHUB_TOKEN"]
        return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120)

    def json(self, url):
        with self.request(url) as response:
            return json.load(response)

    def text(self, url):
        with self.request(url) as response:
            return response.read().decode().strip()

    def download(self, url, name, digest=None):
        target = self.prefix / "cache/downloads" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            temporary = target.with_suffix(target.suffix + ".partial")
            with self.request(url) as source, temporary.open("wb") as dest:
                shutil.copyfileobj(source, dest)
            temporary.replace(target)
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest and actual != digest.removeprefix("sha256:").lower():
            target.unlink()
            raise RuntimeError(f"SHA256 mismatch: {url}")
        self.manifest[name] = {"url": url, "sha256": actual}
        self.save_manifest()
        return target

    def save_manifest(self):
        self.manifest_file.parent.mkdir(parents=True, exist_ok=True)
        temp = self.manifest_file.with_suffix(".tmp")
        temp.write_text(json.dumps(self.manifest, indent=2) + "\n")
        temp.replace(self.manifest_file)

    def extract(self, archive, destination):
        destination.mkdir(parents=True, exist_ok=True)
        base = destination.resolve()

        def check(name):
            path = (base / name).resolve()
            if path != base and base not in path.parents:
                raise RuntimeError(f"Unsafe archive path: {name}")

        if zipfile.is_zipfile(archive):
            with zipfile.ZipFile(archive) as handle:
                for entry in handle.infolist():
                    check(entry.filename)
                handle.extractall(base)
        else:
            with tarfile.open(archive) as handle:
                for entry in handle.getmembers():
                    check(entry.name)
                    if entry.isdev() or entry.isfifo():
                        raise RuntimeError("Refusing archive special file")
                    if entry.issym():
                        check(str(Path(entry.name).parent / entry.linkname))
                    elif entry.islnk():
                        check(entry.linkname)
                # Python 3.10 lacks extraction filters. All members/links were
                # validated above; use the standard data filter when available.
                if hasattr(tarfile, "data_filter"):
                    handle.extractall(base, filter="data")
                else:
                    handle.extractall(base)
        return destination

    def link(self, target, name):
        link = self.prefix / "bin" / name
        link.parent.mkdir(parents=True, exist_ok=True)
        if link.is_symlink():
            previous = link.resolve()
            if previous == Path(target).resolve():
                return
            if self.prefix not in previous.parents:
                raise RuntimeError(f"Refusing to replace unmanaged symlink: {link}")
            link.unlink()
        elif link.exists():
            if link.resolve() == Path(target).resolve():
                return
            raise RuntimeError(f"Refusing to overwrite unmanaged executable: {link}")
        link.symlink_to(target)

    def wrapper(self, name, text):
        dest = self.prefix / "bin" / name
        if dest.exists() and not dest.is_symlink() and not dest.read_text().startswith("#!/bin/sh\n# Etmacs"):
            raise RuntimeError(f"Refusing to overwrite unmanaged executable: {dest}")
        if dest.is_symlink():
            raise RuntimeError(f"Refusing to replace unmanaged symlink: {dest}")
        dest.write_text("#!/bin/sh\n# Etmacs managed launcher\n" + text + "\n")
        dest.chmod(0o755)

    def github_archive(self, repo, pattern):
        release = self.json(f"https://api.github.com/repos/{repo}/releases/latest")
        asset = next((a for a in release["assets"] if re.fullmatch(pattern, a["name"])), None)
        if not asset or not asset.get("digest"):
            raise RuntimeError(f"No checksum-bearing release asset for {repo}: {pattern}")
        return self.download(asset["browser_download_url"], asset["name"], asset["digest"])

    def git_source(self, repo, ref, name):
        directory = Path(tempfile.mkdtemp(prefix=name + "-", dir=self.prefix / "build"))
        self.run("git", "clone", "--depth", "1", "--branch", ref, repo, directory)
        commit = self.run("git", "rev-parse", "HEAD", cwd=directory, capture=True)
        self.manifest[name] = {"repository": repo, "ref": ref, "commit": commit}
        self.save_manifest()
        return directory

    def gnu_source(self, project, version):
        name = f"{project}-{version}.tar.xz"
        base = f"https://ftp.gnu.org/gnu/{project}/"
        archive = self.download(base + name, name)
        signature = self.download(base + name + ".sig", name + ".sig")
        keyring = self.download("https://ftp.gnu.org/gnu/gnu-keyring.gpg", "gnu-keyring.gpg")
        self.run("gpgv", "--keyring", keyring, signature, archive)
        directory = Path(tempfile.mkdtemp(prefix=project + "-", dir=self.prefix / "build"))
        self.extract(archive, directory)
        return directory / f"{project}-{version}"

    def runtimes(self):
        if not self.version_ok("node", (24,)):
            release = next(r for r in self.json("https://nodejs.org/dist/index.json") if r["lts"])
            arch = "x64" if self.arch == "amd64" else self.arch
            name = f"node-{release['version']}-linux-{arch}.tar.xz"
            base = f"https://nodejs.org/dist/{release['version']}/"
            checksums = self.text(base + "SHASUMS256.txt").splitlines()
            digest = next(line.split()[0] for line in checksums if line.split()[-1] == name)
            directory = self.extract(self.download(base + name, name, digest), self.prefix / "node")
            home = directory / name.removesuffix(".tar.xz")
            for command in ("node", "npm", "npx", "corepack"):
                if (home / "bin" / command).exists():
                    self.link(home / "bin" / command, command)
        if not self.version_ok("go", (1, 24), "version"):
            release = next(r for r in self.json("https://go.dev/dl/?mode=json") if r["stable"])
            asset = next(a for a in release["files"] if a["os"] == "linux" and a["arch"] == self.arch and a["kind"] == "archive")
            home = self.prefix / "runtimes" / release["version"]
            self.extract(self.download("https://go.dev/dl/" + asset["filename"], asset["filename"], asset["sha256"]), home)
            self.link(home / "go/bin/go", "go")
        if not self.version_ok("javac", (25,)):
            arch = "x64" if self.arch == "amd64" else "aarch64"
            asset = self.json(f"https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture={arch}&image_type=jdk&os=linux")[0]["binary"]["package"]
            home = self.prefix / "runtimes/jdk25"
            self.extract(self.download(asset["link"], asset["name"], asset["checksum"]), home)
            jdk = next(home.glob("*/bin/javac")).parent.parent
            for executable in (jdk / "bin").iterdir():
                self.link(executable, executable.name)
            self.env["JAVA_HOME"] = str(jdk)
        if not self.available("fd") and self.available("fdfind"):
            self.link(self.available("fdfind"), "fd")

    def emacs_ready(self):
        if not self.available(self.emacs):
            return False
        code = """(progn
          (when (version< emacs-version "31.1") (error "Emacs too old"))
          (unless (and (fboundp 'module-load) module-file-suffix
                       (sqlite-available-p) (treesit-available-p))
            (error "Missing modules, SQLite or tree-sitter")))"""
        try:
            self.run(self.emacs, "-Q", "--batch", "--eval", code)
            return True
        except subprocess.CalledProcessError:
            return False

    def emacs_install(self):
        if self.emacs_ready():
            return
        if not (self.prefix / "lib/pkgconfig/tree-sitter.pc").exists():
            source = self.git_source("https://github.com/tree-sitter/tree-sitter", "v0.25.10", "tree-sitter")
            self.run("make", f"-j{os.cpu_count() or 2}", cwd=source)
            self.run("make", "install", f"PREFIX={self.prefix}", cwd=source)
        source = self.gnu_source("emacs", "31.1")
        self.run("./configure", f"--prefix={self.prefix}", "--with-x-toolkit=gtk3",
                 "--with-modules", "--with-tree-sitter", "--with-sqlite3",
                 "--with-native-compilation", cwd=source)
        self.run("make", f"-j{os.cpu_count() or 2}", cwd=source)
        self.run("make", "install", cwd=source)
        self.emacs = str(self.prefix / "bin/emacs")
        if not self.emacs_ready():
            raise RuntimeError("Built Emacs failed required-feature checks")

    def language_tools(self):
        python = self.prefix / "python-tools/bin/python"
        if not python.exists():
            self.run("python3", "-m", "venv", python.parent.parent)
        marker = self.prefix / "python-tools/.etmacs-complete"
        if not marker.exists() or not all((python.parent / name).exists()
                                         for name in ("ruff", "pytest", "yls", "basedpyright-langserver")):
            self.run(python, "-m", "pip", "install", "--upgrade", "pip")
            self.run(python, "-m", "pip", "install", *PYTHON_PACKAGES)
            marker.touch()
        for name in ("python", "python3", "ipython", "ipython3", "pytest", "ruff",
                     "basedpyright", "basedpyright-langserver", "yls", "meson", "ninja"):
            executable = python.parent / name
            if executable.exists():
                self.link(executable, name)
        self.manifest["python-packages"] = self.run(python, "-m", "pip", "freeze", capture=True).splitlines()
        marker = self.prefix / ".npm-tools-complete"
        if not marker.exists() or not all(self.available(name) for name in
                                         ("tsc", "ts-node", "tsx", "prettier", "jest", "vitest",
                                          "typescript-language-server", "yaml-language-server",
                                          "docker-langserver", "bash-language-server", "opencode")):
            self.run("npm", "install", "--global", "--prefix", self.prefix, *NPM_PACKAGES)
            marker.touch()
        self.manifest["npm-packages"] = json.loads(self.run("npm", "list", "--global", "--prefix", self.prefix, "--depth=0", "--json", capture=True))
        if not self.available("sqls"):
            self.run("go", "install", "github.com/sqls-server/sqls@latest")
        self.wrapper("opencode2",
                     f"export ETMACS_WORK_ROOT={shlex.quote(str(self.root / '.local/profiles/work/opencode'))}\n"
                     f"export ETMACS_PREFIX={shlex.quote(str(self.prefix))}\n"
                     f"exec {shlex.quote(str(self.root / 'scripts/opencode-work'))} \"$@\"")
        self.save_manifest()

    def debuggers(self):
        if not self.version_ok("gdb", (14, 1)):
            source = self.gnu_source("gdb", "16.3")
            self.run("./configure", f"--prefix={self.prefix}", "--with-python=python3", "--disable-werror", cwd=source)
            self.run("make", f"-j{os.cpu_count() or 2}", cwd=source)
            self.run("make", "install", cwd=source)
        js = self.prefix / "share/js-debug"
        if not (js / "dapDebugServer.js").exists():
            self.extract(self.github_archive("microsoft/vscode-js-debug", r"js-debug-dap-.*\.tar\.gz"), js.parent)
        jdtls = self.prefix / "share/jdtls"
        if not (jdtls / "plugins").is_dir():
            base = "https://download.eclipse.org/jdtls/snapshots/"
            name = self.text(base + "latest.txt")
            if not re.fullmatch(r"jdt-language-server-[\w.-]+\.tar\.gz", name):
                raise RuntimeError("Unexpected JDTLS release filename")
            digest = self.text(base + name + ".sha256").split()[0]
            self.extract(self.download(base + name, name, digest), jdtls)
        # Use the selected JDK, not an older java elsewhere on PATH.
        self.wrapper("jdtls", f"exec {shlex.quote(str(jdtls / 'bin/jdtls'))} \"$@\"")
        bundle = self.prefix / "share/java-debug/com.microsoft.java.debug.plugin.jar"
        if not bundle.exists():
            release = self.json("https://api.github.com/repos/microsoft/java-debug/releases/latest")
            source = self.git_source("https://github.com/microsoft/java-debug", release["tag_name"], "java-debug")
            self.run("mvn", "-B", f"-Dmaven.repo.local={self.prefix}/cache/maven",
                     "-DskipTests", "package", cwd=source)
            artifact = next(source.glob("com.microsoft.java.debug.plugin/target/com.microsoft.java.debug.plugin-*.jar"))
            bundle.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(artifact, bundle)

    def extras(self):
        try:
            self.run("pkg-config", "--atleast-version=0.3.3", "vterm")
        except subprocess.CalledProcessError:
            source = self.git_source("https://github.com/neovim/libvterm", "v0.3.3", "libvterm")
            self.run("make", f"-j{os.cpu_count() or 2}", cwd=source)
            self.run("make", "install", f"PREFIX={self.prefix}", cwd=source)
        if not self.available("mu"):
            release = self.json("https://api.github.com/repos/djcb/mu/releases/latest")
            source = self.git_source("https://github.com/djcb/mu", release["tag_name"], "mu")
            self.run("meson", "setup", "build", f"--prefix={self.prefix}", "-Dguile=disabled", cwd=source)
            self.run("ninja", "-C", "build", cwd=source)
            self.run("ninja", "-C", "build", "install", cwd=source)
        if not self.available("docker"):
            # Docker's static distribution includes the engine; do not start it.
            arch = "x86_64" if self.arch == "amd64" else "aarch64"
            base = f"https://download.docker.com/linux/static/stable/{arch}/"
            names = re.findall(r'docker-(\d+\.\d+\.\d+)\.tgz', self.text(base))
            version = max(names, key=lambda x: tuple(map(int, x.split("."))))
            name = f"docker-{version}.tgz"
            # Docker does not publish checksums for these archives. Download
            # via its authenticated TLS endpoint and record the content hash.
            dest = self.extract(self.download(base + name, name), self.prefix / "runtimes/docker")
            for executable in (dest / "docker").iterdir():
                self.link(executable, executable.name)
        try:
            self.run("docker", "compose", "version", capture=True)
        except subprocess.CalledProcessError:
            arch = "x86_64" if self.arch == "amd64" else "aarch64"
            asset = self.github_archive("docker/compose", f"docker-compose-linux-{arch}")
            target = self.prefix / "lib/docker/cli-plugins/docker-compose"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(asset, target)
            target.chmod(0o755)
            # Expose the locally installed plugin without rewriting credentials.
            config = Path(self.env.get("DOCKER_CONFIG", Path.home() / ".docker"))
            plugin = config / "cli-plugins/docker-compose"
            plugin.parent.mkdir(parents=True, exist_ok=True)
            if plugin.exists() or plugin.is_symlink():
                raise RuntimeError(f"Existing Compose plugin failed its version check: {plugin}")
            plugin.symlink_to(target)
        if not self.available("chromium"):
            self.run("npm", "install", "--prefix", self.prefix / "browser-tools", "playwright")
            self.run(self.prefix / "browser-tools/node_modules/.bin/playwright", "install", "chromium")
            browsers = list((self.prefix / "share/browsers").glob("chromium-*/chrome-linux*/chrome"))
            if not browsers:
                raise RuntimeError("Chromium download did not contain a browser executable")
            self.wrapper("chromium", f"exec {shlex.quote(str(sorted(browsers)[-1]))} \"$@\"")
        fonts = self.prefix / "share/fonts"
        if not list(fonts.glob("*.ttf")):
            self.extract(self.github_archive("ryanoasis/nerd-fonts", r"NerdFontsSymbolsOnly\.zip"), fonts)
        font_link = Path.home() / ".local/share/fonts/etmacs"
        if not font_link.exists():
            font_link.parent.mkdir(parents=True, exist_ok=True)
            font_link.symlink_to(fonts)
        self.run("fc-cache", "-f", fonts)

    def configure_emacs(self):
        settings = self.root / ".local/dependencies.json"
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text(json.dumps({"prefix": str(self.prefix)}, indent=2) + "\n")
        self.run(self.emacs, "-Q", "--batch", "--load", self.root / "scripts/tangle.el")
        self.run(self.emacs, "-Q", "--batch", "--load", self.root / "init.el",
                 "--funcall", "et/install-packages")
        self.run(self.emacs, "-Q", "--batch", "--load", self.root / "init.el", "--eval",
                 """(progn
                   (when (et/missing-packages) (error "Missing Emacs packages"))
                   (et/install-vterm)
                   (et/treesit-install-grammars)
                   (dolist (grammar et/treesit-grammars)
                     (unless (et/tree-sitter-ready-p grammar)
                       (error "Grammar unavailable: %s" grammar)))
                   (require 'parinfer-rust-mode)
                   (unless (file-exists-p parinfer-rust-library) (et/install-parinfer-rust))
                   (unless (file-exists-p parinfer-rust-library)
                     (error "Parinfer library unavailable")))""")
        if not self.args.skip_tests:
            self.run(self.emacs, "-Q", "--batch", "--load", self.root / "tests/et-core-tests.el",
                     "--funcall", "ert-run-tests-batch-and-exit")

    def audit(self):
        missing = [name for name in TOOLS if not self.available(name)]
        for name in TOOLS:
            print(f"{'MISSING' if name in missing else 'OK':7} {name}: {self.available(name) or '-'}")
        if not self.emacs_ready():
            missing.append("Emacs >=31.1 with modules, SQLite and tree-sitter")
        if not self.version_ok("opencode", (2, 2, 3)):
            missing.append("OpenCode >=2.2.3 (required for work policies)")
        if not self.version_ok("node", (24,)):
            missing.append("Node >=24 (required by the installed language tools)")
        if not self.version_ok("gdb", (14, 1)):
            missing.append("GDB >=14.1 (required by Dape's DAP adapter)")
        for name, path in (("js-debug", "share/js-debug/dapDebugServer.js"),
                           ("java-debug", "share/java-debug/com.microsoft.java.debug.plugin.jar"),
                           ("JDTLS", "share/jdtls/plugins")):
            if not (self.prefix / path).exists():
                missing.append(name)
        try:
            self.run("docker", "compose", "version", capture=True)
            self.run("python", "-c", "import debugpy.adapter, pytest, yara")
        except (subprocess.CalledProcessError, FileNotFoundError):
            missing.append("Docker Compose or Python tool modules")
        if missing:
            raise RuntimeError("Incomplete installation: " + ", ".join(missing))

    def install(self):
        if self.args.check:
            self.audit()
            # Keep histories, profile selections, and package state untouched.
            with tempfile.TemporaryDirectory(prefix="etmacs-check-") as temporary:
                state = json.dumps(temporary + "/")
                root = json.dumps(str(self.root / "init.el"))
                grammars = json.dumps(str(self.root / ".local/tree-sitter"))
                parinfer = json.dumps(str(self.root / ".local/parinfer-rust"))
                self.run(self.emacs, "-Q", "--batch", "--eval", f"""(progn
                  (require 'cl-lib)
                  (advice-add 'require :before
                    (lambda (feature &rest _)
                      (when (memq feature '(et-profile et-core))
                        (setq et/state-directory {state}))))
                  (load {root} nil t)
                  (when (et/missing-packages) (error "Missing Emacs packages"))
                  (unless (et/vterm-available-p) (error "Missing vterm module"))
                  (require 'vterm)
                  (require 'parinfer-rust-mode)
                  (unless (file-exists-p (expand-file-name parinfer-rust--lib-name {parinfer}))
                    (error "Missing Parinfer"))
                  (setq treesit-extra-load-path (list {grammars}))
                  (dolist (g et/treesit-grammars)
                    (unless (et/tree-sitter-ready-p g) (error "Missing grammar: %s" g))))""")
            return
        for directory in ("bin", "build", "cache", "share"):
            (self.prefix / directory).mkdir(parents=True, exist_ok=True)
        self.runtimes()
        self.language_tools()
        self.emacs_install()
        self.debuggers()
        self.extras()
        self.audit()
        self.configure_emacs()
        self.save_manifest()
        print(f"Ready: {self.emacs} --init-directory {shlex.quote(str(self.root))}")
        print("Work AI uses direct OpenAI only; sign in separately with opencode2.")
        print("Project environments still need their own dependencies. Docker is not started.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--distro", choices=("ubuntu", "arch"), required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-tests", action="store_true")
    args = parser.parse_args()
    try:
        Installer(args).install()
    except (RuntimeError, subprocess.CalledProcessError, OSError, StopIteration) as error:
        parser.exit(1, f"Installation failed: {error}\nFix the reported dependency and rerun the same installer.\n")


if __name__ == "__main__":
    main()
