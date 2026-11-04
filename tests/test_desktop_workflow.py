import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

try:
    import tomllib
except ImportError:
    from pip._vendor import tomli as tomllib


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / 'scripts' / 'validate-desktop-result.py'


class ResultValidationTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / 'runtime' / 'tests'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.evidence = self.root / '05-verification'
        self.task_dir = self.evidence / 'CCB-MIGRATION-001' / 'attempt-1'
        self.task_dir.mkdir(parents=True)
        (self.task_dir / 'check.txt').write_text('verified\n', encoding='utf-8')
        self.report = {
            'task_id': 'CCB-MIGRATION-001', 'attempt': 1, 'worker': 'migration-qa',
            'verdict': 'PASS', 'summary': '迁移验收',
            'commands': [{'command': 'python -m unittest', 'exit_code': 0}],
            'checks': {name: {'pass': True, 'evidence': [
                '05-verification/CCB-MIGRATION-001/attempt-1/check.txt'
            ]} for name in ['config', 'native_dispatch', 'scope', 'recovery']}
        }

    def run_checker(self, report=None, kind='workflow'):
        report_path = self.root / 'report.json'
        report_path.write_text(json.dumps(report or self.report), encoding='utf-8')
        result = subprocess.run([
            sys.executable, str(CHECKER), '--result', str(report_path),
            '--task-id', 'CCB-MIGRATION-001', '--attempt', '1',
            '--kind', kind, '--evidence-root', str(self.evidence)
        ], capture_output=True, text=True, encoding='utf-8')
        return result

    def test_valid_report_passes(self):
        self.assertEqual(self.run_checker().returncode, 0)

    def reject(self, report, kind='workflow'):
        result = self.run_checker(report, kind)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(json.loads(result.stdout)['valid'])

    def test_stale_attempt_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['attempt'] = 2
        self.reject(report)

    def test_wrong_task_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['task_id'] = 'OTHER-001'
        self.reject(report)

    def test_missing_evidence_is_rejected(self):
        (self.task_dir / 'check.txt').unlink()
        self.reject(self.report)

    def test_other_attempt_evidence_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['checks']['scope']['evidence'] = [
            '05-verification/CCB-MIGRATION-001/attempt-2/check.txt'
        ]
        self.reject(report)

    @unittest.skipUnless(sys.platform == 'win32', 'Windows junction regression')
    def test_task_directory_cannot_alias_another_task_attempt(self):
        (self.task_dir / 'check.txt').unlink()
        self.task_dir.rmdir()
        other = self.evidence / 'OTHER-001' / 'attempt-2'
        other.mkdir(parents=True)
        (other / 'check.txt').write_text('old task evidence', encoding='utf-8')
        junction = str(self.task_dir).replace("'", "''")
        target = str(other).replace("'", "''")
        subprocess.run([
            r'C:\Program Files\PowerShell\7\pwsh.exe', '-NoProfile', '-Command',
            "New-Item -ItemType Junction -Path '" + junction + "' -Target '"
            + target + "' -ErrorAction Stop | Out-Null"
        ], check=True, capture_output=True)
        try:
            self.reject(self.report)
        finally:
            os.rmdir(self.task_dir)

    def test_parent_traversal_is_rejected(self):
        outside = self.root / 'secret.txt'
        outside.write_text('not evidence', encoding='utf-8')
        report = copy.deepcopy(self.report)
        report['checks']['scope']['evidence'] = ['05-verification/../secret.txt']
        self.reject(report)

    def test_absolute_path_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['checks']['scope']['evidence'] = [str(self.task_dir / 'check.txt')]
        self.reject(report)

    def test_failed_command_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['commands'][0]['exit_code'] = 1
        self.reject(report)

    def test_failed_verdict_is_rejected(self):
        report = copy.deepcopy(self.report)
        report['verdict'] = 'BLOCKED'
        self.reject(report)

    def test_missing_check_is_rejected(self):
        report = copy.deepcopy(self.report)
        del report['checks']['recovery']
        self.reject(report)

    def test_network_failure_and_console_errors_are_rejected(self):
        report = copy.deepcopy(self.report)
        report['checks'] = {name: copy.deepcopy(self.report['checks']['scope'])
                            for name in ['ui', 'console', 'network', 'failure_path']}
        report['checks']['console']['error_count'] = 0
        report['checks']['network']['has_5xx'] = True
        self.reject(report, 'frontend')
        report['checks']['network']['has_5xx'] = False
        report['checks']['console']['error_count'] = 1
        self.reject(report, 'frontend')


