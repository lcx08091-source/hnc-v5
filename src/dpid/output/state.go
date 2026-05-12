package output

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const SchemaVersion = "1.1"

const (
	maxClients        = 128
	maxNamesPerClient = 64
	maxGlobalNames    = 256
	topN              = 8
)

type Stats struct {
	Packets        uint64 `json:"packets"`
	KernelDrops    uint64 `json:"kernel_drops"`
	DNSEvents      uint64 `json:"dns_events"`
	TLSEvents      uint64 `json:"tls_events"`
	IgnoredPackets uint64 `json:"ignored_packets"`
	ParseErrors    uint64 `json:"parse_errors"`
}

type Device struct {
	IPs       []string `json:"ips"`
	FirstSeen int64    `json:"first_seen"`
	LastSeen  int64    `json:"last_seen"`
	RxBps     uint64   `json:"rx_bps"`
	TxBps     uint64   `json:"tx_bps"`
}

type NameCount struct {
	Name     string `json:"name"`
	Count    uint64 `json:"count"`
	LastSeen int64  `json:"last_seen"`
}

type ClientProfile struct {
	ClientIP     string      `json:"client_ip"`
	ClientMAC    string      `json:"client_mac,omitempty"`
	RemoteIPs    []string    `json:"remote_ips,omitempty"`
	FirstSeen    int64       `json:"first_seen"`
	LastSeen     int64       `json:"last_seen"`
	DNSEvents    uint64      `json:"dns_events"`
	TLSEvents    uint64      `json:"tls_events"`
	LastHostname string      `json:"last_hostname,omitempty"`
	LastSNI      string      `json:"last_sni,omitempty"`
	TopHostnames []NameCount `json:"top_hostnames,omitempty"`
	TopSNI       []NameCount `json:"top_sni,omitempty"`
}

type State struct {
	SchemaVersion   string                   `json:"schema_version"`
	GeneratedAt     int64                    `json:"generated_at"`
	Version         string                   `json:"version"`
	Mode            string                   `json:"mode"`
	BlindReason     string                   `json:"blind_reason,omitempty"`
	Interface       string                   `json:"interface,omitempty"`
	TLSReassembly   bool                     `json:"tls_reassembly"`
	IPv6Capture     bool                     `json:"ipv6_capture"`
	OffloadHint     bool                     `json:"offload_hint"`
	UptimeS         int64                    `json:"uptime_s"`
	Stats           Stats                    `json:"stats"`
	Devices         map[string]Device        `json:"devices"`
	Clients         map[string]ClientProfile `json:"clients,omitempty"`
	ClientCount     int                      `json:"client_count"`
	TopHostnames    []NameCount              `json:"top_hostnames,omitempty"`
	TopSNI          []NameCount              `json:"top_sni,omitempty"`
	UniqueHostnames int                      `json:"unique_hostnames"`
	UniqueSNI       int                      `json:"unique_sni"`
}

type nameStat struct {
	Count    uint64
	LastSeen int64
}

type clientAgg struct {
	ClientIP     string
	ClientMAC    string
	FirstSeen    int64
	LastSeen     int64
	DNSEvents    uint64
	TLSEvents    uint64
	LastHostname string
	LastSNI      string
	Hostnames    map[string]*nameStat
	SNI          map[string]*nameStat
	RemoteIPs    map[string]int64
}

type Writer struct {
	mu        sync.Mutex
	state     State
	startTime time.Time
	path      string

	clients   map[string]*clientAgg
	globalDNS map[string]*nameStat
	globalSNI map[string]*nameStat
}

func NewWriter(path, version string) *Writer {
	return &Writer{
		path:      path,
		startTime: time.Now(),
		state: State{
			SchemaVersion: SchemaVersion,
			Version:       version,
			IPv6Capture:   false,
			Devices:       map[string]Device{},
		},
		clients:   make(map[string]*clientAgg),
		globalDNS: make(map[string]*nameStat),
		globalSNI: make(map[string]*nameStat),
	}
}

func (w *Writer) SetMode(mode, reason, iface string, tlsReassembly, offloadHint bool) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.state.Mode = mode
	w.state.BlindReason = reason
	w.state.Interface = iface
	w.state.TLSReassembly = tlsReassembly
	w.state.OffloadHint = offloadHint
}

func (w *Writer) UpdateStats(s Stats) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.state.Stats = s
}

// RecordDNS attributes a DNS qname to the hotspot client seen on the packet.
// This is L2 metadata only: no app/category classification and no payload storage.
func (w *Writer) RecordDNS(clientMAC, clientIP, remoteIP, qname string, ts time.Time) {
	host := normalizeName(qname)
	if clientIP == "" && clientMAC == "" {
		return
	}
	now := ts.Unix()
	w.mu.Lock()
	defer w.mu.Unlock()
	c := w.clientLocked(clientMAC, clientIP, now)
	c.DNSEvents++
	c.LastSeen = now
	if remoteIP != "" {
		c.RemoteIPs[remoteIP] = now
	}
	if host != "" {
		c.LastHostname = host
		bumpName(c.Hostnames, host, now, maxNamesPerClient)
		bumpName(w.globalDNS, host, now, maxGlobalNames)
	}
}

