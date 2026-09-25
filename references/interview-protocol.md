# Interview Protocol — ui-tuning-lab

Run before any scaffold. No scaffold without valid lab.json + baseline.

## Tool

- Use AskUserQuestion tool. Chat fallback only if tool unavailable.
- Write answers to lab.json. Validate before proceeding.

## STOP Guard

> STOP: do not scaffold without valid lab.json + baseline. Missing or invalid answers = stop, re-ask.

## Batching

- Call 1: Q0–Q3.
- Call 2: Q4–Q6.
- Q7 separate. Require explicit confirm.

## Questions

- Q0 lab-target: feature (Recommended) / container / both-sequenced. Pick one.
- Q1 scope: multi-select. animation / layout / appearance / logic.
- Q2 container: lightest host rendering target. Recommended-first. State exact host.
- Q3 persist: none / session / namespaced-save. Default none.
- Q4 profiles: Single / Multi. Name each profile.
- Q5 next-build: DEBUG build + tester gate. Confirm available.
- Q6 generic-saver: reuse shared saver? yes / no. If no, define saver now.
- Q7 shared-understanding: confirm labTarget + scope + container + persist + profiles. Require yes.

## Findings Format

Emit exactly:

```
## Interview findings: ui-tuning-lab
- labTarget:
- scope:
- container:
- persist:
- profiles:
- next-build:
- saver:
- confirmed: yes/no
```
