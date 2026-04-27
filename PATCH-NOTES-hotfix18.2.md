# HNC hotfix18.2 patch notes

- Harden `json_set_batch.sh` by replacing its regex JSON editor with a serial wrapper around the hotfix18.0/18.1 safe `json_set.sh device` writer.
- Unify batch writes onto the existing json lock path.
- Prevent values containing comma, right brace, escaped quote, or backslash from corrupting `rules.json`.
- Version: `v5.1.0-rc1-hotfix18.2`, `versionCode=509182`.
