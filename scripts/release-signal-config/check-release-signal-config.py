#!/usr/bin/env python3
"""
Validates release-signal-config.json and audits rule consistency.

Repo-aware Python 3.11+ port of scripts/release-signal-config/check-release-signal-config.ps1.

This script can live either inside the repository or inside an external Codex skill/helper
folder. It resolves the repository root first, then defaults config paths to:

  <repo>/scripts/release-signal-config.json
  <repo>/scripts/release-signal-config.schema.json

It intentionally contains no project-specific release classification policy.
"""

from __future__ import annotations

import argparse
import importlib
import importlib.util
import json
import shlex
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Any, Iterable

pass_count = 0
fail_count = 0
warn_count = 0
repo_root_resolved = ""
verbose_mode = False
jsonschema_available = False
failure_messages: list[str] = []
warning_messages: list[str] = []

JSONSCHEMA_IMPORT_NAME = "jsonschema"
JSONSCHEMA_PIP_PACKAGE = "jsonschema"


def _configure_stdio() -> None:
    """Best effort UTF-8 output, mostly useful on older Windows terminals."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        except Exception:
            pass


def write_verbose(message: str = "") -> None:
    if verbose_mode:
        print(message)


def write_verbose_section(title: str) -> None:
    write_verbose("")
    write_verbose(title)
    write_verbose("")


def is_path_fully_qualified(path: str) -> bool:
    return Path(path).is_absolute() or PureWindowsPath(path).is_absolute()


def resolve_full_path_from_base(base_path: str, path: str) -> str:
    if is_path_fully_qualified(path):
        return path
    return str(Path(base_path) / path)


def run_process(args: list[str], cwd: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def resolve_repository_root(requested_repo_root: str = "") -> str:
    if requested_repo_root.strip():
        return str(Path(requested_repo_root).resolve(strict=True))

    cwd = Path.cwd()

    try:
        result = run_process(["git", "-C", str(cwd), "rev-parse", "--show-toplevel"])
        git_root = result.stdout.strip()
        if result.returncode == 0 and git_root:
            return git_root
    except Exception:
        # Fall through to upward search.
        pass

    current = cwd.resolve()
    while True:
        config_candidate = current / "scripts" / "release-signal-config.json"
        schema_candidate = current / "scripts" / "release-signal-config.schema.json"
        if config_candidate.exists() and schema_candidate.exists():
            return str(current)

        parent = current.parent
        if parent == current:
            break
        current = parent

    raise RuntimeError(
        f"Could not resolve repository root from current directory: {cwd}. "
        "Run from inside the repo or pass -RepoRoot."
    )


def resolve_repo_path(path: str) -> str:
    if is_path_fully_qualified(path):
        return path
    return str(Path(repo_root_resolved) / path)


def add_pass(message: str) -> None:
    global pass_count
    pass_count += 1
    write_verbose(f"  ✓ {message}")


def add_fail(message: str) -> None:
    global fail_count
    fail_count += 1
    failure_messages.append(message)
    write_verbose(f"  ✗ {message}")


def add_warn(message: str) -> None:
    global warn_count
    warn_count += 1
    warning_messages.append(message)
    write_verbose(f"  ⚠ {message}")


def test_check(name: str, test: Any) -> bool:
    try:
        if bool(test()):
            add_pass(name)
            return True

        add_fail(name)
        return False
    except Exception as exc:
        add_fail(f"{name} — {exc}")
        return False


def get_config_value(obj: Any, name: str, default: Any = None) -> Any:
    if obj is None:
        return default

    if isinstance(obj, dict):
        value = obj.get(name, default)
        return default if value is None else value

    value = getattr(obj, name, default)
    return default if value is None else value


def get_config_array(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    return [value]


def get_high_signal_exact_files(config: dict[str, Any]) -> list[str]:
    files: list[str] = []
    for rule in get_config_array(get_config_value(config, "highSignal")):
        file_value = get_config_value(rule, "file")
        if file_value:
            files.append(str(file_value))
        for item in get_config_array(get_config_value(rule, "files")):
            files.append(str(item))
    return files


def get_high_signal_path_prefixes(config: dict[str, Any]) -> list[str]:
    prefixes: list[str] = []
    for rule in get_config_array(get_config_value(config, "highSignal")):
        for prefix in get_config_array(get_config_value(rule, "pathPrefixes")):
            prefixes.append(str(prefix))
    return prefixes


def get_conditional_exact_files(config: dict[str, Any]) -> list[str]:
    files: list[str] = []
    for rule in get_config_array(get_config_value(config, "conditionalFiles")):
        file_value = get_config_value(rule, "file")
        if file_value:
            files.append(str(file_value))
        for item in get_config_array(get_config_value(rule, "files")):
            files.append(str(item))
    return files


def get_conditional_path_prefixes(config: dict[str, Any]) -> list[str]:
    prefixes: list[str] = []
    for rule in get_config_array(get_config_value(config, "conditionalFiles")):
        for prefix in get_config_array(get_config_value(rule, "pathPrefixes")):
            prefixes.append(str(prefix))
    return prefixes


def test_any_prefix_covers(required_prefix: str, actual_prefixes: Iterable[str]) -> bool:
    for prefix in actual_prefixes:
        if required_prefix.startswith(prefix) or prefix.startswith(required_prefix):
            return True
    return False


@dataclass
class GitResult:
    exit_code: int
    output: list[str]


def invoke_git_optional(args: list[str]) -> GitResult:
    result = run_process(["git", "-C", repo_root_resolved, *args])
    return GitResult(
        exit_code=result.returncode,
        output=result.stdout.splitlines(),
    )


def test_git_tracked_exact_file(path: str) -> bool:
    result = invoke_git_optional(["ls-files", "--error-unmatch", "--", path])
    return result.exit_code == 0


def test_git_tracked_prefix(prefix: str) -> bool:
    result = invoke_git_optional(["ls-files", "--", f"{prefix}*"])
    return result.exit_code == 0 and any(line for line in result.output)


def ensure_jsonschema_available_at_start(no_install_deps: bool = False) -> bool:
    """
    Ensure jsonschema is importable before validation starts.

    By default, install it with pip when missing. Pass no_install_deps=True to
    skip installation and downgrade schema validation to a warning.
    """
    global jsonschema_available

    if importlib.util.find_spec(JSONSCHEMA_IMPORT_NAME) is not None:
        jsonschema_available = True
        write_verbose("  ✓ Python package available: jsonschema")
        return True

    if no_install_deps:
        jsonschema_available = False
        add_warn("jsonschema package is not available; schema validation skipped")
        return False

    install_command = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--disable-pip-version-check",
        JSONSCHEMA_PIP_PACKAGE,
    ]

    write_verbose("  ℹ jsonschema package is missing; installing before validation starts:")
    write_verbose("    " + " ".join(shlex.quote(part) for part in install_command))

    result = subprocess.run(
        install_command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    importlib.invalidate_caches()

    if result.returncode == 0 and importlib.util.find_spec(JSONSCHEMA_IMPORT_NAME) is not None:
        jsonschema_available = True
        write_verbose("  ✓ Installed Python package: jsonschema")
        return True

    jsonschema_available = False
    output = (result.stdout or "").strip()
    detail = ""
    if output:
        last_line = output.splitlines()[-1].strip()
        if last_line:
            detail = f" — {last_line}"

    add_warn(f"Could not install jsonschema; schema validation skipped{detail}")
    return False


def format_jsonschema_error(error: Any) -> str:
    path = ".".join(str(part) for part in error.absolute_path)
    if not path:
        path = "<root>"
    return f"{path}: {error.message}"


def test_json_schema_if_available(config: Any, schema: Any) -> None:
    if not jsonschema_available:
        return

    try:
        import jsonschema  # type: ignore[import-not-found]
    except Exception as exc:
        add_warn(
            "jsonschema package is not importable after startup installation attempt; "
            f"schema validation skipped — {exc}"
        )
        return

    def validate_config() -> bool:
        jsonschema.Draft202012Validator.check_schema(schema)
        validator = jsonschema.Draft202012Validator(schema)
        errors = sorted(validator.iter_errors(config), key=lambda item: list(item.absolute_path))
        if errors:
            first_error = format_jsonschema_error(errors[0])
            extra_count = len(errors) - 1
            suffix = f" (+{extra_count} more)" if extra_count > 0 else ""
            raise RuntimeError(f"{first_error}{suffix}")
        return True

    test_check("Config validates against JSON Schema", validate_config)


def sorted_unique(values: Iterable[Any]) -> list[str]:
    return sorted({str(value) for value in values})


def load_json_file(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def path_exists_literal(path: str) -> bool:
    return Path(path).exists()


def get_coverage_required_files(coverage_audit: Any) -> list[Any]:
    # New precise field name first; legacy field retained for compatibility.
    values = get_config_array(get_config_value(coverage_audit, "requiredReleaseSignalFiles"))
    if values:
        return values
    return get_config_array(get_config_value(coverage_audit, "requiredHighSignalFiles"))


def get_coverage_required_prefixes(coverage_audit: Any) -> list[Any]:
    # New precise field name first; legacy field retained for compatibility.
    values = get_config_array(get_config_value(coverage_audit, "requiredReleaseSignalPathPrefixes"))
    if values:
        return values
    return get_config_array(get_config_value(coverage_audit, "requiredHighSignalPathPrefixes"))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate release-signal-config.json and audit rule consistency.",
        add_help=True,
    )
    parser.add_argument("--repo-root", "-RepoRoot", dest="repo_root", default="")
    parser.add_argument("--config-path", "-ConfigPath", dest="config_path", default="")
    parser.add_argument("--schema-path", "-SchemaPath", dest="schema_path", default="")
    parser.add_argument(
        "--no-install-deps",
        "-NoInstallDeps",
        dest="no_install_deps",
        action="store_true",
        help="Do not pip install missing optional dependencies such as jsonschema.",
    )
    parser.add_argument(
        "--verbose",
        "-Verbose",
        "-v",
        dest="verbose",
        action="store_true",
        help="Print detailed section and per-check output.",
    )
    return parser.parse_args(argv)


def print_verbose_header(config_path: str, schema_path: str) -> None:
    write_verbose("╔════════════════════════════════════════╗")
    write_verbose("║  Release Signal Config Check           ║")
    write_verbose("╚════════════════════════════════════════╝")
    write_verbose("")
    write_verbose(f"Repository root: {repo_root_resolved}")
    write_verbose(f"Config path:     {config_path}")
    write_verbose(f"Schema path:     {schema_path}")
    write_verbose("")


def print_summary(config_path: str, schema_path: str) -> None:
    if verbose_mode:
        print("")
        print("╔════════════════════════════════════════╗")
        print("║  FINAL SUMMARY                         ║")
        print("╚════════════════════════════════════════╝")
        print("")
    else:
        print("Release Signal Config Check")

    print(f"  Passed:   {pass_count}")
    print(f"  Warnings: {warn_count}")
    print(f"  Failed:   {fail_count}")

    if warning_messages:
        print("")
        print("Warnings:")
        for message in warning_messages:
            print(f"  ⚠ {message}")

    if failure_messages:
        print("")
        print("Failures:")
        for message in failure_messages:
            print(f"  ✗ {message}")

        print("")
        print("References:")
        print(f"  Repository root: {repo_root_resolved or '<unresolved>'}")
        print(f"  Config path:     {config_path}")
        print(f"  Schema path:     {schema_path}")

    print("")
    if fail_count > 0:
        print(f"✗ {fail_count} check(s) failed")
    else:
        print("✓ All required checks passed")


def main(argv: list[str] | None = None) -> int:
    global repo_root_resolved, verbose_mode

    _configure_stdio()
    args = parse_args(sys.argv[1:] if argv is None else argv)
    verbose_mode = bool(args.verbose)

    if sys.version_info < (3, 11):
        print("Python 3.11 or higher is required.", file=sys.stderr)
        return 1

    # Dependency bootstrap happens at startup, before repository checks begin.
    ensure_jsonschema_available_at_start(no_install_deps=bool(args.no_install_deps))

    repo_root_resolved = resolve_repository_root(args.repo_root)

    if not str(args.config_path).strip():
        config_path = str(Path(repo_root_resolved) / "scripts" / "release-signal-config.json")
    else:
        config_path = resolve_full_path_from_base(repo_root_resolved, args.config_path)

    if not str(args.schema_path).strip():
        schema_path = str(Path(repo_root_resolved) / "scripts" / "release-signal-config.schema.json")
    else:
        schema_path = resolve_full_path_from_base(repo_root_resolved, args.schema_path)

    print_verbose_header(config_path=config_path, schema_path=schema_path)

    write_verbose_section("1. CONFIG AND SCHEMA")

    config_exists = test_check("Config file exists", lambda: path_exists_literal(config_path))
    schema_exists = test_check("Schema file exists", lambda: path_exists_literal(schema_path))

    if not config_exists or not schema_exists:
        add_fail("Cannot continue without config and schema files")
        print_summary(config_path=config_path, schema_path=schema_path)
        return 1

    script_state: dict[str, Any] = {"config": None, "schema": None}

    def parse_config() -> bool:
        script_state["config"] = load_json_file(config_path)
        return script_state["config"] is not None

    def parse_schema() -> bool:
        script_state["schema"] = load_json_file(schema_path)
        return script_state["schema"] is not None

    config_parsed = test_check("Config parses as JSON", parse_config)
    schema_parsed = test_check("Schema parses as JSON", parse_schema)

    if config_parsed and schema_parsed:
        test_json_schema_if_available(config=script_state["config"], schema=script_state["schema"])

    config = script_state["config"]
    if not isinstance(config, dict):
        config = {}

    write_verbose_section("2. REQUIRED SECTIONS")

    for section in (
        "version",
        "project",
        "lowSignal",
        "nonTrivialLines",
        "highSignal",
        "conditionalFiles",
        "labels",
        "docsPolicy",
    ):
        test_check(f"{section} section present", lambda section=section: section in config)

    write_verbose_section("3. FILE AND PREFIX EXISTENCE")

    low_signal = get_config_value(config, "lowSignal")
    low_exact_files = get_config_array(get_config_value(low_signal, "exactFiles"))
    low_prefixes = get_config_array(get_config_value(low_signal, "pathPrefixes"))
    high_files = get_high_signal_exact_files(config)
    high_prefixes = get_high_signal_path_prefixes(config)
    conditional_files = get_conditional_exact_files(config)
    conditional_prefixes = get_conditional_path_prefixes(config)

    for file_value in sorted_unique([*low_exact_files, *high_files, *conditional_files]):
        test_check(
            f"Configured file path exists: {file_value}",
            lambda file_value=file_value: path_exists_literal(resolve_repo_path(str(file_value))),
        )

    for prefix in sorted_unique([*low_prefixes, *high_prefixes, *conditional_prefixes]):
        trimmed = str(prefix).rstrip("/")
        test_check(
            f"Configured path prefix exists: {prefix}",
            lambda trimmed=trimmed: path_exists_literal(resolve_repo_path(trimmed)),
        )

    docs_policy = get_config_value(config, "docsPolicy")
    for field in ("unreleasedFile", "readmeFile", "changelogFile", "agentsFile"):
        policy_path = str(get_config_value(docs_policy, field, "") or "")
        if policy_path:
            test_check(
                f"Docs policy file exists: {policy_path}",
                lambda policy_path=policy_path: path_exists_literal(resolve_repo_path(policy_path)),
            )

    write_verbose_section("4. RULE CONSISTENCY")

    assignments: list[tuple[str, str]] = []
    for file_value in low_exact_files:
        assignments.append((str(file_value), "lowSignal.exactFiles"))
    for file_value in high_files:
        assignments.append((str(file_value), "highSignal"))
    for file_value in conditional_files:
        assignments.append((str(file_value), "conditionalFiles"))

    buckets_by_file: dict[str, set[str]] = defaultdict(set)
    for file_value, bucket in assignments:
        buckets_by_file[file_value].add(bucket)

    duplicated_files = [(file_value, buckets) for file_value, buckets in buckets_by_file.items() if len(buckets) > 1]
    if duplicated_files:
        for file_value, buckets in sorted(duplicated_files):
            bucket_text = ", ".join(sorted(buckets))
            add_fail(f"File appears in multiple rule buckets: {file_value} ({bucket_text})")
    else:
        add_pass("No exact file is assigned to multiple rule buckets")

    label_config = get_config_value(config, "labels")
    test_check(
        "releaseNeeded and releaseNone labels differ",
        lambda: str(get_config_value(label_config, "releaseNeeded"))
        != str(get_config_value(label_config, "releaseNone")),
    )

    write_verbose_section("5. OPTIONAL COVERAGE AUDIT")

    coverage_audit = get_config_value(config, "coverageAudit")
    if coverage_audit is None:
        add_warn("No coverageAudit section found; shipped-code coverage audit skipped")
    else:
        release_signal_files_for_audit = sorted_unique([*high_files, *conditional_files])
        release_signal_prefixes_for_audit = sorted_unique([*high_prefixes, *conditional_prefixes])

        required_files = get_coverage_required_files(coverage_audit)
        for file_value in required_files:
            test_check(
                f"Required release-signal file covered: {file_value}",
                lambda file_value=str(file_value): file_value in release_signal_files_for_audit,
            )

        required_prefixes = get_coverage_required_prefixes(coverage_audit)
        for prefix in required_prefixes:
            test_check(
                f"Required release-signal prefix covered: {prefix}",
                lambda prefix=str(prefix): test_any_prefix_covers(prefix, release_signal_prefixes_for_audit),
            )

    write_verbose_section("6. TRACKED-FILE ALIGNMENT")

    git_available = False
    try:
        git_probe = invoke_git_optional(["rev-parse", "--is-inside-work-tree"])
        git_available = git_probe.exit_code == 0
    except Exception:
        git_available = False

    if not git_available:
        add_warn("Not inside a git work tree or git unavailable; tracked-file alignment skipped")
    else:
        for file_value in sorted_unique([*low_exact_files, *high_files, *conditional_files]):
            test_check(
                f"Git tracks configured file: {file_value}",
                lambda file_value=file_value: test_git_tracked_exact_file(str(file_value)),
            )

        for prefix in sorted_unique([*low_prefixes, *high_prefixes, *conditional_prefixes]):
            test_check(
                f"Git tracks at least one file under prefix: {prefix}",
                lambda prefix=prefix: test_git_tracked_prefix(str(prefix)),
            )

    print_summary(config_path=config_path, schema_path=schema_path)
    return 1 if fail_count > 0 else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
