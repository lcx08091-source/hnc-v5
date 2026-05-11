// middleware.go — Patch 2.b auth + rate-limit middleware (v4_0_design_v2.1 §4)
//
// 请求流程:
//   accessLog → (若 public path) unauthRateLimit → handler
//              → (若 protected) authMiddleware → handler
//
// authMiddleware:
//   1. public 路径直接放行(/pair, /api/pair/verify, /static/*)
//   2. 读 cookie hnc_token,无则 302 /pair(或 API 401)
//   3. VerifyCookie → O(1) 查 tokens + 单次 bcrypt
//   4. 失败 → 清 cookie(MaxAge=-1 + Expires=1970 双保险) + 302/401
//   5. 成功 → 更新 last_seen + 把 TokenID 塞进 context + 放行
//
// remote_auth_required 开关(v2.1 §10.3):
//   rules.json.remote_auth_required=false 时, 无 cookie 也放行(过渡期友好)
//   true 时强制鉴权(Patch 3 会强升 true)
//   2.b 默认 false, 用户 opt-in 启用

package main

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ctxKey context 里存 Token 信息的 key
type ctxKey int

const (
	ctxKeyTokenID ctxKey = iota
	ctxKeyToken
)

// CookieName hnc token cookie 名字
const CookieName = "hnc_token"

// isPublicPath 不需要 auth 的路径
func isPublicPath(p string) bool {
	if p == "/pair" || p == "/api/pair/verify" || p == "/api/health" || p == "/api/pairing/status" {
		return true
	}
	if strings.HasPrefix(p, "/static/") {
		return true
	}
	return false
}

// readAuthRequired 读 rules.json.auth_required
// rc3.1.13: config.json 已弃用 (post-fs-data.sh 启动时单向迁移并删除),
// 字段单源化在 rules.json. rc3.1.9~12 的 P0 故事:
//
//	原本 middleware 读 remote_auth_required (rc3.1.9 改 auth_required),
//	但前端 toggle 走 cfg_set 实际写 config.json (rc3.1.12 加 config 覆盖兜底),
//	两次都是"对齐读法"不是治本. 真正的治本是字段单源, 这就是 rc3.1.13.
//
// rc3.1.13.1 (review §2 P1): I/O / 解析 / 类型错误一律 fail-closed (return true 强制鉴权)
//
//	并打 log. 之前 fail-open 在 toggle 已 ON 用户那里, 偶发文件错误瞬间会
//	短暂打开匿名读权限. 安全方向以"出错时严"为正.
func readAuthRequired(hncDir string) bool {
	data, err := os.ReadFile(filepath.Join(hncDir, "data", "rules.json"))
	if err != nil {
		log.Printf("readAuthRequired: read rules.json failed, fail-closed: %v", err)
		return true
	}
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		log.Printf("readAuthRequired: parse rules.json failed, fail-closed: %v", err)
		return true
	}
	v, ok := raw["auth_required"].(bool)
	if !ok {
		// hotfix17.8: 字段缺失/非 bool 视为配置损坏, fail-closed。
		// 全新安装由 post-fs-data.sh 写入显式 auth_required:false, 不应走到这里。
		log.Printf("readAuthRequired: auth_required missing/non-bool, fail-closed")
		return true
	}
	return v
}

// clearCookie 构造一个清除 hnc_token 的 Cookie
// Gemini v2 审查 3.1: MaxAge=-1 + Expires=time.Unix(0,0) 双保险
func clearCookie() *http.Cookie {
	return &http.Cookie{
		Name:     CookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		Expires:  time.Unix(0, 0),
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
	}
}

// issuedCookie 构造一个 30 天有效期的 hnc_token cookie
func issuedCookie(value string) *http.Cookie {
	return &http.Cookie{
		Name:     CookieName,
		Value:    value,
		Path:     "/",
		MaxAge:   30 * 86400, // 30 天
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
	}
}

