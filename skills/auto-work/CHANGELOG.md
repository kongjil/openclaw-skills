# Changelog

## Unreleased

### Changes
- Add `auto-work` as a unified entry skill for watchdog + execution workflows.
- Split internal policy into `references/` docs for modes, evidence, watchdog, execution, recovery, and risk gates.
- Add user-facing README, FAQ, and examples for trigger phrases, blocking cases, and completion flow.

### Fixes
- Clarify that watchdog reminders must close the loop to a new action, continuation, or explicit blocker.
- Clarify that execution mode requires a real execution path, not just a reminder cron.
- Clarify that high-risk actions stop at confirmation instead of auto-running.
