#!/usr/bin/env python3
"""Aggregate thesis CI/CD pipeline run logs into summary statistics.

Usage:
    python scripts/aggregate-results.py logs/ > results-summary.json

Reads the JSONL event logs produced by run-scenario.sh (run-*.jsonl) and
run-manual-baseline.sh (manual-*.jsonl), groups runs by scenario, and computes
per-scenario timing statistics for Chapter 4. The JSON summary is written to
stdout; a Markdown summary table is written to results-summary.md.

Malformed or unidentifiable log files are skipped with a warning on stderr
rather than aborting the run.
"""
import argparse
import glob
import json
import os
import statistics
import sys
from datetime import datetime

SCENARIOS = ["successful", "broken-image", "broken-smoke", "slow-start"]


def warn(message):
    print(f"WARNING: {message}", file=sys.stderr)


def parse_timestamp(value):
    """Parse an ISO 8601 UTC timestamp (the trailing Z form used by log.sh)."""
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_events(path):
    """Return the list of event dicts in a JSONL file.

    Raises ValueError if any non-empty line is not valid JSON.
    """
    events = []
    with open(path, encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"line {lineno}: {exc}") from exc
    return events


def first_event(events, name):
    """The first event with the given name, or None."""
    for event in events:
        if event.get("event") == name:
            return event
    return None


def seconds_between(events, start_name, end_name):
    """Seconds from the first start_name event to the first end_name event,
    or None if either event is missing."""
    start = first_event(events, start_name)
    end = first_event(events, end_name)
    if start is None or end is None:
        return None
    return (parse_timestamp(end["timestamp"])
            - parse_timestamp(start["timestamp"])).total_seconds()


def failure_time(events):
    """Timestamp of the earliest failure-detection event, or None.

    A run fails either at the health check (health_check_failed) or at the
    smoke tests (smoke_test_failed); whichever came first is the detection
    point used for time-to-detect and MTTR.
    """
    candidates = []
    for name in ("health_check_failed", "smoke_test_failed"):
        event = first_event(events, name)
        if event is not None:
            candidates.append(parse_timestamp(event["timestamp"]))
    return min(candidates) if candidates else None


def stats(values):
    """Summary statistics for a list of numbers, or None if the list is empty.

    stdev is None for fewer than two values, since the sample standard
    deviation is undefined for a single observation.
    """
    if not values:
        return None
    return {
        "count": len(values),
        "mean": round(statistics.mean(values), 3),
        "min": round(min(values), 3),
        "max": round(max(values), 3),
        "stdev": round(statistics.stdev(values), 3) if len(values) > 1 else None,
    }


def new_bucket(extra_keys):
    bucket = {"analysed": 0, "correct": 0}
    for key in extra_keys:
        bucket[key] = []
    return bucket


def expected_outcome(scenario):
    return "success" if scenario == "successful" else "rolled_back"


def process_automated(paths):
    """Aggregate the automated run logs (run-*.jsonl)."""
    runs = {s: new_bucket(["detect", "mttr"]) for s in SCENARIOS}
    excluded = []

    for path in sorted(paths):
        name = os.path.basename(path)
        try:
            events = load_events(path)
        except (ValueError, OSError) as exc:
            warn(f"excluding {name}: {exc}")
            excluded.append({"file": name, "reason": str(exc)})
            continue

        start = first_event(events, "deployment_start")
        completed = first_event(events, "scenario_completed")
        if start is None or completed is None:
            reason = "missing deployment_start or scenario_completed"
            warn(f"excluding {name}: {reason}")
            excluded.append({"file": name, "reason": reason})
            continue

        scenario = start.get("scenario") or completed.get("scenario")
        if scenario not in runs:
            reason = f"unknown scenario '{scenario}'"
            warn(f"excluding {name}: {reason}")
            excluded.append({"file": name, "reason": reason})
            continue

        bucket = runs[scenario]
        bucket["analysed"] += 1
        if completed.get("outcome") == expected_outcome(scenario):
            bucket["correct"] += 1

        # Timing metrics apply only to runs that recorded a failure.
        failed_at = failure_time(events)
        if failed_at is not None:
            started_at = parse_timestamp(start["timestamp"])
            bucket["detect"].append((failed_at - started_at).total_seconds())
            recovered = first_event(events, "post_rollback_health_check_passed")
            if recovered is not None:
                recovered_at = parse_timestamp(recovered["timestamp"])
                bucket["mttr"].append((recovered_at - failed_at).total_seconds())

    summary = {}
    for scenario in SCENARIOS:
        bucket = runs[scenario]
        if bucket["analysed"] == 0:
            continue
        summary[scenario] = {
            "runs_analysed": bucket["analysed"],
            "runs_correct": bucket["correct"],
            "time_to_detect_seconds": stats(bucket["detect"]),
            "mttr_seconds": stats(bucket["mttr"]),
        }
    return summary, excluded


