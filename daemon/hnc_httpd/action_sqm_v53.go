package main

import "strings"

// actionSQMSet · v5.3.0-rc2
// params:
//
//	mode    optional: off | fq_codel | cake | auto | game
//	profile optional: balanced | game | bulk | custom
//	apply   optional: true/false, whether to ask tc_manager restore to rebuild leaves
//
// The shell manager performs the actual persistence so Go, KSU WebUI and adb
// diagnostics keep identical semantics. Invalid values are rejected before shell.
func actionSQMSet(hncDir string, p map[string]string) actionResp {
	mode := strings.TrimSpace(strings.ToLower(p["mode"]))
	profile := strings.TrimSpace(strings.ToLower(p["profile"]))
	apply := strings.TrimSpace(strings.ToLower(p["apply"]))

	if mode == "" && profile == "" && apply == "" {
		return actionResp{OK: false, Error: "bad params", Detail: "one of mode/profile/apply is required"}
	}

	details := []string{}
	if mode != "" {
		switch mode {
		case "off", "fq_codel", "fq-codel", "fqcodel", "cake", "auto", "game":
		default:
			return actionResp{OK: false, Error: "bad params", Detail: "invalid sqm mode"}
		}
		rc, out := runBin(hncDir, "sqm_manager.sh", "set-mode", mode)
		if rc != 0 {
			return actionResp{OK: false, Error: "sqm set-mode failed", Detail: strings.TrimSpace(out)}
		}
		details = append(details, "mode="+mode)
	}

	if profile != "" {
		switch profile {
		case "balanced", "game", "bulk", "custom":
		default:
			return actionResp{OK: false, Error: "bad params", Detail: "invalid sqm profile"}
		}
		rc, out := runBin(hncDir, "sqm_manager.sh", "set-profile", profile)
		if rc != 0 {
			return actionResp{OK: false, Error: "sqm set-profile failed", Detail: strings.TrimSpace(out)}
		}
		details = append(details, "profile="+profile)
	}

	switch apply {
	case "", "false", "0", "no":
		// no-op
	case "true", "1", "yes":
		rc, out := runBin(hncDir, "sqm_manager.sh", "apply")
		if rc != 0 {
			return actionResp{OK: false, Error: "sqm apply failed", Detail: strings.TrimSpace(out)}
		}
		details = append(details, "applied")
	default:
		return actionResp{OK: false, Error: "bad params", Detail: "apply must be true/false"}
	}

	return actionResp{OK: true, Detail: strings.Join(details, "; ")}
}
