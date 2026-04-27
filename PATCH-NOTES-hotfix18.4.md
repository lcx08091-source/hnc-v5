# HNC hotfix18.4 patch notes

- Add `bin/json_doctor.sh` as a JSON health and recovery entry point.
- `json_doctor.sh status` writes `/data/local/hnc/run/json_health.json` and `json_health.txt`.
- `json_doctor.sh list` lists timestamped backups under `.json_backups`.
- `json_doctor.sh restore <file>` restores the latest valid backup for one managed JSON file.
- `json_doctor.sh repair` restores invalid managed JSON files from latest valid backups.
- Default mode is read-only; live files are only changed by explicit restore/repair.
- Version: `v5.1.0-rc1-hotfix18.4`, `versionCode=509184`.
