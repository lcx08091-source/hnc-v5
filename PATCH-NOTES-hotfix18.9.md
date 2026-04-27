# HNC v5.1.0-rc1 hotfix18.9

## JSON unification bootstrap

This hotfix introduces the first stable JSON helper contract:

- `bin/hnc_json validate <file>`
- `bin/hnc_json get-top <file> <key>`
- `bin/hnc_json set-top <file> <key> <value> [type]`
- `bin/hnc_json version`

The runtime `bin/hnc_json` is a conservative shell frontend. `validate` and
`get-top` are implemented locally; `set-top` delegates to the already hardened
`json_set.sh top` from hotfix18.0+ and then validates the result.

A small C prototype is added at:

- `daemon/hotspotd/tools/hnc_json.c`
- `daemon/hotspotd/tools/build_hnc_json.sh`

The C prototype is not yet wired into the module runtime. It is the foundation
for the next JSON-unification phase, where the shell frontend can be replaced by
a compiled helper after device-side validation.

## Why this is intentionally incremental

hotfix18.0-18.8 hardened existing writers, added rollback, diagnostics and CI
checks. hotfix18.9 adds a single command contract without replacing all callers
at once, reducing risk while preparing the larger hnc_json migration.
