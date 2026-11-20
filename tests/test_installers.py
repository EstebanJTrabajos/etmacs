"""Offline tests: never install packages, run sudo, or start an AI service."""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import types
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install-dependencies.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="etmacs-install-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        args = types.SimpleNamespace(prefix=str(self.path / "prefix"), root=str(ROOT),
                                     distro="ubuntu", check=False, skip_tests=True)
        self.installer = MODULE.Installer(args)
        (self.installer.prefix / "bin").mkdir(parents=True)

    def test_checksums_reject_corruption(self):
        self.installer.request = lambda _: io.BytesIO(b"payload")
        digest = hashlib.sha256(b"payload").hexdigest()
        archive = self.installer.download("https://example.invalid/file", "archive", digest)
        self.assertEqual(archive.read_bytes(), b"payload")
        archive.write_bytes(b"corrupt")
        with self.assertRaisesRegex(RuntimeError, "SHA256"):
            self.installer.download("https://example.invalid/file", "archive", digest)

    def test_archive_paths_cannot_escape(self):
        archive = self.path / "bad.tar"
        with tarfile.open(archive, "w") as handle:
            entry = tarfile.TarInfo("../../outside")
            entry.size = 1
            handle.addfile(entry, io.BytesIO(b"x"))
        with self.assertRaisesRegex(RuntimeError, "Unsafe"):
            self.installer.extract(archive, self.path / "extract")

    def test_archive_symlinks_cannot_escape(self):
        archive = self.path / "bad-link.tar"
        with tarfile.open(archive, "w") as handle:
            entry = tarfile.TarInfo("symlink")
            entry.type = tarfile.SYMTYPE
            entry.linkname = "/etc"
            handle.addfile(entry)
        with self.assertRaisesRegex(RuntimeError, "Unsafe"):
            self.installer.extract(archive, self.path / "extract")

    def test_unmanaged_binary_is_not_overwritten(self):
        target = self.installer.prefix / "bin/tool"
        target.write_text("keep me")
        with self.assertRaisesRegex(RuntimeError, "unmanaged"):
            self.installer.link("/other/tool", "tool")
        with self.assertRaisesRegex(RuntimeError, "unmanaged"):
            self.installer.wrapper("tool", "exit 0")
        self.assertEqual(target.read_text(), "keep me")

    def test_both_dry_runs_are_non_destructive(self):
        for distro in ("ubuntu", "arch"):
            prefix = self.path / distro
            result = subprocess.run([str(ROOT / f"install-{distro}.sh"), "--dry-run",
                                     "--prefix", str(prefix)], check=True,
                                    text=True, capture_output=True)
            self.assertIn("31.1", result.stdout)
            self.assertIn("vterm", result.stdout)
            self.assertFalse(prefix.exists())

    def test_missing_emacs_builds_31_1_with_required_features(self):
        checks = iter((False, True))
        self.installer.emacs_ready = lambda: next(checks)
        pkgconfig = self.installer.prefix / "lib/pkgconfig"
        pkgconfig.mkdir(parents=True)
        (pkgconfig / "tree-sitter.pc").touch()
        sources = []
        self.installer.gnu_source = lambda project, version: (
            sources.append((project, version)) or self.path)
        commands = []
        self.installer.run = lambda *args, **kwargs: commands.append(args)
        self.installer.emacs_install()
        self.assertEqual(sources, [("emacs", "31.1")])
        configure = commands[0]
        for option in ("--with-modules", "--with-tree-sitter", "--with-sqlite3"):
            self.assertIn(option, configure)
        self.assertEqual(self.installer.emacs, str(self.installer.prefix / "bin/emacs"))

    def test_vterm_is_built_during_installation(self):
        self.installer.root = self.path / "checkout"
        self.installer.root.mkdir()
        commands = []
        self.installer.run = lambda *args, **kwargs: commands.append(args)
        self.installer.configure_emacs()
        expression = commands[-1][-1]
        self.assertIn("(et/install-vterm)", expression)
        self.assertIn("(et/treesit-install-grammars)", expression)
        settings = json.loads((self.installer.root / ".local/dependencies.json").read_text())
        self.assertEqual(settings["prefix"], str(self.installer.prefix))

    def fake_opencode(self):
        """Simulate service configuration without starting a real service."""
        fake = self.path / "opencode"
        fake.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if args == ["--version"]:
    print("2.2.3")
    sys.exit()
