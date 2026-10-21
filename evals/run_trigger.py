#!/usr/bin/env python3
"""Trigger eval for ui-tuning-lab.

Each query runs `claude -p` in an empty scratch project where the packaged skill
is installed as a project skill. Shell, edit, and web tools are disabled so the
run cannot touch real files; a query counts as triggered when the model invokes
the skill (or reads its SKILL.md) at any point within --max-turns.

skill-creator's run_eval counts only the first tool call. In environments whose
global instructions say "explore first", that scores real triggers as misses, so
this runner checks the whole short run instead.

Usage: python3 evals/run_trigger.py --claude <path> --model <id> [--runs 1]
"""
import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DISALLOWED = "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch"


def make_project(package: Path) -> Path:
    project = Path(tempfile.mkdtemp(prefix="uitl-trigger-"))
    shutil.copytree(package, project / ".claude" / "skills" / "ui-tuning-lab")
    (project / "README.md").write_text("Scratch project for a trigger eval.\n")
    return project


def run_query(claude: str, model: str, project: Path, query: str, max_turns: int, timeout: int) -> dict:
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    cmd = [claude, "-p", query, "--model", model, "--output-format", "stream-json", "--verbose",
           "--max-turns", str(max_turns), "--disallowedTools", DISALLOWED]
    tools, error = [], None
    try:
        out = subprocess.run(cmd, cwd=project, env=env, capture_output=True, text=True, timeout=timeout).stdout
    except subprocess.TimeoutExpired as exc:
        out, error = (exc.stdout or b"").decode() if isinstance(exc.stdout, bytes) else (exc.stdout or ""), "timeout"
    for line in out.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "assistant":
            for item in event.get("message", {}).get("content", []):
                if item.get("type") == "tool_use":
                    tools.append((item.get("name"), json.dumps(item.get("input", {}))[:200]))
        # Hitting --max-turns is the expected way a non-triggering run ends.
        if event.get("type") == "result" and event.get("is_error") and event.get("subtype") != "error_max_turns":
            error = (event.get("result") or event.get("subtype") or "error")[:200]
    triggered = any(
        (name == "Skill" and "ui-tuning-lab" in arg) or (name == "Read" and "ui-tuning-lab/SKILL.md" in arg)
        for name, arg in tools
    )
    return {"triggered": triggered, "tools": [name for name, _ in tools], "error": error}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--claude", default="claude")
    parser.add_argument("--model", required=True)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--max-turns", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--eval-set", default=str(ROOT / "evals" / "trigger-eval.json"))
    args = parser.parse_args()

    package_dir = Path(tempfile.mkdtemp(prefix="uitl-package-"))
    subprocess.run(["sh", str(ROOT / "tools" / "package.sh"), str(package_dir)], check=True, capture_output=True)
    package = package_dir / "ui-tuning-lab"
    queries = json.loads(Path(args.eval_set).read_text())

    jobs = [(q, r) for q in queries for r in range(args.runs)]
    projects = [make_project(package) for _ in jobs]
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(run_query, args.claude, args.model, project, q["query"], args.max_turns, args.timeout): (q["query"], r)
            for (q, r), project in zip(jobs, projects)
        }
        for future in concurrent.futures.as_completed(futures):
            results.setdefault(futures[future][0], []).append(future.result())

    rows, errors = [], 0
    for q in queries:
        runs = results[q["query"]]
        errors += sum(1 for run in runs if run["error"])
        rate = sum(run["triggered"] for run in runs) / len(runs)
        passed = rate >= 0.5 if q["should_trigger"] else rate < 0.5
        rows.append({"query": q["query"], "should_trigger": q["should_trigger"], "trigger_rate": rate,
                     "pass": passed, "runs": runs})
    positives = [row for row in rows if row["should_trigger"]]
    negatives = [row for row in rows if not row["should_trigger"]]
    summary = {
        "true_positive": sum(row["pass"] for row in positives), "positives": len(positives),
        "false_positive": sum(not row["pass"] for row in negatives), "negatives": len(negatives),
        "runs_with_errors": errors, "model": args.model, "runs_per_query": args.runs, "max_turns": args.max_turns,
    }
    print(json.dumps({"summary": summary, "results": rows}, indent=2))
    for path in projects + [package_dir]:
        shutil.rmtree(path, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
