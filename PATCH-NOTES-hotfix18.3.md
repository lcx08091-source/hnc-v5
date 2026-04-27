# HNC hotfix18.3 patch notes

- Add `bin/json_guard.sh`, a dependency-free JSON syntax validator for Android shell environments.
- Wrap `json_set.sh` commits with write-after-validate checks.
- Keep timestamped backups under `/data/local/hnc/data/.json_backups` before replacing live JSON files.
- Roll back automatically if post-write validation fails.
- Apply the guard to `rules.json`, `device_names.json`, `templates.json`, and `remote_tokens.json` writes touched by `json_set.sh`.
- Version: `v5.1.0-rc1-hotfix18.3`, `versionCode=509183`.
