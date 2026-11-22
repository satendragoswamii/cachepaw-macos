# CachePaw

**A cautious, scheduled cache cleaner for macOS.** CachePaw is a distinct-name derivative of [Mole](https://github.com/tw93/Mole) V1.41.0 with a conservative cleanup profile and a native `launchd` scheduler.

CachePaw keeps its default cleanup intentionally narrow: Homebrew download archives and the Python `pip` cache. It does not clear browser profiles, cookies, app settings, documents, Trash, or macOS temporary directories.

## What CachePaw adds

- **Preview by default:** `cachepaw clean` shows what it would remove. Pass `--apply` to delete the cache files.
- **Mac scheduling:** install a per-user LaunchAgent that checks daily and performs cleanup no more often than every 25 days.
- **Busy-file guard:** a cache stays untouched if a process has files open in it; the schedule retries on a later check.
- **Persistent audit trail:** cleanup actions use Mole's path validation and deletion log, under `~/Library/Logs/CachePaw`.
- **Broader review without deletion:** `cachepaw review` runs Mole's full cleanup in dry-run mode so you can inspect other candidates separately.
- **Separate project identity:** CachePaw does not replace the installed `mo` or `mole` commands.
- **Upstream update guard:** `cachepaw mole update` and `cachepaw mole remove` are blocked so the copied engine cannot overwrite or remove the separate project.

## Requirements

- macOS 12 or newer
- Bash, `launchctl`, `lsof`, and `plutil` (included with macOS)
- Homebrew and/or Python `pip` caches for the conservative cleanup to find anything

The bundled Mole analyzer and cleanup engine are from V1.41.0. CachePaw does not need the separate Mole installation on your Mac.

## Use from a checkout

```bash
./bin/cachepaw --help
./bin/cachepaw clean                 # preview the conservative cache set
./bin/cachepaw clean --apply         # remove only the listed cache data
./bin/cachepaw review                # preview Mole's broader cleanup
```

To use it from another Mac, clone this repository and run `./bin/cachepaw` from the checkout. The upstream Mole installer is retained as `install-mole-upstream.sh` and is not the CachePaw installer.

The broad upstream cleanup is available only when requested explicitly:

```bash
./bin/cachepaw mole clean --dry-run
./bin/cachepaw mole clean
```

## Schedule cleanup

Install the default 25-day schedule, checked at 10:00 local time:

```bash
./bin/cachepaw schedule install
```

Choose a different interval or time:

```bash
./bin/cachepaw schedule install --days 30 --hour 9 --minute 30
./bin/cachepaw schedule status
./bin/cachepaw schedule remove
```

The LaunchAgent runs in the current macOS user session and does not require an internet connection or an AI service subscription. If the Mac is asleep or logged out at the due time, the next available run checks the saved timestamp and catches up. `schedule remove` removes the LaunchAgent; it keeps the installed helper and its logs.

## Safety

- Manual `clean` is preview-only unless `--apply` is supplied.
- Scheduled cleanup only invokes the same two cache targets.
- The schedule checks for active file handles before deleting and records a successful-run timestamp only if no target was busy.
- Mole's path validation and operation logging are reused for deletions.
- The `schedule` command refuses to mutate launchd when `MOLE_TEST_MODE=1` or `MOLE_TEST_NO_AUTH=1` is set.

## Upstream and license

CachePaw is based on [tw93/Mole V1.41.0](https://github.com/tw93/Mole/tree/V1.41.0), licensed under MIT. The original Mole copyright and license are preserved in [`LICENSE`](LICENSE). CachePaw is an independent project and is not affiliated with or endorsed by Mole's maintainers.

The upstream source has changed since V1.41.0. This repository preserves the license attached to the exact version used as its base; review the upstream license before incorporating newer Mole versions.