// authMiddleware 要求请求带合法 token,否则 redirect/401
func (s *server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isPublicPath(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}

		// v5.0 loopback bypass: 本地 KSU WebUI 走 loopback 不需要鉴权
		// 热点段的远程访问仍然需要 PIN + cookie
		// rc3 修 N-6: 防 DNS rebinding · 浏览器 fetch 必带 Origin/Referer,
		// ksu.exec curl 不带. 有 Origin/Referer 的 loopback 请求视为浏览器来源,
		// 强制走 cookie 鉴权路径 (而不是无条件放行).
		if isLoopbackRequest(r) {
			if r.Header.Get("Origin") == "" && r.Header.Get("Referer") == "" {
				next.ServeHTTP(w, r)
				return
			}
			log.Printf("loopback with Origin/Referer → cookie auth required: origin=%q ref=%q",
				r.Header.Get("Origin"), r.Header.Get("Referer"))
			// 不 return · 继续走下面 cookie 鉴权路径
		}

		// 同步 tokens.json 如果被外部修改过(json_set.sh revoke)
		_ = s.tokens.SyncIfChanged()

		cookie, err := r.Cookie(CookieName)
		if err != nil || cookie.Value == "" {
			// 无 cookie:按 remote_auth_required 决定
			// v4.0 Patch 3.a: /api/action 是写操作,永不放行匿名
			// 即使 remote_auth_required=false 也强制要 cookie
			if !readAuthRequired(s.hncDir) && !forceRemoteAuth && !isWritePath(r.URL.Path) && !isSensitiveReadPath(r.URL.Path) {
				// 过渡期且非写操作: 放行
				next.ServeHTTP(w, r)
				return
			}
			respondUnauthorized(w, r, false)
			return
		}

		tokenID, tok, err := VerifyCookie(s.tokens, cookie.Value)
		if err != nil {
			// cookie 无效,清掉
			respondUnauthorized(w, r, true)
			return
		}

		// 成功:更新 last_seen + 塞 context
		s.tokens.UpdateLastSeen(tokenID)
		log.Printf("auth ok: %s %s tid=%s ip=%s",
			r.Method, r.URL.Path, TokenIDLogPrefix(tokenID), ipOnly(r.RemoteAddr))

		ctx := context.WithValue(r.Context(), ctxKeyTokenID, tokenID)
		ctx = context.WithValue(ctx, ctxKeyToken, tok)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// v4.0 Patch 3.a: 写操作路径 - 永不放行匿名,即使过渡期也强制鉴权
func isWritePath(p string) bool {
	// 目前仅 /api/action, 未来新写操作端点加这里
	return p == "/api/action"
}

// hotfix17.8: 敏感只读接口。
// /api/logs 会暴露 MAC/IP/hostname/SSID/操作时间线；远程访问即使 auth_required=false
// 也必须要求 cookie。本机 KSU loopback 且无 Origin/Referer 仍由上方 loopback bypass 放行。
func isSensitiveReadPath(p string) bool {
	switch p {
	case "/api/logs",
		"/api/devices",
		"/api/live",
		"/api/capabilities",
		"/api/tokens",
		"/api/config",
		"/api/stats",
		"/api/templates",
		"/api/metrics",
		"/api/iface_info",
		"/api/offload_status",
		"/api/sqm",
		"/api/dpi_state",
		"/api/dpi_probe":
		return true
	default:
		return false
	}
}

// respondUnauthorized 拒绝无效/缺失 token 的请求
// clearExisting=true 时下发过期 cookie 清浏览器
func respondUnauthorized(w http.ResponseWriter, r *http.Request, clearExisting bool) {
	if clearExisting {
		http.SetCookie(w, clearCookie())
	}
	if strings.HasPrefix(r.URL.Path, "/api/") {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"auth required"}`))
	} else {
		http.Redirect(w, r, "/pair", http.StatusFound)
	}
}

// unauthRateLimitMiddleware 包裹公开路径(/pair, /api/pair/verify),
// 每 IP 20 req/s token bucket。
// 目的: 防止爬虫 + 恶意请求耗资源。PIN 自己的 5 次/分锁在 handlePairVerify 里做。
func (s *server) unauthRateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := ipOnly(r.RemoteAddr)
		allowed, retry := s.limiter.CheckUnauth(ip)
		if !allowed {
			w.Header().Set("Retry-After", int64ToStr(retry))
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"rate limited"}`))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func int64ToStr(n int64) string {
	// 避免 import strconv 多一次
	if n == 0 {
		return "0"
	}
	neg := false
	if n < 0 {
		neg = true
		n = -n
	}
	buf := [20]byte{}
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// isLoopbackRequest 判定请求是否来自 loopback 接口。
// v5.0 新增: KSU WebUI 在本机通过 http://127.0.0.1:<port>/ 访问时免鉴权。
// 注: RemoteAddr 格式 "ip:port", 可能是 IPv4 "127.0.0.1:xxx" 或 IPv6 "[::1]:xxx"。
func isLoopbackRequest(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	// rc3 修 N-14: IPv4-mapped IPv6 (如 "::ffff:127.0.0.1") 也算 loopback
	// Android bionic 某些场景下 curl 127.0.0.1 会通过 IPv4-in-IPv6 到达,
	// 直接 ip.IsLoopback() 返 false, 导致 ksu.exec 请求偶尔被判远程.
	if v4 := ip.To4(); v4 != nil {
		return v4.IsLoopback()
	}
	return ip.IsLoopback()
}