// RecordTLS attributes a TLS ClientHello SNI to the hotspot client seen on the packet.
func (w *Writer) RecordTLS(clientMAC, clientIP, remoteIP, sni string, ts time.Time) {
	host := normalizeName(sni)
	if clientIP == "" && clientMAC == "" {
		return
	}
	now := ts.Unix()
	w.mu.Lock()
	defer w.mu.Unlock()
	c := w.clientLocked(clientMAC, clientIP, now)
	c.TLSEvents++
	c.LastSeen = now
	if remoteIP != "" {
		c.RemoteIPs[remoteIP] = now
	}
	if host != "" {
		c.LastSNI = host
		bumpName(c.SNI, host, now, maxNamesPerClient)
		bumpName(w.globalSNI, host, now, maxGlobalNames)
	}
}

func (w *Writer) clientLocked(mac, ip string, now int64) *clientAgg {
	key := strings.TrimSpace(ip)
	if key == "" {
		key = strings.TrimSpace(mac)
	}
	if key == "" {
		key = "unknown"
	}
	if len(w.clients) >= maxClients {
		if _, ok := w.clients[key]; !ok {
			w.evictOldestClientLocked()
		}
	}
	c := w.clients[key]
	if c == nil {
		c = &clientAgg{
			ClientIP:  ip,
			ClientMAC: mac,
			FirstSeen: now,
			LastSeen:  now,
			Hostnames: make(map[string]*nameStat),
			SNI:       make(map[string]*nameStat),
			RemoteIPs: make(map[string]int64),
		}
		w.clients[key] = c
	}
	if c.ClientIP == "" && ip != "" {
		c.ClientIP = ip
	}
	if c.ClientMAC == "" && mac != "" {
		c.ClientMAC = mac
	}
	return c
}

func (w *Writer) evictOldestClientLocked() {
	var oldestKey string
	var oldest int64
	for k, c := range w.clients {
		if oldestKey == "" || c.LastSeen < oldest {
			oldestKey = k
			oldest = c.LastSeen
		}
	}
	if oldestKey != "" {
		delete(w.clients, oldestKey)
	}
}

func normalizeName(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = strings.TrimSuffix(s, ".")
	if s == "" || len(s) > 253 {
		return ""
	}
	// Keep the JSON/UI safe and compact: DNS labels/SNI should be printable hostnames.
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '.' || r == '_' || r == ':' {
			continue
		}
		return ""
	}
	return s
}

func bumpName(m map[string]*nameStat, name string, now int64, limit int) {
	if name == "" {
		return
	}
	st := m[name]
	if st == nil {
		if limit > 0 && len(m) >= limit {
			evictOldestName(m)
		}
		st = &nameStat{}
		m[name] = st
	}
	st.Count++
	st.LastSeen = now
}

func evictOldestName(m map[string]*nameStat) {
	var oldestKey string
	var oldest int64
	for k, v := range m {
		if oldestKey == "" || v.LastSeen < oldest {
			oldestKey = k
			oldest = v.LastSeen
		}
	}
	if oldestKey != "" {
		delete(m, oldestKey)
	}
}

func topNames(m map[string]*nameStat, n int) []NameCount {
	out := make([]NameCount, 0, len(m))
	for name, st := range m {
		out = append(out, NameCount{Name: name, Count: st.Count, LastSeen: st.LastSeen})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		if out[i].LastSeen != out[j].LastSeen {
			return out[i].LastSeen > out[j].LastSeen
		}
		return out[i].Name < out[j].Name
	})
	if n > 0 && len(out) > n {
		out = out[:n]
	}
	return out
}

func recentRemoteIPs(m map[string]int64, n int) []string {
	type kv struct {
		ip   string
		last int64
	}
	arr := make([]kv, 0, len(m))
	for ip, last := range m {
		arr = append(arr, kv{ip, last})
	}
	sort.Slice(arr, func(i, j int) bool { return arr[i].last > arr[j].last })
	if n > 0 && len(arr) > n {
		arr = arr[:n]
	}
	out := make([]string, 0, len(arr))
	for _, x := range arr {
		out = append(out, x.ip)
	}
	return out
}

func (w *Writer) Flush() error {
	w.mu.Lock()
	snap := w.state
	snap.SchemaVersion = SchemaVersion
	snap.GeneratedAt = time.Now().Unix()
	snap.UptimeS = int64(time.Since(w.startTime).Seconds())
	if len(w.state.Devices) > 0 {
		snap.Devices = make(map[string]Device, len(w.state.Devices))
		for k, v := range w.state.Devices {
			snap.Devices[k] = v
		}
	} else {
		snap.Devices = map[string]Device{}
	}
	snap.Clients = make(map[string]ClientProfile, len(w.clients))
	for key, c := range w.clients {
		cp := ClientProfile{
			ClientIP:     c.ClientIP,
			ClientMAC:    c.ClientMAC,
			RemoteIPs:    recentRemoteIPs(c.RemoteIPs, 6),
			FirstSeen:    c.FirstSeen,
			LastSeen:     c.LastSeen,
			DNSEvents:    c.DNSEvents,
			TLSEvents:    c.TLSEvents,
			LastHostname: c.LastHostname,
			LastSNI:      c.LastSNI,
			TopHostnames: topNames(c.Hostnames, topN),
			TopSNI:       topNames(c.SNI, topN),
		}
		snap.Clients[key] = cp
	}
	snap.ClientCount = len(w.clients)
	snap.TopHostnames = topNames(w.globalDNS, topN)
	snap.TopSNI = topNames(w.globalSNI, topN)
	snap.UniqueHostnames = len(w.globalDNS)
	snap.UniqueSNI = len(w.globalSNI)
	w.mu.Unlock()

	b, err := json.MarshalIndent(snap, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(w.path, b, 0o644)
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return err
	}
	if d, err := os.Open(filepath.Dir(path)); err == nil {
		_ = d.Sync()
		_ = d.Close()
	}
	return nil
}
