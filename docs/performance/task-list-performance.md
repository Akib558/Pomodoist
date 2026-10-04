# Task list performance comparison

Measured against baseline revision `60fe887837d5754171ea23c626f8bb79c047e69c` with Flutter 3.47.0 / Dart 3.13.0. The artifacts describe the working snapshot captured before the implementation commit.

## Method

The same frozen unit/microbenchmark and widget scenarios ran before and after production edits. SHA-256 fingerprints in both JSON files verify that the executable measuring code is unchanged; the replay tool strips the added `avoid_print` lint directive and accepts the two reviewed formatting-only digests before comparison. The original artifact fingerprints remain unchanged. Fixtures contain 40 and 1000 tasks on one day, separate days, mixed timed/all-day schedules and nested branches, plus 40 visible tasks with 10000 completed metadata rows. Data construction, database seeding and test-environment setup are outside stopwatch sections. Each computational scenario uses 20 warmups and 100 measured repetitions in five sequential test processes (`--concurrency=1`). Provider ticks, real in-memory Drift queries, native-scheduler doubles and automated widget scrolling supply operation counts. These are host JIT computation timings and widget build/mount counts, not frame timings or iPhone 12 FPS.

Replay from the repository root:

```sh
python3 apps/flutter/tool/task_list_performance.py
```

The runner verifies every operation gate, unchanged measurement fingerprints, and rejects a median timing regression above 10%. It retains all raw samples, p95, min/max, the range of run medians, SDK and source/diff metadata in JSON. The original baseline is never overwritten.

## Operation gates

| Scenario | Before | After | Change |
|---|---:|---:|---:|
| Upcoming: 10 unchanged seconds | 10 | 0 | -100.0% |
| ID accesses: 1000 separate days | 2,015,000 | 17,000 | -99.2% |
| Completion reads: chain of 1000 | 499,500 | 999 | -99.8% |
| New task instances: one update in 1000 | 1,000 | 1 | -99.9% |
| Other card builds: one title update | 39 | 0 | -100.0% |
| 40 unchanged future reminders rescheduled | 40 | 0 | -100.0% |
| Initial productivity task SELECTs | 5 | 1 | -80.0% |
| Task rows read by initial productivity | 200 | 40 | -80.0% |
| Initial mounted cards: 1000 same day, 390×844 | 1,000 | 8 | -99.2% |
| Initial mounted cards: 1000 separate days, 390×844 | 1,000 | 6 | -99.4% |

The operation gates passed in all five runs. The widget scenarios automatically reached the final task on both one-day and separate-day datasets. Final mounted counts remained bounded (12 and 8 respectively). Today and Inbox have separate widget assertions that changing one title never rebuilds another card. Calendar day rollover has a unit assertion; stable timed statuses retain their second-resolution ticker subscriptions. Schedule-getter counters are not JSON-decode counters after memoization; a separate identity test verifies one parsed schedule per immutable task.

## Computation timings

Median is the median of five run medians; p95 combines the 500 measured samples. Ranges below show minimum/maximum run medians, in milliseconds.

| Scenario | Before median / p95 (ms) | After median / p95 (ms) | Median change | Before → after median range (ms) |
|---|---:|---:|---:|---|
| one_day_40 | 0.339 / 0.693 | 0.155 / 0.261 | -54.2% | 0.322–0.354 → 0.151–0.177 |
| different_days_40 | 0.326 / 0.769 | 0.186 / 0.383 | -42.9% | 0.322–0.370 → 0.155–0.204 |
| mixed_40 | 0.197 / 0.337 | 0.103 / 0.169 | -47.7% | 0.194–0.201 → 0.093–0.109 |
| progress_chain_40 | 0.062 / 0.095 | 0.032 / 0.075 | -48.4% | 0.060–0.066 → 0.030–0.034 |
| history_10000 | 0.720 / 1.047 | 0.687 / 0.894 | -4.6% | 0.696–0.742 → 0.678–0.700 |
| one_day_1000 | 3.044 / 4.337 | 1.214 / 1.375 | -60.1% | 2.912–3.282 → 1.191–1.253 |
| different_days_1000 | 84.938 / 98.050 | 1.401 / 1.619 | -98.4% | 84.358–88.656 → 1.376–1.430 |
| mixed_1000 | 4.215 / 5.019 | 1.613 / 1.820 | -61.7% | 4.034–4.446 → 1.607–1.652 |
| progress_chain_1000 | 36.297 / 41.055 | 0.495 / 0.576 | -98.6% | 35.505–37.824 → 0.479–0.533 |

The one-day, separate-day, mixed and chain improvements are reproducible across the five run medians. The small change in first projection with 10000 completed metadata rows overlaps the run ranges, so it is not presented as a demonstrated timing improvement. A separate unit check confirms that subsequent projections of that same snapshot reuse its metadata index instead of rescanning all completed rows. No measured median regressed by more than 10%.

## Behavior and validation

Automated checks cover loading/error/empty states, open/completed stream precedence, selected and synthetic dates, route push/pop and scrolling, ordinary refreshes without repeated scrolling, date moves, Completion/Undo, logical offscreen selection and bulk priority for 1000 tasks, collapsed descendants and disclosure, Quick Add draft/focus, long titles at 200% text scale, RTL, both themes, Reduce Motion, widths 390/760/1280, row actions and time boundaries. Unit checks cover ordering, cross-day hierarchy, duplicates, cycles (including comparison against the original safe traversal for 100 generated malformed graphs), editing-right changes, snapshot cache eviction, midnight updates, pending notification disappearance/restart, language/title/time changes, failures and serialized retries.

Independent review found a stale progress fallback when the last unscheduled child disappeared. Its widget regression was observed failing, then passed after treating empty live progress as authoritative. Final review found no material remaining issues.

Final consolidated validation: **269 tests passed** across the agreed unit/widget set, including the existing interaction controls suite. The five frozen computation runs add 75 successful test executions, and the frozen widget run adds 5. Pinned-SDK `flutter analyze --no-pub` reports **No issues found**; Dart/Flutter MCP analysis also reports no errors. No commits, builds, dependency additions, app/device launches or manual UI actions were performed.

## Remaining costs

- Drift still rereads broad task snapshots after a relevant table change: the 1000-task update scenario still returns 1000, 0, 1000 task rows across coalesced queries. Object reuse reduces decoding/identity churn, not SQL row transfer.
- The initial 40-row projection with 10000 completed metadata rows still builds an index of that full snapshot (10600 instrumented ID accesses including projection). Later projections reuse the index.
- Ancestor breadcrumb construction depends on visible ancestry depth. Invalid cyclic subtrees retain the original safe traversal and may still cost quadratic work; ordinary acyclic progress is linear.
- Scrolling eventually builds rows that enter the viewport. Virtualization bounds mounted UI; it does not discard the complete logical task projection used for selection.
- Native pending notification IDs are still queried for every reconciliation, and reminder capacity is refreshed; successful unchanged task reminders are skipped.
- Painting, rasterization, device memory, thermal behavior and actual iPhone 12 frame rate were not measured. No app/device/manual runs were performed.

Artifacts: [baseline JSON](task-list-before.json), [optimized JSON](task-list-after.json), [implementation ledger](task-list-ledger.md).