directory = Path(os.environ["XDG_CONFIG_HOME"]) / "opencode"
with (directory / "calls.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\\n")
file = directory / "service.json"
config = json.loads(file.read_text()) if file.exists() else {}
if args == ["service", "get", "port"]:
    print(config.get("port", ""))
elif args[:3] == ["service", "set", "port"]:
    config["port"] = int(args[3])
    file.write_text(json.dumps(config))
else:
    print(os.environ["XDG_STATE_HOME"])
    print(os.environ.get("OPENCODE_CONFIG_CONTENT", "unset"))
''')
        fake.chmod(0o755)
        return fake

    def test_work_wrapper_isolated_policy_without_ai_requests(self):
        root = self.path / "work"
        fake = self.fake_opencode()
        env = dict(os.environ, ETMACS_WORK_ROOT=str(root), ETMACS_OPENCODE=str(fake),
                   OPENCODE_CONFIG_CONTENT='{"model":"deepseek/deepseek-chat"}')
        result = subprocess.run([str(ROOT / "scripts/opencode-work"), "models"],
                                env=env, check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout.splitlines(), [str(root / "state"), "unset"])
        config = json.loads((root / "config/opencode/opencode.json").read_text())
        policy = config["policies"]
        for provider in ("anthropic", "deepseek", "openrouter", "amazon-bedrock", "opencode"):
            decision = None
            for rule in policy:
                if rule["action"] == "provider.use" and rule["resource"] in ("*", provider):
                    decision = rule["effect"]
            self.assertEqual(decision, "deny")
        self.assertEqual(policy[1]["resource"], "openai")
        self.assertEqual(policy[1]["effect"], "allow")

    def test_work_wrapper_initializes_separate_port_only_once(self):
        root = self.path / "work"
        fake = self.fake_opencode()
        env = dict(os.environ, ETMACS_WORK_ROOT=str(root), ETMACS_OPENCODE=str(fake))
        for _ in range(2):
            subprocess.run([str(ROOT / "scripts/opencode-work"), "service", "start"],
                           env=env, check=True, text=True, capture_output=True)
        directory = root / "config/opencode"
        self.assertEqual(json.loads((directory / "service.json").read_text())["port"],
                         49375)
        calls = [json.loads(line) for line in (directory / "calls.jsonl").read_text().splitlines()]
        self.assertEqual(calls, [["service", "get", "port"],
                                 ["service", "set", "port", "49375"],
                                 ["service", "start"],
                                 ["service", "get", "port"],
                                 ["service", "start"]])

    def test_work_wrapper_preserves_custom_service_configuration(self):
        root = self.path / "work"
        directory = root / "config/opencode"
        directory.mkdir(parents=True)
        config = {"port": 50400, "hostname": "127.0.0.1"}
        (directory / "service.json").write_text(json.dumps(config))
        fake = self.fake_opencode()
        subprocess.run([str(ROOT / "scripts/opencode-work"), "models"],
                       env=dict(os.environ, ETMACS_WORK_ROOT=str(root),
                                ETMACS_OPENCODE=str(fake)),
                       check=True, text=True, capture_output=True)
        self.assertEqual(json.loads((directory / "service.json").read_text()), config)
        calls = [json.loads(line) for line in (directory / "calls.jsonl").read_text().splitlines()]
        self.assertEqual(calls, [["service", "get", "port"], ["models"]])

    def test_work_wrapper_refuses_legacy_opencode(self):
        fake = self.path / "opencode"
        fake.write_text("#!/bin/sh\necho 1.19.5\n")
        fake.chmod(0o755)
        root = self.path / "work"
        result = subprocess.run([str(ROOT / "scripts/opencode-work"), "models"],
                                env=dict(os.environ, ETMACS_WORK_ROOT=str(root),
                                         ETMACS_OPENCODE=str(fake)),
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("2.2.3", result.stderr)
        self.assertFalse(root.exists())


if __name__ == "__main__":
    unittest.main()
