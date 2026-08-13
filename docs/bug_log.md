# Bug Log

Every entry: symptom → root cause → waveform evidence → fix → re-verification.

| # | Date | Found by (test/assertion) | Symptom | Root cause | Fix commit | Re-verified |
|---|------|---------------------------|---------|------------|------------|-------------|
| – | – | – | – | – | – | – |

## Injected-bug hunt (W16, planned)

5 bugs to inject: overflow-guard removal, off-by-one in load counter, missing reset on one PE, sign-extension error, handshake data-stability violation. Record time-to-detection and which layer (scoreboard / SVA / coverage hole) caught each.
