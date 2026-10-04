# Task list performance implementation ledger

Baseline revision: `60fe887837d5754171ea23c626f8bb79c047e69c`.

- Work stays on main, without commits, device runs, manual checks or new dependencies.
- Saved the baseline before changing production code: five sequential runs, 20 warmups and 100 measured iterations, plus automated widget build/mount/scroll counts.
- RED → GREEN: schedule identity and null caching, day grouping budget, linear nested progress, and disappearance of the last unscheduled child.
- Completed data changes: local-day subscription, per-instance schedule memoization, per-snapshot metadata index, bottom-up progress with safe cyclic fallback, per-stream immutable-row reuse, summary from watched snapshots.
- Completed UI changes: structural parent selectors, task-ID card subscriptions, separate current logical selection, one lazy agenda sliver across all days, measured post-layout selected-day scrolling.
- Completed reminder reconciliation: serialized updates; signatures cache only successful scheduling and require actual native pending IDs.
- Behavior checks cover offscreen bulk priority for 1000 rows, collapsed descendants, Completion/Undo, Quick Add draft/focus, route query and scroll preservation, RTL/200% text/both themes/Reduce Motion at 390/760/1280 px. Existing interaction tests additionally cover gestures, context menus and actual detail navigation.
- Fresh independent review found stale progress fallback; a failing regression was reproduced and fixed. Final review found no material remaining issues.
- Five final benchmark runs passed all operation gates. Reproducible computational improvements are reported with p95 and run ranges; the small first-history-projection timing change is not claimed as demonstrated improvement.

Ruling: use the existing Flutter test runner for deterministic UI measurements; host timings do not establish device FPS.

Ruling: frozen benchmark log printing requires an `avoid_print` lint directive. The fingerprint strips that exact directive only; all executable measuring code remains byte-for-byte identical to the saved baseline. No measurements or workload parameters changed.

Ruling: retain the full-state parent subscription only for arbitrary external task filters, which may inspect content; other list parents select structure. The rows still observe their own task IDs, progress and ancestor path.

Ruling: use a simple ConsumerWidget for live rows. Flutter's structural selection already avoids unrelated title rebuilds; an extra widget cache was removed.

Final verification: 269 consolidated tests passed; 5 × 15 frozen computation cases and 5 frozen widget cases passed; pinned SDK static analysis has no issues; main and HEAD are unchanged. Results and residual costs are recorded in task-list-performance.md.
