"""Validate native QA reports without changing task state."""

import argparse
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import re


REQUIRED_CHECKS = {
    'backend': ('contract', 'network', 'failure_path'),
    'frontend': ('ui', 'console', 'network', 'failure_path'),
    'workflow': ('config', 'native_dispatch', 'scope', 'recovery'),
}


def validate(report, task_id, attempt, kind, evidence_root):
    errors = []
    if not isinstance(report, dict):
        return ['Report must be a JSON object']
    if not re.fullmatch(r'[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+', task_id):
        return ['Invalid expected task ID']
    if attempt < 1:
        return ['Expected attempt must be positive']
    if report.get('task_id') != task_id:
        errors.append('Task ID does not match')
    if type(report.get('attempt')) is not int or report['attempt'] != attempt:
        errors.append('Attempt does not match')
    if report.get('verdict') != 'PASS':
        errors.append('Verdict must be PASS')
    for field in ('worker', 'summary'):
        if not isinstance(report.get(field), str) or not report[field].strip():
            errors.append(field + ' must be a nonempty string')

    commands = report.get('commands')
    if not isinstance(commands, list) or not commands:
        errors.append('At least one executed command is required')
    else:
        for command in commands:
            if (not isinstance(command, dict)
                    or not isinstance(command.get('command'), str)
                    or not command['command'].strip()
                    or type(command.get('exit_code')) is not int
                    or command['exit_code'] != 0):
                errors.append('Every reported command must have exit_code 0')

    checks = report.get('checks')
    if not isinstance(checks, dict):
        return errors + ['Checks must be an object']
    for name in REQUIRED_CHECKS[kind]:
        if name not in checks:
            errors.append('Missing required check: ' + name)

    root = evidence_root.resolve()
    expected = root / task_id / ('attempt-' + str(attempt))
    allowed = expected.resolve()
    if allowed != expected or not allowed.is_relative_to(root):
        return errors + ['Current task/attempt directory must not redirect elsewhere']
    for name, check in checks.items():
        if not isinstance(check, dict) or check.get('pass') is not True:
            errors.append('Check did not pass: ' + name)
            continue
        if name == 'network' and check.get('has_5xx') is not False:
            errors.append('Network check must explicitly report has_5xx=false')
        if name == 'console' and (type(check.get('error_count')) is not int
                                  or check['error_count'] != 0):
            errors.append('Console check must report error_count=0')
        evidence = check.get('evidence')
        if not isinstance(evidence, list) or not evidence:
            errors.append('Check has no evidence: ' + name)
            continue
        for item in evidence:
            if not isinstance(item, str):
                errors.append('Evidence path must be a string')
                continue
            path = PurePosixPath(item.replace('\\', '/'))
            if (path.is_absolute() or PureWindowsPath(item).drive
                    or '..' in path.parts or not path.parts
                    or path.parts[0] != '05-verification'):
                errors.append('Evidence path must be relative and inside 05-verification')
                continue
            target = root.joinpath(*path.parts[1:]).resolve()
            if not target.is_relative_to(allowed) or not target.is_file():
                errors.append('Evidence is missing or outside current task/attempt: ' + item)
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--task-id', required=True)
    parser.add_argument('--attempt', type=int, required=True)
    parser.add_argument('--kind', choices=REQUIRED_CHECKS, required=True)
    parser.add_argument('--evidence-root', type=Path,
                        default=Path(__file__).resolve().parents[1] / '05-verification')
    args = parser.parse_args()
    try:
        report = json.loads(args.result.read_text(encoding='utf-8-sig'))
        errors = validate(report, args.task_id, args.attempt, args.kind, args.evidence_root)
    except (OSError, ValueError, TypeError) as error:
        errors = ['Cannot validate report: ' + str(error)]
    print(json.dumps({'valid': not errors, 'task_id': args.task_id,
                      'attempt': args.attempt, 'errors': errors}))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
