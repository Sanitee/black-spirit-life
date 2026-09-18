"""Offline synthetic histories only. Never reads publisher profiles or remote Git."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


PROJECT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'git_privacy', PROJECT / 'tool' / 'release' / 'verify_git_object_privacy.py')
scanner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scanner)
POWERSHELL = os.environ.get('BSL_PRIVACY_TEST_POWERSHELL', 'powershell.exe')
PRIVATE_MARKER = 'synthetic-' + 'private-' + 'profile-root'
MACHINE_PATH = 'Q:' + '\\' + 'Users' + '\\' + 'SyntheticOnly' + '\\' + 'private'
SECRET = 'gh' + 'p_' + 'Z' * 30


class GitPrivacyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy_path = PROJECT / 'tool' / 'verify_production_source.ps1'
        cls.policy, cls.policy_hash = scanner.load_policy(
            cls.policy_path, scanner.sha(cls.policy_path.read_bytes()), POWERSHELL)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bsl-git-privacy-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Synthetic Tester')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        self.write('readme.md', b'synthetic public reference\n')
        self.commit()
        self.sequence = 0

    def git(self, *args, data=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_AUTHOR_DATE='2025-01-01T00:00:00Z',
                   GIT_COMMITTER_DATE='2025-01-01T00:00:00Z')
        result = subprocess.run(['git', '-C', str(self.repo), *args], input=data,
                                capture_output=True, env=env, timeout=30)
        self.assertEqual(result.returncode, 0, 'synthetic git command failed')
        return result.stdout.decode('utf-8').strip()

    def write(self, relative, content):
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)

    def commit(self, message='synthetic change'):
        self.git('add', '--all')
        self.git('commit', '-q', '-m', message)
        self.git('tag', '-f', 'release-test')

    def refs(self):
        return dict(line.split(' ') for line in self.git(
            'for-each-ref', '--format=%(refname) %(objectname)').splitlines())

    def scan(self, prior=None, **overrides):
        self.sequence += 1
        args = dict(root=self.repo, expected_commit=self.git('rev-parse', 'HEAD'),
                    expected_tag='refs/tags/release-test', expected_refs=self.refs(),
                    policy=self.policy, policy_hash=self.policy_hash,
                    receipt_path=self.base / f'result-{self.sequence}.json',
                    markers=[PRIVATE_MARKER])
        if prior:
            args.update(prior_path=prior[0], prior_sha256=prior[1])
        args.update(overrides)
        result, digest = scanner.scan(**args)
        return result, (args['receipt_path'], digest)

    def altered_receipt(self, prior, change):
        receipt = json.loads(prior[0].read_bytes())
        change(receipt)
        path = self.base / 'altered.json'
        raw = scanner.canonical(receipt)
        path.write_bytes(raw)
        return path, scanner.sha(raw)

    def test_cold_warm_100_blobs_measurement_and_subset(self):
        for i in range(100):
            self.write(f'lib/item-{i}.txt', (f'reference {i}\n' * 100).encode())
        self.commit()
        old = self.git('rev-parse', 'HEAD')
        cold, cold_receipt = self.scan()
        warm, _ = self.scan(cold_receipt)
        self.assertEqual(warm['metrics']['scanned_entries'], 0)
        self.assertEqual(warm['metrics']['content_bytes_scanned'], 0)
        self.assertEqual(cold['metrics']['content_bytes_scanned'],
                         warm['metrics']['content_bytes_reused'])
        self.assertGreaterEqual(cold['metrics']['scanned_entries'], 103)
        print('GIT_PRIVACY_MEASUREMENT ' + json.dumps({
            'cold': cold['metrics'], 'warm': warm['metrics']}, sort_keys=True))
        self.write('lib/new.txt', b'one new object\n')
        self.commit()
        added, added_receipt = self.scan(cold_receipt)
        self.assertEqual(added['metrics']['scanned_entries'], 2)  # blob + commit
        self.git('checkout', '--detach', old)
        self.git('branch', '-f', 'main', old)
        self.git('tag', '-f', 'release-test', old)
        subset, _ = self.scan(added_receipt)
        self.assertEqual(subset['metrics']['scanned_entries'], 0)

    def test_same_blob_forbidden_new_name_warm(self):
        _, prior = self.scan()
        self.write('sessions.json', (self.repo / 'readme.md').read_bytes())
        self.commit()
        with self.assertRaisesRegex(scanner.ScanError, 'forbidden-history-filename'):
            self.scan(prior)

    def test_direct_tree_ref_with_reused_blob_is_rejected_cold_and_warm(self):
        _, prior = self.scan()
        blob = self.git('rev-parse', 'HEAD:readme.md')
        tree = self.git('mktree', data=f'100644 blob {blob}\tsessions.json\n'.encode())
        self.git('tag', 'tree-reference', tree)
        for baseline in [None, prior]:
            with self.assertRaisesRegex(scanner.ScanError, 'noncommit-ref-target'):
                self.scan(baseline)

    def test_forbidden_empty_tree_directory_cold_and_warm(self):
        _, prior = self.scan()
        empty = self.git('mktree', data=b'')
        blob = self.git('rev-parse', 'HEAD:readme.md')
        tree = self.git('mktree', data=(f'040000 tree {empty}\tbrowser-profile\n'
                                       f'100644 blob {blob}\treadme.md\n').encode())
        commit = self.git('commit-tree', tree, '-p', 'HEAD', '-m', 'synthetic empty tree')
        self.git('update-ref', 'refs/heads/main', commit)
        self.git('tag', '-f', 'release-test')
        for baseline in [None, prior]:
            with self.assertRaisesRegex(scanner.ScanError, 'forbidden-history-path'):
                self.scan(baseline)

    def test_windows_aliases_and_directory_case_collision(self):
        for path in ['nested./safe.txt', 'nested /safe.txt', 'CON.txt', 'COM1/item.txt',
                     'bad?.txt', 'LPT' + chr(0xb2) + '.txt']:
            with self.assertRaisesRegex(scanner.ScanError, 'ambiguous-windows-history-path'):
                scanner.check_path(path, self.policy, [PRIVATE_MARKER])
        blob = self.git('rev-parse', 'HEAD:readme.md')
        first = self.git('mktree', data=f'100644 blob {blob}\ta.txt\n'.encode())
        second = self.git('mktree', data=f'100644 blob {blob}\tb.txt\n'.encode())
        tree = self.git('mktree', data=(f'040000 tree {first}\tFoo\n'
                                       f'040000 tree {second}\tfoo\n').encode())
        commit = self.git('commit-tree', tree, '-p', 'HEAD', '-m', 'synthetic case alias')
        self.git('update-ref', 'refs/heads/main', commit)
        self.git('tag', '-f', 'release-test')
        with self.assertRaisesRegex(scanner.ScanError, 'case-colliding-history-path'):
            self.scan()

    def test_every_historical_path_not_only_current_or_one_name(self):
        self.write('browser-profile/payload.txt', b'same public bytes')
        self.write('safe.txt', b'same public bytes')
        self.commit()
        (self.repo / 'browser-profile' / 'payload.txt').unlink()
        self.commit()
        with self.assertRaisesRegex(scanner.ScanError, 'forbidden-history-path'):
            self.scan()

    def test_mode_change_binary_to_text_is_not_reused(self):
        self.write('reference.png', SECRET.encode())
        self.commit()
        _, prior = self.scan()
        self.write('reference.txt', SECRET.encode())
        self.commit()
        with self.assertRaisesRegex(scanner.ScanError, 'secret-content'):
            self.scan(prior)

    def test_allowlisted_path_to_strict_path_is_not_reused(self):
        self.write(self.policy['machinePathFixtureAllowlist'][0], MACHINE_PATH.encode())
        self.commit()
        _, prior = self.scan()
        self.write('lib/strict.dart', MACHINE_PATH.encode())
        self.commit()
        with self.assertRaisesRegex(scanner.ScanError, 'machine-path-content'):
            self.scan(prior)

    def test_exact_excluded_path_and_tracked_generated(self):
        for name in [self.policy['excludedRelativePaths'][0], 'nested/build/a.txt',
                     'windows/flutter/ephemeral/a.txt', 'a.sqlite3', 'trace.log',
                     'session-import-inbox/a.txt', 'icons/' + 'a' * 64 + '.png']:
            with self.subTest(case=name):
                with self.assertRaises(scanner.ScanError):
                    scanner.check_path(name, self.policy, [PRIVATE_MARKER])

    def test_text_privacy_and_encodings(self):
        for value in [SECRET, MACHINE_PATH, PRIVATE_MARKER]:
            for encoding in ['utf-8-sig', 'utf-16', 'utf-32']:
                with self.subTest(encoding=encoding, kind=value[:2]):
                    with self.assertRaises(scanner.ScanError):
                        scanner.inspect_content(('safe\x00\n' + value).encode(encoding),
                                                'blob-text', self.policy, [PRIVATE_MARKER])
        with self.assertRaisesRegex(scanner.ScanError, 'unsupported-text-encoding'):
            scanner.inspect_content(b'\xff', 'blob-text', self.policy, [PRIVATE_MARKER])

    def test_sqlite_disguised_binary(self):
        self.write('art.png', b'SQLite format 3\x00' + b'x' * 64)
        self.commit()
        with self.assertRaisesRegex(scanner.ScanError, 'sqlite-content'):
            self.scan()

    def test_secret_in_commit_and_annotated_tag(self):
        self.git('tag', '-a', 'other', '-m', SECRET)
        with self.assertRaisesRegex(scanner.ScanError, 'secret-content'):
            self.scan()
        self.git('tag', '-d', 'other')
        self.write('new.txt', b'safe')
        self.commit(SECRET)
        with self.assertRaisesRegex(scanner.ScanError, 'secret-content'):
            self.scan()

    def test_receipt_external_hash_required(self):
        _, prior = self.scan()
        with self.assertRaisesRegex(scanner.ScanError, 'receipt-hash-required'):
            self.scan(prior_path=prior[0])
        with self.assertRaisesRegex(scanner.ScanError, 'receipt-hash-mismatch'):
            self.scan((prior[0], '0' * 64))

    def test_receipt_unknown_partial_missing_duplicate_failed_entries(self):
        _, prior = self.scan()
        changes = [lambda r: r.update(schema=1), lambda r: r.update(complete=False),
                   lambda r: r['entries'].pop(),
                   lambda r: r['entries'].append(r['entries'][0]),
                   lambda r: r['entries'][0].update(result='failed'),
                   lambda r: r['contexts'].clear(), lambda r: r.update(unknown=True)]
        for change in changes:
            altered = self.altered_receipt(prior, change)
            with self.subTest(change=changes.index(change)):
                with self.assertRaises(scanner.ScanError):
                    self.scan(altered)

    def test_policy_scanner_marker_runtime_identity_invalidates(self):
        _, prior = self.scan()
        changed_policy = copy.deepcopy(self.policy)
        changed_policy['textExtensions'].append('.synthetic')
        for changes in [dict(policy=changed_policy), dict(policy_hash='0' * 64),
                        dict(markers=['different-synthetic-marker'])]:
            with self.assertRaisesRegex(scanner.ScanError, 'receipt-identity'):
                self.scan(prior, **changes)
        for key in ['scanner_sha256', 'bridge_sha256', 'runtime']:
            altered = self.altered_receipt(prior, lambda r: r['identity'].update({key: 'changed'}))
            with self.assertRaisesRegex(scanner.ScanError, 'receipt-identity'):
                self.scan(altered)

    def test_refs_head_tag_mismatch_and_unexpected_ref(self):
        _, prior = self.scan()
        for changes in [dict(expected_commit='0' * 40),
                        dict(expected_tag='refs/tags/missing'),
                        dict(expected_refs={'refs/heads/main': '0' * 40})]:
            with self.assertRaises(scanner.ScanError):
                self.scan(prior, **changes)
        before = self.refs()
        self.git('branch', 'unexpected')
        with self.assertRaisesRegex(scanner.ScanError, 'refs-mismatch'):
            self.scan(prior, expected_refs=before)
        self.write('new.txt', b'new')
        self.commit()
        self.git('tag', '-f', 'release-test', 'HEAD~1')
        with self.assertRaisesRegex(scanner.ScanError, 'tag-commit-mismatch'):
            self.scan(prior)

    def test_corrupt_git_object_rejected_even_when_cached(self):
        _, prior = self.scan()
        blob = self.git('rev-parse', 'HEAD:readme.md')
        path = self.repo / '.git' / 'objects' / blob[:2] / blob[2:]
        path.chmod(0o600)
        path.write_bytes(b'corrupt synthetic loose object')
        with self.assertRaises(scanner.ScanError):
            self.scan(prior)

    def test_grafts_alternates_shallow_replace_and_promisor_rejected(self):
        for relative in ['info/grafts', 'objects/info/alternates', 'shallow']:
            path = self.repo / '.git' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'')
            with self.assertRaises(scanner.ScanError):
                self.scan()
            path.unlink()
        self.git('config', 'remote.synthetic.promisor', 'true')
        with self.assertRaisesRegex(scanner.ScanError, 'partial-or-external-config'):
            self.scan()
        self.git('config', '--unset', 'remote.synthetic.promisor')
        self.git('update-ref', 'refs/replace/' + '1' * 40, self.git('rev-parse', 'HEAD'))
        with self.assertRaises(scanner.ScanError):
            self.scan()

    def test_output_new_only_and_no_private_paths_in_receipt(self):
        result, prior = self.scan()
        with self.assertRaisesRegex(scanner.ScanError, 'receipt-already-exists'):
            self.scan(receipt_path=prior[0])
        raw = prior[0].read_text()
        self.assertNotIn(str(self.repo), raw)
        self.assertNotIn(PRIVATE_MARKER, raw)
        self.assertNotIn('readme.md', raw)
        self.assertTrue(result['complete'])

    def test_fresh_fsck_on_warm_scan(self):
        _, prior = self.scan()
        original = scanner.Git.run
        commands = []
        def recording(git, *args, **kwargs):
            commands.append(args)
            return original(git, *args, **kwargs)
        with mock.patch.object(scanner.Git, 'run', recording):
            self.scan(prior)
        self.assertTrue(any(args[0] == 'fsck' for args in commands))
        self.assertFalse(any(args[:2] == ('cat-file', 'blob') for args in commands))

    def test_policy_source_changed_before_receipt_is_rejected(self):
        changed = self.base / 'changed-policy.ps1'
        changed.write_bytes(self.policy_path.read_bytes() + b'\n# changed\n')
        target = self.base / 'never-written.json'
        with self.assertRaisesRegex(scanner.ScanError, 'policy-changed'):
            self.scan(policy_source_path=changed, receipt_path=target)
        self.assertFalse(target.exists())

    def test_missing_marker_and_symlink_tree_entry_rejected(self):
        with self.assertRaisesRegex(scanner.ScanError, 'private-marker-required'):
            self.scan(markers=[])
        blob = self.git('hash-object', '-w', '--stdin', data=b'synthetic-link-target')
        self.git('update-index', '--add', '--cacheinfo', '120000', blob, 'link')
        self.git('commit', '-q', '-m', 'synthetic symlink')
        self.git('tag', '-f', 'release-test')
        with self.assertRaisesRegex(scanner.ScanError, 'nonregular-history-entry'):
            self.scan()

    def test_large_binary_stream_and_text_limit(self):
        target = self.repo / 'large-reference.png'
        with target.open('wb') as stream:
            for _ in range(129):
                stream.write(b'x' * (1024 * 1024))
        self.commit()
        result, prior = self.scan()
        self.assertGreater(result['metrics']['content_bytes_scanned'], 128 * 1024 * 1024)
        self.git('mv', 'large-reference.png', 'large-reference.txt')
        self.git('commit', '-q', '-m', 'synthetic text mode')
        self.git('tag', '-f', 'release-test')
        with self.assertRaisesRegex(scanner.ScanError, 'text-size-limit'):
            self.scan(prior)

    def test_static_policy_extractor_never_executes_candidate(self):
        text = self.policy_path.read_text(encoding='utf-8-sig')
        bad = self.base / 'dynamic.ps1'
        sentinel = self.base / 'should-not-exist'
        replacement = "$textExtensions = @('placeholder'); [IO.File]::WriteAllText('" + str(sentinel) + "','bad'); $other = @("
        bad.write_text(text.replace('$textExtensions = @(', replacement), encoding='utf-8')
        # Even unrelated top-level executable code must only be parsed, not executed.
        scanner.load_policy(bad, scanner.sha(bad.read_bytes()), POWERSHELL)
        self.assertFalse(sentinel.exists())
        bad.write_text(text.replace("'.dart', '.yaml'", "(Get-Date), '.yaml'"), encoding='utf-8')
        with self.assertRaisesRegex(scanner.ScanError, 'policy-bridge-failed'):
            scanner.load_policy(bad, scanner.sha(bad.read_bytes()), POWERSHELL)
        with self.assertRaisesRegex(scanner.ScanError, 'policy-source-hash'):
            scanner.load_policy(self.policy_path, '0' * 64, POWERSHELL)

    def test_cli_failure_sanitizes_paths_and_content(self):
        self.write('private.txt', (MACHINE_PATH + SECRET).encode())
        self.commit()
        refs_path = self.base / 'refs.json'
        refs_path.write_text(json.dumps(self.refs()))
        result = subprocess.run([sys.executable, str(SPEC.origin), '--repository', str(self.repo),
            '--expected-commit', self.git('rev-parse', 'HEAD'),
            '--expected-tag', 'refs/tags/release-test', '--expected-refs', str(refs_path),
            '--policy-sha256', self.policy_hash, '--powershell', POWERSHELL,
            '--receipt', str(self.base / 'failure.json')], capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 1)
        output = (result.stdout + result.stderr).decode()
        for forbidden in [SECRET, MACHINE_PATH, str(self.repo), 'private.txt']:
            self.assertNotIn(forbidden, output)
        self.assertFalse((self.base / 'failure.json').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
