"""Reachable Git history privacy gate; independent of source/package/install gates.

Python 3.9+, Git, and PowerShell 5.1/7; no third-party modules or network calls.
The trusted policy is AST-extracted, never executed. Its full source hash must be
approved separately. This is a new cold baseline, not the lost historical scanner.
All current refs and all historical tree/path contexts are checked on every run.
Fresh fsck still reads Git objects: reuse saves policy/content decoding, not all IO.
Binary blobs receive the maintained source policy's SQLite-header check; text
extensions receive its secret/machine-path rules, plus commit/tag metadata. Text
over 128 MiB fails closed instead of the source verifier's size-based omission.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import threading
import time


class ScanError(Exception):
    """Messages are fixed reason codes, never candidate paths or content."""


def require(condition, reason):
    if not condition:
        raise ScanError(reason)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True).encode('ascii')


def json_read(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate-json-key')
            result[key] = value
        return result
    try:
        return json.loads(data, object_pairs_hook=pairs)
    except (ValueError, UnicodeError):
        raise ScanError('invalid-json') from None


def digest_ok(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def checked_file(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        require(not item.is_symlink(), 'unsafe-file-path')
        if item.exists():
            stat = item.stat()
            require(not (getattr(stat, 'st_file_attributes', 0) & 0x400),
                    'unsafe-file-path')
    require(path.is_file(), 'missing-input-file')
    return path


def load_policy(policy_path, expected_sha256, powershell):
    source = checked_file(policy_path).read_bytes()
    require(digest_ok(expected_sha256.lower()) and
            sha(source) == expected_sha256.lower(), 'policy-source-hash')
    bridge = Path(__file__).with_suffix('.ps1')
    try:
        output = subprocess.run(
            [powershell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(bridge),
             '-PolicyPath', str(policy_path)], capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        raise ScanError('policy-bridge-failed') from None
    require(output.returncode == 0, 'policy-bridge-failed')
    require(sha(checked_file(policy_path).read_bytes()) == sha(source), 'policy-changed')
    policy = json_read(output.stdout.decode('utf-8-sig'))
    bridge_runtime = policy.pop('_bridgeRuntime', None)
    require(isinstance(bridge_runtime, str) and bridge_runtime, 'policy-runtime')
    arrays = {'excludedRelativePaths', 'machinePathFixtureAllowlist',
              'textExtensions', 'trackedGeneratedPatterns'}
    patterns = {'generatedPathPattern', 'browserStatePathPattern',
                'sessionImportReceiptPathPattern', 'customIconPathPattern',
                'personalDataFilePattern', 'databaseOrSidecarPattern',
                'temporaryArtifactPattern', 'secretPattern', 'machinePathPattern'}
    require(isinstance(policy, dict) and set(policy) == arrays | patterns,
            'policy-shape')
    for name in arrays:
        require(isinstance(policy[name], list) and policy[name] and
                all(isinstance(x, str) and x for x in policy[name]), 'policy-array')
    try:
        for name in patterns:
            require(isinstance(policy[name], str) and policy[name], 'policy-pattern')
            re.compile(policy[name], re.IGNORECASE)
        for pattern in policy['trackedGeneratedPatterns']:
            re.compile(pattern, re.IGNORECASE)
    except re.error:
        raise ScanError('unsupported-policy-regex') from None
    policy['_bridgeRuntime'] = bridge_runtime
    return policy, sha(source)


class Git:
    def __init__(self, root, executable='git'):
        self.root, self.executable = str(root), executable
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_NO_REPLACE_OBJECTS='1', GIT_CONFIG_NOSYSTEM='1',
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT='0',
                        GIT_NO_LAZY_FETCH='1')

    def run(self, *args, data=None):
        try:
            output = subprocess.run(
                [self.executable, '-C', self.root, *args], env=self.env,
                input=data, capture_output=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired):
            raise ScanError('git-command-failed') from None
        require(output.returncode == 0, 'git-command-failed')
        return output.stdout

    def text(self, *args):
        try:
            return self.run(*args).decode('utf-8').strip()
        except UnicodeError:
            raise ScanError('invalid-git-text') from None


class BatchReader:
    """One Git process; bounded memory and per-object timeout, including binary IO."""

    def __init__(self, git):
        self.process = subprocess.Popen(
            [git.executable, '-C', git.root, 'cat-file', '--batch'], env=git.env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def read(self, oid, kind, size, mode, policy, markers):
        process = self.process
        timer = threading.Timer(300, process.kill)
        timer.daemon = True
        timer.start()
        try:
            process.stdin.write((oid + '\n').encode('ascii'))
            process.stdin.flush()
            header = process.stdout.readline(256)
            require(header == f'{oid} {kind} {size}\n'.encode('ascii'), 'batch-header')
            require(mode == 'blob-binary' or size <= 128 * 1024 * 1024, 'text-size-limit')
            remaining, parts, prefix = size, [], b''
            digest = hashlib.sha256()
            while remaining:
                chunk = process.stdout.read(min(1024 * 1024, remaining))
                require(bool(chunk), 'batch-truncated-object')
                remaining -= len(chunk)
                digest.update(chunk)
                if len(prefix) < 16:
                    prefix += chunk[:16 - len(prefix)]
                if mode != 'blob-binary':
                    parts.append(chunk)
            require(process.stdout.read(1) == b'\n', 'batch-trailer')
            inspect_content(prefix if mode == 'blob-binary' else b''.join(parts),
                            mode, policy, markers)
            return digest.hexdigest()
        finally:
            timer.cancel()

    def close(self):
        self.process.stdin.close()
        self.process.stdout.close()
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=10)


def inspect_refs(git, expected_commit, expected_tag, expected_refs):
    require(re.fullmatch('[0-9a-f]{40}|[0-9a-f]{64}', expected_commit) is not None,
            'expected-commit-format')
    require(isinstance(expected_refs, dict) and expected_refs, 'expected-refs-shape')
    actual = {}
    for line in git.text('for-each-ref', '--format=%(refname) %(objectname)').splitlines():
        name, oid = line.split(' ')
        actual[name] = oid
    for name, oid in expected_refs.items():
        require(isinstance(name, str) and name.startswith('refs/') and
                not name.startswith('refs/replace/') and isinstance(oid, str) and
                re.fullmatch('[0-9a-f]{40}|[0-9a-f]{64}', oid) is not None,
                'expected-refs-shape')
        git.run('check-ref-format', name)
    require(actual == expected_refs, 'refs-mismatch')
    # This release gate supports only commit-peeling refs. A direct tree/blob tag
    # would otherwise introduce path contexts outside any historical commit tree.
    for name in actual:
        try:
            git.text('rev-parse', '--verify', name + '^{commit}')
        except ScanError:
            raise ScanError('noncommit-ref-target') from None
    require(git.text('rev-parse', '--verify', 'HEAD^{commit}') == expected_commit,
            'head-mismatch')
    require(isinstance(expected_tag, str) and expected_tag.startswith('refs/tags/')
            and expected_tag in actual, 'expected-tag-missing')
    require(git.text('rev-parse', '--verify', expected_tag + '^{commit}') ==
            expected_commit, 'tag-commit-mismatch')
    return actual


def check_path(path, policy, markers):
    require(path and not path.startswith('/') and '\\' not in path and
            ':' not in path and all(p not in ('', '.', '..') for p in path.split('/')),
            'unsafe-history-path')
    require(not any(ord(c) < 32 or ord(c) == 127 for c in path), 'unsafe-history-path')
    for component in path.split('/'):
        require(component.rstrip(' .') == component and
                re.search(r'[<>"|?*]', component) is None and
                re.fullmatch(r'(?i)(?:con|prn|aux|nul|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\..*)?',
                             component) is None, 'ambiguous-windows-history-path')
    folded = path.casefold()
    require(not any(m.casefold() in folded for m in markers), 'private-history-path')
    require(folded not in {p.casefold() for p in policy['excludedRelativePaths']},
            'excluded-history-path')
    for key in ('generatedPathPattern', 'browserStatePathPattern',
                'sessionImportReceiptPathPattern', 'customIconPathPattern'):
        require(re.search(policy[key], path, re.IGNORECASE) is None, 'forbidden-history-path')
    for pattern in policy['trackedGeneratedPatterns']:
        require(re.search(pattern, path, re.IGNORECASE) is None, 'tracked-generated-path')
    for key in ('personalDataFilePattern', 'databaseOrSidecarPattern',
                'temporaryArtifactPattern'):
        require(re.search(policy[key], PurePosixPath(path).name, re.IGNORECASE) is None,
                'forbidden-history-filename')
    extension = PurePosixPath(path).suffix.lower()
    if extension not in policy['textExtensions']:
        return 'blob-binary'
    return ('blob-text-fixture' if path in policy['machinePathFixtureAllowlist']
            else 'blob-text')


def inspect_content(data, mode, policy, markers):
    require(not data.startswith(b'SQLite format 3\x00'), 'sqlite-content')
    if mode == 'blob-binary':
        return
    require(len(data) <= 128 * 1024 * 1024, 'text-size-limit')
    # Deterministic BOM handling matches source-text intent on both PS versions.
    try:
        if data.startswith((b'\xff\xfe\x00\x00', b'\x00\x00\xfe\xff')):
            text = data.decode('utf-32')
        elif data.startswith((b'\xff\xfe', b'\xfe\xff')):
            text = data.decode('utf-16')
        else:
            text = data.decode('utf-8-sig')
    except UnicodeError:
        raise ScanError('unsupported-text-encoding') from None
    folded = text.casefold()
    require(not any(m.casefold() in folded for m in markers), 'private-content')
    require(re.search(policy['secretPattern'], text, re.IGNORECASE) is None,
            'secret-content')
    if mode != 'blob-text-fixture':
        require(re.search(policy['machinePathPattern'], text, re.IGNORECASE) is None,
                'machine-path-content')


def receipt_entries(receipt, identity):
    require(isinstance(receipt, dict) and set(receipt) == {
        'schema', 'kind', 'complete', 'result', 'identity', 'refs', 'head', 'tag',
        'objects', 'contexts', 'entries', 'metrics'}, 'receipt-shape')
    require(receipt['schema'] == 2 and receipt['kind'] == 'git-object-privacy' and
            receipt['complete'] is True and receipt['result'] == 'passed', 'receipt-status')
    require(receipt['identity'] == identity, 'receipt-identity')
    require(isinstance(receipt['head'], str) and
            re.fullmatch('[0-9a-f]{40}|[0-9a-f]{64}', receipt['head']) is not None and
            isinstance(receipt['refs'], dict) and receipt['refs'] and
            isinstance(receipt['tag'], str) and receipt['tag'].startswith('refs/tags/')
            and receipt['tag'] in receipt['refs'], 'receipt-refs')
    for name, oid in receipt['refs'].items():
        require(isinstance(name, str) and name.startswith('refs/') and
                isinstance(oid, str) and
                re.fullmatch('[0-9a-f]{40}|[0-9a-f]{64}', oid) is not None,
                'receipt-refs')
    require(isinstance(receipt['objects'], dict) and
            isinstance(receipt['contexts'], list) and
            isinstance(receipt['entries'], list), 'receipt-incomplete')
    objects = receipt['objects']
    wanted = set()
    for oid, obj in objects.items():
        require(re.fullmatch('[0-9a-f]{40}|[0-9a-f]{64}', oid) is not None and
                isinstance(obj, dict) and set(obj) == {'type', 'size'} and
                obj['type'] in ('blob', 'tree', 'commit', 'tag') and
                type(obj['size']) is int and obj['size'] >= 0, 'receipt-object')
        if obj['type'] in ('commit', 'tag'):
            wanted.add((oid, 'metadata-text'))
    seen_contexts = set()
    for context in receipt['contexts']:
        require(isinstance(context, dict) and set(context) == {'oid', 'path_sha256', 'mode'}
                and digest_ok(context['path_sha256']) and context['oid'] in objects
                and objects[context['oid']]['type'] == 'blob'
                and context['mode'] in ('blob-binary', 'blob-text', 'blob-text-fixture'),
                'receipt-context')
        key = (context['oid'], context['path_sha256'], context['mode'])
        require(key not in seen_contexts, 'receipt-duplicate-context')
        seen_contexts.add(key)
        wanted.add((context['oid'], context['mode']))
    require({c['oid'] for c in receipt['contexts']} ==
            {oid for oid, obj in objects.items() if obj['type'] == 'blob'},
            'receipt-context-coverage')
    entries = {}
    for entry in receipt['entries']:
        require(isinstance(entry, dict) and set(entry) ==
                {'oid', 'mode', 'size', 'sha256', 'result'}, 'receipt-entry')
        key = (entry['oid'], entry['mode'])
        require(key in wanted and key not in entries and entry['result'] == 'passed'
                and digest_ok(entry['sha256']) and
                entry['size'] == objects[entry['oid']]['size'], 'receipt-entry')
        entries[key] = entry
    require(set(entries) == wanted, 'receipt-incomplete')
    metrics = receipt['metrics']
    require(isinstance(metrics, dict) and set(metrics) == {
        'scanned_entries', 'reused_entries', 'content_bytes_scanned',
        'content_bytes_reused', 'content_seconds', 'fsck_seconds', 'elapsed_seconds'},
        'receipt-metrics')
    require(all(type(v) in (int, float) and v >= 0 for v in metrics.values()) and
            metrics['scanned_entries'] + metrics['reused_entries'] == len(entries) and
            metrics['content_bytes_scanned'] + metrics['content_bytes_reused'] ==
            sum(e['size'] for e in entries.values()), 'receipt-metrics')
    return entries


def scan(root, expected_commit, expected_tag, expected_refs, policy, policy_hash,
         receipt_path, markers=None, prior_path=None, prior_sha256=None, git_executable='git',
         policy_source_path=None):
    started = time.monotonic()
    markers = sorted(set(m for m in (markers if markers is not None else
                         [os.environ.get('USERPROFILE', '')]) if m and m.strip()))
    require(bool(markers), 'private-marker-required')
    for ancestor in (Path(root).absolute(), *Path(root).absolute().parents):
        require(ancestor.is_dir() and not ancestor.is_symlink() and not
                (getattr(ancestor.stat(), 'st_file_attributes', 0) & 0x400),
                'unsafe-repository-path')
    git = Git(root, git_executable)
    scanner = Path(__file__)
    identity = {'scanner_sha256': sha(scanner.read_bytes()),
                'bridge_sha256': sha(scanner.with_suffix('.ps1').read_bytes()),
                'policy_source_sha256': policy_hash, 'policy_sha256': sha(canonical(policy)),
                'private_markers_sha256': sha(canonical(markers)),
                'runtime': {'python': sys.version, 'git': git.text('--version'),
                            'powershell': policy.get('_bridgeRuntime')},
                'semantics': 'reachable-history-all-contexts-v2'}
    prior = {}
    require(bool(prior_path) == bool(prior_sha256), 'receipt-hash-required')
    if prior_path:
        raw = checked_file(prior_path).read_bytes()
        require(digest_ok(prior_sha256.lower()) and sha(raw) == prior_sha256.lower(),
                'receipt-hash-mismatch')
        prior = receipt_entries(json_read(raw), identity)
    destination = Path(receipt_path).absolute()
    require(not destination.exists(), 'receipt-already-exists')
    require(destination.parent.is_dir(), 'receipt-parent-missing')
    for ancestor in (destination.parent, *destination.parent.parents):
        require(not ancestor.is_symlink() and not
                (getattr(ancestor.stat(), 'st_file_attributes', 0) & 0x400),
                'unsafe-receipt-path')
    require(git.text('rev-parse', '--is-shallow-repository') == 'false', 'shallow-history')
    for item in ('info/grafts', 'objects/info/alternates', 'shallow'):
        candidate = Path(git.text('rev-parse', '--git-path', item))
        if not candidate.is_absolute():
            candidate = Path(root) / candidate
        require(not candidate.exists(), 'external-or-rewritten-history')
    # Config absence exits 1; inspect config names instead without printing values.
    config_names = git.text('config', '--local', '--name-only', '--list').lower().splitlines()
    require(not any(n == 'extensions.partialclone' or n.endswith('.promisor')
                    or n.startswith('include.') or n.startswith('includeif.')
                    or n == 'extensions.worktreeconfig' for n in config_names),
            'partial-or-external-config')
    refs = inspect_refs(git, expected_commit, expected_tag, expected_refs)
    for name in refs:
        inspect_content(name.encode('utf-8'), 'metadata-text', policy, markers)
    fsck_started = time.monotonic()
    git.run('fsck', '--full', '--strict', '--no-reflogs')
    fsck_seconds = time.monotonic() - fsck_started
    oids = sorted(set(git.text('rev-list', '--objects', '--all', 'HEAD',
                               '--no-object-names').splitlines()))
    require(bool(oids), 'empty-history')
    rows = git.run('cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)',
                   data=('\n'.join(oids) + '\n').encode('ascii')).decode('ascii').splitlines()
    objects = {}
    for row in rows:
        parts = row.split(' ')
        require(len(parts) == 3 and parts[0] in oids and
                parts[1] in ('blob', 'tree', 'commit', 'tag') and parts[2].isdigit(),
                'invalid-object')
        objects[parts[0]] = {'type': parts[1], 'size': int(parts[2])}
    require(set(objects) == set(oids), 'missing-object')
    contexts = set()
    trees_seen = set()
    for commit, obj in objects.items():
        if obj['type'] != 'commit':
            continue
        tree = git.text('rev-parse', commit + '^{tree}')
        if tree in trees_seen:
            continue
        trees_seen.add(tree)
        paths = set()
        for row in git.run('ls-tree', '-r', '-t', '-z', '--full-tree', tree).split(b'\x00'):
            if not row:
                continue
            header, path_bytes = row.split(b'\t', 1)
            mode, kind, oid = header.decode('ascii').split(' ')
            require((mode in ('100644', '100755') and kind == 'blob') or
                    (mode == '040000' and kind == 'tree'), 'nonregular-history-entry')
            try:
                path = path_bytes.decode('utf-8')
            except UnicodeError:
                raise ScanError('invalid-history-path-encoding') from None
            require(path.casefold() not in paths, 'case-colliding-history-path')
            paths.add(path.casefold())
            scan_mode = check_path(path, policy, markers)
            if kind == 'tree':
                require(oid in objects and objects[oid]['type'] == 'tree', 'missing-tree-object')
                continue
            require(oid in objects and objects[oid]['type'] == 'blob', 'missing-tree-object')
            contexts.add((oid, sha(path_bytes), scan_mode))
    require({x[0] for x in contexts} ==
            {oid for oid, obj in objects.items() if obj['type'] == 'blob'},
            'uncontextualized-blob')
    wanted = {(oid, mode) for oid, _, mode in contexts}
    wanted.update((oid, 'metadata-text') for oid, obj in objects.items()
                  if obj['type'] in ('commit', 'tag'))
    entries, scanned_bytes, reused_bytes = [], 0, 0
    content_started = time.monotonic()
    batch = None
    try:
        for oid, mode in sorted(wanted):
            size = objects[oid]['size']
            if (oid, mode) in prior:
                entry = prior[(oid, mode)]
                require(entry['size'] == size, 'cached-object-size')
                reused_bytes += size
            else:
                if batch is None:
                    batch = BatchReader(git)
                content_hash = batch.read(oid, objects[oid]['type'], size, mode, policy, markers)
                entry = {'oid': oid, 'mode': mode, 'size': size,
                         'sha256': content_hash, 'result': 'passed'}
                scanned_bytes += size
            entries.append(entry)
    finally:
        if batch is not None:
            batch.close()
    content_seconds = time.monotonic() - content_started
    # Ref movement during the check invalidates the evidence instead of mixing states.
    inspect_refs(git, expected_commit, expected_tag, expected_refs)
    require(identity['scanner_sha256'] == sha(scanner.read_bytes()) and
            identity['bridge_sha256'] == sha(scanner.with_suffix('.ps1').read_bytes()),
            'scanner-changed')
    if policy_source_path is not None:
        require(sha(checked_file(policy_source_path).read_bytes()) == policy_hash,
                'policy-changed')
    receipt = {'schema': 2, 'kind': 'git-object-privacy', 'complete': True,
               'result': 'passed', 'identity': identity, 'refs': refs,
               'head': expected_commit, 'tag': expected_tag, 'objects': objects,
               'contexts': [{'oid': oid, 'path_sha256': path_hash, 'mode': mode}
                            for oid, path_hash, mode in sorted(contexts)],
               'entries': entries, 'metrics': {
                   'scanned_entries': sum((e['oid'], e['mode']) not in prior for e in entries),
                   'reused_entries': sum((e['oid'], e['mode']) in prior for e in entries),
                   'content_bytes_scanned': scanned_bytes, 'content_bytes_reused': reused_bytes,
                   'content_seconds': content_seconds, 'fsck_seconds': fsck_seconds,
                   'elapsed_seconds': time.monotonic() - started}}
    receipt_entries(receipt, identity)
    raw = canonical(receipt) + b'\n'
    # Atomic new-only exposure: hard link fails if evidence already exists.
    fd, temporary = tempfile.mkstemp(prefix='.git-privacy-', suffix='.partial',
                                     dir=destination.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, destination)
    finally:
        os.unlink(temporary)
    return receipt, sha(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--expected-tag', required=True, help='Full refs/tags/... name')
    parser.add_argument('--expected-refs', required=True, help='Approved exact ref-to-OID JSON object')
    parser.add_argument('--policy', default=str(Path(__file__).parents[1] / 'verify_production_source.ps1'))
    parser.add_argument('--policy-sha256', required=True)
    parser.add_argument('--powershell', default='powershell.exe')
    parser.add_argument('--git', default='git')
    parser.add_argument('--receipt', required=True)
    parser.add_argument('--prior-receipt')
    parser.add_argument('--prior-receipt-sha256')
    args = parser.parse_args()
    try:
        policy, policy_hash = load_policy(args.policy, args.policy_sha256, args.powershell)
        result, receipt_hash = scan(
            args.repository, args.expected_commit, args.expected_tag,
            json_read(checked_file(args.expected_refs).read_bytes()), policy, policy_hash,
            args.receipt, prior_path=args.prior_receipt,
            prior_sha256=args.prior_receipt_sha256, git_executable=args.git,
            policy_source_path=args.policy)
        print(json.dumps({'result': 'passed', 'receipt_sha256': receipt_hash,
                          'metrics': result['metrics']}, sort_keys=True))
        return 0
    except ScanError as error:
        print('Git object privacy failed: ' + str(error), file=sys.stderr)
        return 1
    except Exception:
        # OS/subprocess errors can contain private local paths or source content.
        print('Git object privacy failed: input-or-output-error', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
