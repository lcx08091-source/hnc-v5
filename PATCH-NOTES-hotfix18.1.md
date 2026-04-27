# HNC v5.1.0-rc1 hotfix18.1

## Goal

Continue the hotfix18 JSON unification track by hardening the remaining high-risk shell JSON writers without introducing a new runtime dependency.

## Fixed paths

- `json_set.sh device_remove`
  - Replaces regex object deletion with a brace/string-aware scanner.
- `json_set.sh bl_add` / `bl_del`
  - Replaces `[^]]*` blacklist manipulation with a top-level array-aware scanner.
- `json_set.sh name_set` / `name_del`
  - Uses generic object set/delete helpers for `device_names.json`.
  - Names containing comma, `}`, escaped quote, or backslash are now safe.
- `json_set.sh tpl_set` / `tpl_del`
  - Uses generic object set/delete helpers for `templates.json`.
  - Template names containing comma, `}`, escaped quote, or backslash are now safe.
- `json_set.sh device_patch`
  - No longer builds a pseudo JSON string and splits it by comma.
  - Delegates directly to the safe `device` writer for each key/value pair.

## Still deferred

- Full `hnc_json` C helper.
- Token JSON rewrite into one canonical writer.
- C-side readers such as blacklist/cache parsing.
- Stats model redesign.