def process_manual(paths):
    """Aggregate the manual baseline logs (manual-*.jsonl)."""
    runs = {s: new_bucket(["cycle", "detect", "mttr"]) for s in SCENARIOS}
    excluded = []

    for path in sorted(paths):
        name = os.path.basename(path)
        try:
            events = load_events(path)
        except (ValueError, OSError) as exc:
            warn(f"excluding {name}: {exc}")
            excluded.append({"file": name, "reason": str(exc)})
            continue

        start = first_event(events, "manual_start")
        completed = first_event(events, "manual_completed")
        if start is None or completed is None:
            reason = "missing manual_start or manual_completed"
            warn(f"excluding {name}: {reason}")
            excluded.append({"file": name, "reason": reason})
            continue

        scenario = start.get("scenario") or completed.get("scenario")
        if scenario not in runs:
            reason = f"unknown scenario '{scenario}'"
            warn(f"excluding {name}: {reason}")
            excluded.append({"file": name, "reason": reason})
            continue

        bucket = runs[scenario]
        bucket["analysed"] += 1
        if completed.get("outcome") == expected_outcome(scenario):
            bucket["correct"] += 1

        cycle = seconds_between(events, "manual_start", "manual_completed")
        if cycle is not None:
            bucket["cycle"].append(cycle)
        detect = seconds_between(events, "manual_deployment_done",
                                 "manual_failure_detected")
        if detect is not None:
            bucket["detect"].append(detect)
        mttr = seconds_between(events, "manual_failure_detected",
                               "manual_rollback_done")
        if mttr is not None:
            bucket["mttr"].append(mttr)

    summary = {}
    for scenario in SCENARIOS:
        bucket = runs[scenario]
        if bucket["analysed"] == 0:
            continue
        summary[scenario] = {
            "runs_analysed": bucket["analysed"],
            "runs_correct": bucket["correct"],
            "total_cycle_seconds": stats(bucket["cycle"]),
            "time_to_detect_seconds": stats(bucket["detect"]),
            "mttr_seconds": stats(bucket["mttr"]),
        }
    return summary, excluded


def fmt(metric):
    """Render a stats dict as a Markdown table cell."""
    if metric is None:
        return "n/a"
    if metric["stdev"] is None:
        return f"{metric['mean']:.3f}"
    return f"{metric['mean']:.3f} (sd {metric['stdev']:.3f})"


def render_markdown(summary):
    lines = ["# Results Summary", ""]

    lines += ["## Automated runs", ""]
    if summary["automated"]:
        lines += ["| Scenario | Runs | Correct | Time-to-detect (s) | MTTR (s) |",
                  "|----------|------|---------|--------------------|----------|"]
        for scenario, data in summary["automated"].items():
            lines.append(
                f"| {scenario} | {data['runs_analysed']} | "
                f"{data['runs_correct']}/{data['runs_analysed']} | "
                f"{fmt(data['time_to_detect_seconds'])} | "
                f"{fmt(data['mttr_seconds'])} |")
    else:
        lines.append("_No automated run logs found._")
    lines.append("")

    lines += ["## Manual baseline", ""]
    if summary["manual"]:
        lines += ["| Scenario | Runs | Correct | Total cycle (s) | "
                  "Time-to-detect (s) | MTTR (s) |",
                  "|----------|------|---------|-----------------|"
                  "--------------------|----------|"]
        for scenario, data in summary["manual"].items():
            lines.append(
                f"| {scenario} | {data['runs_analysed']} | "
                f"{data['runs_correct']}/{data['runs_analysed']} | "
                f"{fmt(data['total_cycle_seconds'])} | "
                f"{fmt(data['time_to_detect_seconds'])} | "
                f"{fmt(data['mttr_seconds'])} |")
    else:
        lines.append("_No manual baseline logs found._")
    lines.append("")

    if summary["excluded_files"]:
        lines += ["## Excluded files", ""]
        for item in summary["excluded_files"]:
            lines.append(f"- `{item['file']}` - {item['reason']}")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate thesis CI/CD pipeline run logs.")
    parser.add_argument("logdir", help="directory containing the JSONL logs")
    parser.add_argument("--md-output", default="results-summary.md",
                        help="path for the Markdown summary "
                             "(default: results-summary.md)")
    args = parser.parse_args()

    if not os.path.isdir(args.logdir):
        print(f"ERROR: not a directory: {args.logdir}", file=sys.stderr)
        return 1

    automated_paths = glob.glob(os.path.join(args.logdir, "run-*.jsonl"))
    manual_paths = glob.glob(os.path.join(args.logdir, "manual-*.jsonl"))

    automated, excluded_a = process_automated(automated_paths)
    manual, excluded_m = process_manual(manual_paths)

    summary = {
        "automated": automated,
        "manual": manual,
        "excluded_files": excluded_a + excluded_m,
    }

    with open(args.md_output, "w", encoding="utf-8") as handle:
        handle.write(render_markdown(summary) + "\n")
    print(f"wrote {args.md_output}", file=sys.stderr)

    json.dump(summary, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