class ProjectConfigurationTests(unittest.TestCase):
    def test_roles_are_project_local_and_do_not_override_user_settings(self):
        config_path = ROOT / '.codex' / 'config.toml'
        self.assertTrue(config_path.is_file(), 'Project role registry is missing')
        config = tomllib.loads(config_path.read_text(encoding='utf-8'))
        self.assertEqual(set(config), {'agents'})
        self.assertEqual(set(config['agents']), {
            'backend-dev', 'backend-qa', 'admin-fe-dev', 'admin-fe-qa',
            'shop-fe-dev', 'shop-fe-qa'
        })
        for name, role in config['agents'].items():
            with self.subTest(role=name):
                role_path = (config_path.parent / role['config_file']).resolve()
                self.assertTrue(role_path.is_relative_to(ROOT / '.codex' / 'agents'))
                definition = tomllib.loads(role_path.read_text(encoding='utf-8'))
                self.assertEqual(set(definition), {'developer_instructions'})
                self.assertIn('codex-desktop-workflow.md', definition['developer_instructions'])

    def test_new_templates_have_native_context(self):
        for path in (ROOT / '01-tasks' / 'templates').glob('tech-spec-*.md'):
            with self.subTest(path=path.name):
                text = path.read_text(encoding='utf-8-sig')
                self.assertIn('**执行模式:** codex-desktop', text)
                self.assertIn('**当前 attempt:**', text)
                self.assertIn('QA_LEVEL 规则', text)
                self.assertIn('full', text)
                self.assertIn('smoke', text)
                self.assertIn('skip', text)
                self.assertNotIn('report_route(status=', text)
                self.assertNotIn('\\CLAUDE.md', text)

    def test_qa_is_risk_triggered_instead_of_always_chained(self):
        workflow = (ROOT / '03-guides' / 'codex-desktop-workflow.md').read_text(encoding='utf-8')
        root_rules = (ROOT / 'AGENTS.md').read_text(encoding='utf-8')
        readme = (ROOT / 'README.md').read_text(encoding='utf-8')
        for text in (workflow, root_rules, readme):
            self.assertIn('QA_LEVEL', text)
            self.assertIn('full', text)
            self.assertIn('smoke', text)
            self.assertIn('skip', text)
        self.assertIn('不是开发自测的重复执行者', workflow)
        self.assertIn('未触发 QA', workflow)
        self.assertNotIn('每个开发任务都必须派独立 QA', workflow)

    def test_ignore_policy_keeps_summaries_and_roles_but_excludes_local_data(self):
        scratch = ROOT / 'runtime' / 'tests'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            repo = Path(directory)
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            (repo / '.gitignore').write_bytes((ROOT / '.gitignore').read_bytes())
            cases = {
                '05-verification/CCB-001/summary.md': False,
                '05-verification/CCB-001/attempt-1/raw.log': True,
                '05-verification/QA-IDENTITY-POOL.md': True,
                '.codex/agents/backend-dev.toml': False,
                '.state/orchestrator.db': True,
                'deploy/moxton-webapi/dist.zip': True,
                'docs/preorder-expo/leads.xlsx': True,
                'runtime/migrations/before.zip': True,
            }
            for path, expected in cases.items():
                with self.subTest(path=path):
                    result = subprocess.run(['git', '-C', str(repo), 'check-ignore',
                                             '--no-index', '-q', path])
                    self.assertEqual(result.returncode, 0 if expected else 1)


if __name__ == '__main__':
    unittest.main()
