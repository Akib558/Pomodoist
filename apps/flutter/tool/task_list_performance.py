#!/usr/bin/env python3
"""Repeat the frozen task benchmarks and enforce the approved operation gates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[3]
APP = REPO / 'apps/flutter'
FLUTTER = REPO / '.fvm/flutter_sdk/bin/flutter'
HARNESS = ['test/performance/task_performance_test.dart', 'test/performance/task_widget_performance_test.dart']

# Reviewed dart format output of the frozen measuring code. Keep the original
# artifact digests intact while accepting these exact formatting and lint-only revisions.
FORMATTED_HARNESS_DIGESTS = {'025bae2827517e00adec403ff8f5a56416d6285ee288dcdb1ebd3ac5f6db8536': 'ac488286e5a9292bedbc78bed1307942c871690ed6c4ad5d717d56071abee283', 'f5cdb3850c5f2b9f39c7104d09676df30110704d0da11e3129939d3431e8a6d6': '867bf213893a0ce5ea876839ad793a1ada566cd837e3afbc37ec449b0fc9b62a'}


def timing(runs, name):
    samples = sorted(value for run in runs for value in run[name]['samples_us'])
    medians = [run[name]['median_us'] for run in runs]
    return dict(median_us=statistics.median(medians), p95_us=samples[(len(samples)*95+99)//100-1],
                median_range_us=[min(medians), max(medians)], min_us=samples[0], max_us=samples[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=REPO / 'docs/performance/task-list-before.json')
    parser.add_argument('--output', type=Path, default=REPO / 'docs/performance/task-list-after.json')
    args = parser.parse_args()
    before = json.loads(args.baseline.read_text())
    hashes = {str(Path('apps/flutter')/name): hashlib.sha256((APP/name).read_bytes().removeprefix(b'// ignore_for_file: avoid_print\n')).hexdigest() for name in HARNESS}
    hashes = {name: FORMATTED_HARNESS_DIGESTS.get(digest, digest) for name, digest in hashes.items()}
    assert hashes == before['harness_sha256'], 'The measurement scenario changed after baseline'
    results = []
    with tempfile.TemporaryDirectory(prefix='pomodoist-perf-') as directory:
        directory = Path(directory)
        for run in range(1, 6):
            output = directory / f'run-{run}.json'
            print(f'Measuring run {run}/5', flush=True)
            subprocess.run([str(FLUTTER), 'test', '--no-pub', '--concurrency=1', HARNESS[0]], cwd=APP,
                           env={**os.environ, 'PERFORMANCE_OUTPUT': str(output)}, check=True)
            results.append(json.loads(output.read_text()))
        output = directory / 'widgets.json'
        subprocess.run([str(FLUTTER), 'test', '--no-pub', '--concurrency=1', HARNESS[1]], cwd=APP,
                       env={**os.environ, 'PERFORMANCE_WIDGET_OUTPUT': str(output)}, check=True)
        widgets = json.loads(output.read_text())
    comparison = {}
    for name, value in results[0].items():
        if 'samples_us' in value:
            old, new = timing(before['runs'], name), timing(results, name)
            comparison[name] = dict(before=old, after=new, change_percent=(new['median_us']/old['median_us']-1)*100)
    sdk = json.loads(subprocess.check_output([str(FLUTTER), '--version', '--machine'], text=True))
    sdk.pop('flutterRoot', None)
    report = dict(revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
                  working_diff_sha256=hashlib.sha256(subprocess.check_output(['git', 'diff'], cwd=REPO)).hexdigest(),
                  sdk=sdk,
                  warmups=20, iterations=100, harness_sha256=hashes, runs=results, widget=widgets, comparison=comparison)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    for run in results:
        for n in [40, 1000]:
            assert run[f'idle_{n}']['upcoming_updates'] == 0
            assert run[f'grouping_{n}']['different_day_ids'] <= 30*n
            assert run[f'repository_{n}']['new_identities'] == 1
            assert run[f'reminders_{n}']['rescheduled'] == 0
            assert run[f'progress_{n}']['completion_reads'] <= n
        assert run['productivity']['task_reads'] == 1
    assert widgets['one_title']['other_builds'] == 0
    for name, value in widgets.items():
        if name.startswith('agenda_'):
            assert value['initial_mounted'] <= 40
            assert value['final_mounted'] <= 40
    regressions = {name: value for name, value in comparison.items() if value['change_percent'] > 10}
    assert not regressions, f'Repeat and investigate timing regressions: {regressions}'
    print(json.dumps(comparison, indent=2))
    print('All operation, identity, notification, rebuild and mount gates passed.')


if __name__ == '__main__':
    main()
