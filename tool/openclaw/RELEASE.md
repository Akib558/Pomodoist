# OpenClaw 1.0.0 release preparation

The integration is complete and locally verified in this checkout. **The ClawHub
package, the server migration, and the website changes are not yet released**, so
no public availability can be claimed. The remaining gates are listed at the end.

## Prepared artifacts

- `tool/openclaw/skills/pomodoist/`: standalone skill 1.0.0 with `SKILL.md`,
  bundled `scripts/configure.mjs` and an MIT-0 `LICENSE`. Installing it requires
  no repository checkout and no JavaScript dependency installation. The
  application, server and remaining repository code stay AGPL-3.0-only.
- `tool/openclaw/configure.mjs`: source-checkout compatibility wrapper that
  re-exports and runs the bundled script. Preview stays the default; writes and
  configuration changes require the matching flags.
- `tool/openclaw/*.test.mjs`: setup and action-planning tests, run in CI by
  `.github/workflows/selfhost.yml`.
- `server/supabase/migrations/20260927125910_pomodoist_core_account_delete_calendar_guard.sql`:
  guards account deletion against the Google Calendar trigger recreating child
  state. It runs after the frozen baseline in the normal migration chain; see
  [`server/database/README.md`](../../server/database/README.md#account-deletion).
- `server/tests/openclaw-smoke.mjs` and `server/tests/openclaw-native.mjs`:
  local HTTP and native CLI acceptance. Targets only the loopback `:55421` stack
  and synthetic accounts.
- Companion `pomodoist-landing` changes: `/agents/#openclaw` cloud and
  self-hosted setup, disconnect instructions, current Focus capabilities,
  discovery metadata and regenerated articles in all seven existing languages.
  The website's generic MCP skill stays separate from the ClawHub package.

## Licensing boundary

ClawHub distributes the skill under MIT-0, does not sell skills, and requires
disclosing the terms of an external paid service. The split is therefore explicit:

| Artifact | License |
| --- | --- |
| `tool/openclaw/skills/pomodoist/` (SKILL.md, configure.mjs, LICENSE) | MIT-0 |
| Application, server, other repository code | AGPL-3.0-only |

The skill itself is free. Hosted Pomodoist service access follows the account
plan and is documented in [README.md](README.md) and `LICENSING.md`, next to the
install instructions, so a ClawHub visitor sees the paid-service terms before
connecting. Do not describe the paid service as a paid skill.

## Verified locally in this checkout

The table below records the earlier preparation run; it is historical evidence,
not a claim that every check has been repeated after subsequent edits. The review
follow-up results are recorded separately below. Nothing was published, committed,
deployed or announced.

| Check | Result and scope |
| --- | --- |
| Node setup/planner tests | 17 passed, including incompatible CLI, configuration errors, tool filters, endpoint collision and execution from a copied standalone package. |
| Deno server suite | 336 passed across 70 steps. |
| pgTAP | 614 tests across 22 files passed on the fresh local stack, including the account-deletion guard. |
| Baseline provisioning | `baseline_check.py` passed: legacy upgrade, retry idempotency, checksum rejection, and fresh install matching the upgraded schema. |
| Self-hosted smoke | Registration, login, sync round-trip, anonymous denial and tenant isolation passed. |
| OpenClaw HTTP acceptance | Passed: OAuth DCR/PKCE, MCP tools, task sync, idempotency, synchronized Focus, refresh and revocation. |
| Public boundary and whitespace | `tool/test_public_boundary.sh` and `git diff --check` passed. |

The HTTP acceptance test exercises public OAuth registration and PKCE, wrong
verifier and code-reuse rejection, consent isolation, task scheduling and
deadlines, two independent OAuth clients, app sync push/pull, mutation replay and
argument mismatch, synchronized 25-minute Focus start/pause/resume/stop, stale
Focus conflicts, refresh-token client binding, revocation and denied receipt
replay. It uses synthetic accounts that it removes afterwards.

## Native CLI acceptance

The setup-script path in `server/tests/openclaw-native.mjs` now resolves to
`tool/openclaw/configure.mjs`. On 2026-09-27, the corrected test passed with the
installed OpenClaw 2026.9.4 (3a9d69d): setup, HTTP consent, OAuth credential
storage, probe, server revocation, local logout and disabling the connection.
OpenClaw's `size-drop` guard rejected optional removal of the disabled entry;
the test verified that the rejected write preserved the configuration.

The review used a fresh `pomodoist-selfhost-review` stack with generated test
credentials and port 55422 to avoid the existing local instance on 55421.
Only the temporary test copies changed the allowed port from 55421 to 55422;
the repository scripts retain their loopback-only 55421 restriction. Native
configuration and credentials were isolated; no network guard was disabled.
The earlier claim that loopback native acceptance cannot pass was not reproduced
and is not a current release blocker. This local result does not prove production
OAuth, client compatibility across all OpenClaw versions, or ClawHub installation.

## Review follow-up verification (2026-09-27)

- Node setup/planner tests: 17 passed.
- Deno functions and contracts: 336 passed, including 70 steps.
- Disposable baseline check: legacy upgrade, migration rollback, idempotency,
  checksum rejection, fresh-install parity, data restoration and 614 pgTAP
  assertions across 22 files passed. The active-ledger assertion failed against
  the pending-directory runner before the fix and passed after it.
- Fresh review stack: registration, login, sync isolation and OpenClaw HTTP
  acceptance passed, including OAuth/PKCE, tasks, Focus, replay, refresh and revocation.
- The installed ledger contains only the six active migrations. The pending
  client batch limits are not installed.
- Native acceptance: passed within the scope described above.
- Stock `backup.sh` and `restore.sh`: passed on the fresh review stack; the
  auth-user count and synchronized-row checksum matched after restoration.
  CI now exercises these scripts in addition to the baseline's restore check.
- Public-boundary and whitespace checks passed.

The existing local database already contains the two unreleased pending ledger
entries. Its data, schema and ledger were left unchanged; verification used
separate disposable databases. See the database recovery note before updating
an instance with those entries.

## Acceptance evidence

All checks used CLI, HTTP or automated tests. No Computer Use, browser
interaction, screenshots or visual checks were performed.

| Check | Result and scope |
| --- | --- |
| Website | 89 tests and production build passed; generated content and discovery digest checked. |
| ClawHub publication dry run | `ok: true`, `status: would-publish`, three files, version 1.0.0, no existing version. Nothing uploaded. |
| Production HTTP | Protected-resource discovery and issuer discovery returned 200; the MCP endpoint returned 401 without authentication. Resource/issuer match and PKCE S256 advertisement verified. |

ClawHub dry-run fingerprint:
`85f12108c1346cc533a00df985fc79959e9740666b30a2236fe51bcb4ba77ec2`.
This is ClawHub's package fingerprint, not the website skill's SHA-256.

## Remaining release gates

1. Apply `server/supabase/migrations/20260927125910_pomodoist_core_account_delete_calendar_guard.sql`
   through the existing public-core release route and hosted staging →
   production workflow. The unguarded trigger is present in
   `server/supabase/migrations/20260922162731_pomodoist_initial.sql`; the new
   migration must be applied once. Its fresh timestamp places it after the
   frozen baseline and existing forward migrations. Do not replay already-installed
   migrations or modify the frozen initial migration. The hosted platform consumes
   a tagged public core through its pin; update the pin, require successful staging
   for the exact commit and promote that commit. No direct production SQL shortcut.

   Pending SQL is excluded from the normal runner. The client batch limits remain
   gated on publication of compatible clients. Instances that ran the unreleased
   pending-directory runner must follow the recovery note in
   [`server/database/README.md`](../../server/database/README.md#pending-release-gated-migrations);
   do not erase their ledger entries to force migration or backup checks to pass.
2. Deploy the companion landing changes through their existing release route.
   The website must not advertise OpenClaw availability before this lands.
3. Publish the skill on ClawHub and verify installation in a clean directory.
4. With an explicitly available production test connection, repeat authorized
   OAuth, read, write, Focus, replay and revocation acceptance — or keep the
   production-account limitation in the release notes.
5. Post the community announcement only after those checks pass.

## Reproduce locally

```sh
node --experimental-strip-types --test tool/openclaw/*.test.mjs
deno test --config server/supabase/deno.json --allow-env --allow-net --allow-read server/supabase/functions
make -C server setup core-up
make -C server test-db test-smoke test-openclaw
sh tool/test_public_boundary.sh
git diff --check
```

`make -C server test-openclaw-native` is listed separately because it requires
a compatible OpenClaw CLI; see the native acceptance scope above.

The HTTP test refuses non-loopback endpoints and ports other than 55421, creates
synthetic accounts and removes them. The native test script needs OpenClaw 2026.9.3 or newer
on `PATH` (or `OPENCLAW_TEST_BIN`), isolates its configuration and credential
store, and completes consent over HTTP — no browser, Computer Use or manual
interaction. Do not point these tests at a shared or production instance.

## ClawHub publication and installation

Publication is a separate release action, run from this checkout:

```sh
clawhub login
clawhub skill publish "$PWD/tool/openclaw/skills/pomodoist" --slug pomodoist --name Pomodoist --version 1.0.0 --dry-run --json
# Only in the approved publication step:
clawhub skill publish "$PWD/tool/openclaw/skills/pomodoist" --slug pomodoist --name Pomodoist --version 1.0.0
```

The publication unit is only `tool/openclaw/skills/pomodoist/`. Publish it, wait
for registry processing, then verify a clean install:

```sh
verify_dir=$(mktemp -d)
clawhub install pomodoist --version 1.0.0 --workdir "$verify_dir"
node "$verify_dir/skills/pomodoist/scripts/configure.mjs" https://mcp.pomodoist.com/functions/v1/pomodoist-mcp
```

Record the public card, owner, installed version and included files, and compare
them to the reviewed package. A registry scan, account permission or slug conflict
must be resolved before announcing availability. Do not advertise an install
command before it succeeds.

## Community announcement

The official OpenClaw Showcase recommends Discord `#self-promotion` or mentioning
`@openclaw` on X. Attach the verified ClawHub install link and a short
demonstration. A generic task-list integration already appears in the official
Showcase, including Todoist; lead with the synchronized Focus session instead.

Demonstration sequence:

1. "Show today's tasks."
2. "Move report preparation to tomorrow at 10:00."
3. "Start a 25-minute focus session on that task."
4. Show the result in Pomodoist.

Draft, to send only after release verification:

> Pomodoist now works with OpenClaw 🦞
> Manage tasks, projects and deadlines, and start synchronized Pomodoro sessions
> through your assistant. Connect with browser OAuth and revoke access anytime.
> Supports Pomodoist Cloud and self-hosted instances.
> Setup: https://pomodoist.com/agents/#openclaw
> Built by the Pomodoist maintainer — feedback welcome!

Answer questions about tasks, OAuth and self-hosting in the community, publish
reproducible scenarios, and return with fixes from feedback. Automated
cross-posting of one identical announcement hurts more than it helps here. Track
per-link clicks, successful connections, the first completed command and reuse
after one week; the first ten successful connections tell you more than an
impression count.
