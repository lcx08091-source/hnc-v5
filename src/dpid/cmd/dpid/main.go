// hnc_dpid: HNC DPI daemon, AppSense-lite rc1.2-fixed.
//
// rc19 adds L2 per-client DNS/SNI attribution:
// capability probe -> mode decision -> raw AF_PACKET socket -> DNS/TLS events -> per-client metadata -> dpi_state.json.
//
// It does NOT do: NFQUEUE, DNS hijacking, QUIC, HTTP parsing, app/category rules,
// conntrack correlation, automatic limit/mark, or offload modification.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"hnc.io/dpid/capture"
	"hnc.io/dpid/output"
	"hnc.io/dpid/probe"
)

var version = "0.2.0-l2-rc19"

const (
	defaultConfigPath = "/data/local/hnc/etc/dpi_config.json"
	defaultRunDir     = "/data/local/hnc/run"

	pidFileName   = "dpid.pid"
	lockFileName  = "dpid.lock"
	probeFileName = "dpid.probe.json"
	stateFileName = "dpi_state.json"
	crashFlagFile = "dpid.crashflag"

	maxCrashesWindow  = 60 * time.Second
	maxCrashesAllowed = 3

	debugEventsPerSec = 20
)

type Config struct {
	Iface          string `json:"iface,omitempty"`
	Snaplen        int    `json:"snaplen,omitempty"`
	RcvBufBytes    int    `json:"rcv_buf_bytes,omitempty"`
	LogLevel       string `json:"log_level,omitempty"`
	RunDir         string `json:"run_dir,omitempty"`
	DisableCapture bool   `json:"disable_capture,omitempty"`
}

func defaultConfig() Config {
	return Config{
		Snaplen:     1024,
		RcvBufBytes: 4 << 20,
		LogLevel:    "info",
		RunDir:      defaultRunDir,
	}
}

type Mode string

const (
	ModeOK        Mode = "ok"
	ModeBlind     Mode = "blind"
	ModeDisabled  Mode = "disabled"
	ModeCrashLoop Mode = "crash_loop"
)

func main() {
	cfgPath := flag.String("config", defaultConfigPath, "path to dpi_config.json")
	showVer := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVer {
		fmt.Println("hnc_dpid", version)
		return
	}

	cfg := loadConfig(*cfgPath)
	if err := os.MkdirAll(cfg.RunDir, 0o750); err != nil {
		log.Fatalf("mkdir run_dir %s: %v", cfg.RunDir, err)
	}

	lockFD, err := acquireLock(filepath.Join(cfg.RunDir, lockFileName))
	if err != nil {
		log.Fatalf("lock: %v", err)
	}
	defer releaseLock(lockFD)

	// Write PID early so crash_loop, blind, disabled, and ok modes all have a pid file.
	pidPath := filepath.Join(cfg.RunDir, pidFileName)
	if err := atomicWriteString(pidPath, strconv.Itoa(os.Getpid())+"\n"); err != nil {
		log.Printf("WARN: write pid: %v", err)
	}
	defer os.Remove(pidPath)

	statePath := filepath.Join(cfg.RunDir, stateFileName)
	sw := output.NewWriter(statePath, version)

	if reason := checkCrashLoop(cfg.RunDir); reason != "" {
		log.Printf("ERROR: %s", reason)
		sw.SetMode(string(ModeCrashLoop), reason, "", false, false)
		_ = sw.Flush()
		idleUntilSignal(sw)
		return
	}

	pr := probe.Run(probe.Options{IfaceOverride: cfg.Iface})
	if err := probe.WriteJSON(filepath.Join(cfg.RunDir, probeFileName), pr); err != nil {
		log.Printf("WARN: write probe: %v", err)
	}
	log.Printf("probe: af_packet=%v iface=%q src=%s offload_hint=%v conntrack=%v ipv6_capture=%v",
		pr.AFPacketAvailable, pr.APIface, pr.APIfaceSource, pr.OffloadHint, pr.ConntrackReadable, pr.IPv6Capture)

	mode, blindReason := decideMode(cfg, pr)
	sw.SetMode(string(mode), blindReason, pr.APIface, pr.TLSReassembly, pr.OffloadHint)
	_ = sw.Flush()
	if blindReason != "" {
		log.Printf("startup mode: %s: %s", mode, blindReason)
	} else {
		log.Printf("startup mode: %s", mode)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 4)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	go func() {
		for sig := range sigCh {
			switch sig {
			case syscall.SIGTERM, syscall.SIGINT:
				log.Printf("received %v, shutting down", sig)
				cancel()
				return
			case syscall.SIGHUP:
				log.Printf("SIGHUP received (rules reload is rc2)")
			}
		}
	}()

	armCrashFlag(cfg.RunDir)

	switch mode {
	case ModeBlind, ModeDisabled:
		log.Printf("no capture in %s mode; idling for state writes", mode)
		idleWithFlush(ctx, sw)
	case ModeOK:
		if err := runCapture(ctx, cfg, pr, sw); err != nil {
			// Capture open/run failure is capability failure, not daemon crash.
			reason := "open/run capture failed: " + err.Error()
			log.Printf("ERROR: %s", reason)
			sw.SetMode(string(ModeBlind), reason, pr.APIface, pr.TLSReassembly, pr.OffloadHint)
			_ = sw.Flush()
			clearCrashFlag(cfg.RunDir)
			idleWithFlush(ctx, sw)
		}
	}

	_ = sw.Flush()
	clearCrashFlag(cfg.RunDir)
	log.Printf("hnc_dpid exited cleanly")
}

func runCapture(ctx context.Context, cfg Config, pr probe.Result, sw *output.Writer) error {
	h, err := capture.Open(capture.Options{Iface: pr.APIface, Snaplen: cfg.Snaplen, RcvBufBytes: cfg.RcvBufBytes})
	if err != nil {
		return fmt.Errorf("open capture: %w", err)
	}
	defer h.Close()

	log.Printf("capture started on %s (snaplen=%d, rcvbuf=%d)", pr.APIface, cfg.Snaplen, cfg.RcvBufBytes)

	debug := cfg.LogLevel == "debug"
	var debugBudget atomic.Int64
	if debug {
		debugBudget.Store(int64(debugEventsPerSec))
		go func() {
			tk := time.NewTicker(time.Second)
			defer tk.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-tk.C:
					debugBudget.Store(int64(debugEventsPerSec))
				}
			}
		}()
	}

	go func() {
		tk := time.NewTicker(5 * time.Second)
		defer tk.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tk.C:
				s := h.Stats()
				sw.UpdateStats(output.Stats{
					Packets:        s.Packets,
					KernelDrops:    s.KernelDrops,
					DNSEvents:      s.DNSEvents,
					TLSEvents:      s.TLSEvents,
					IgnoredPackets: s.IgnoredPackets,
					ParseErrors:    s.ParseErrors,
				})
				if err := sw.Flush(); err != nil {
					log.Printf("WARN: flush state: %v", err)
				}
			}
		}
	}()

	go func() {
		tk := time.NewTicker(15 * time.Second)
		defer tk.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tk.C:
				s := h.Stats()
				log.Printf("stats: pkts=%d drops=%d dns=%d tls=%d ignored=%d perr=%d",
					s.Packets, s.KernelDrops, s.DNSEvents, s.TLSEvents, s.IgnoredPackets, s.ParseErrors)
			}
		}
	}()

	return h.Run(ctx, func(ev capture.Event) {
		clientMAC := ev.ClientMAC.String()
		clientIP := ev.ClientIP.String()
		remoteIP := ev.RemoteIP.String()

		switch ev.Kind {
		case capture.EventDNS:
			sw.RecordDNS(clientMAC, clientIP, remoteIP, ev.DNS.QName, ev.Time)
		case capture.EventTLSClientHello:
			sw.RecordTLS(clientMAC, clientIP, remoteIP, ev.TLS.SNI, ev.Time)
		}

		if !debug {
			return
		}
		if debugBudget.Add(-1) < 0 {
			return
		}
		// NOTE: debug logs contain full qname/SNI. Formal release/debug bundles must sanitize qname/SNI.
		switch ev.Kind {
		case capture.EventDNS:
			log.Printf("DNS client=%s/%s remote=%s qname=%q qtype=%d resp=%v ttl=%d answers=%d",
				ev.ClientMAC, ev.ClientIP, ev.RemoteIP, ev.DNS.QName, ev.DNS.QType, ev.DNS.IsResponse, ev.DNS.TTL, len(ev.DNS.Answers))
		case capture.EventTLSClientHello:
			log.Printf("TLS-CH client=%s/%s remote=%s sni=%q alpn=%v",
				ev.ClientMAC, ev.ClientIP, ev.RemoteIP, ev.TLS.SNI, ev.TLS.ALPN)
		}
	})
}

func idleWithFlush(ctx context.Context, sw *output.Writer) {
	tk := time.NewTicker(10 * time.Second)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tk.C:
			_ = sw.Flush()
		}
	}
}

func idleUntilSignal(sw *output.Writer) {
	sigCh := make(chan os.Signal, 4)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	tk := time.NewTicker(30 * time.Second)
	defer tk.Stop()
	for {
		select {
		case <-sigCh:
			return
		case <-tk.C:
			_ = sw.Flush()
		}
	}
}

func decideMode(cfg Config, pr probe.Result) (Mode, string) {
	if cfg.DisableCapture {
		return ModeDisabled, "disable_capture=true"
	}
	if !pr.AFPacketAvailable {
		return ModeBlind, "AF_PACKET unavailable: " + pr.AFPacketError
	}
	if pr.APIface == "" {
		return ModeBlind, "no hotspot iface detected"
	}
	return ModeOK, ""
}

func loadConfig(path string) Config {
	cfg := defaultConfig()
	b, err := os.ReadFile(path)
	if err != nil {
		if !os.IsNotExist(err) {
			log.Printf("WARN: read config %s: %v", path, err)
		}
		return cfg
	}
	var raw Config
	if err := json.Unmarshal(b, &raw); err != nil {
		log.Printf("WARN: parse config %s: %v (using defaults)", path, err)
		return cfg
	}
	if raw.Iface != "" {
		cfg.Iface = raw.Iface
	}
	if raw.Snaplen > 0 {
		cfg.Snaplen = raw.Snaplen
	}
	if raw.RcvBufBytes > 0 {
		cfg.RcvBufBytes = raw.RcvBufBytes
	}
	if raw.LogLevel != "" {
		cfg.LogLevel = raw.LogLevel
	}
	if raw.RunDir != "" {
		cfg.RunDir = raw.RunDir
	}
	if raw.DisableCapture {
		cfg.DisableCapture = true
	}
	return cfg
}

func acquireLock(path string) (int, error) {
	fd, err := syscall.Open(path, syscall.O_CREAT|syscall.O_RDWR|syscall.O_CLOEXEC, 0o644)
	if err != nil {
		return -1, fmt.Errorf("open %s: %w", path, err)
	}
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = syscall.Close(fd)
		if err == syscall.EWOULDBLOCK {
			return -1, fmt.Errorf("another hnc_dpid is running (%s held)", path)
		}
		return -1, fmt.Errorf("flock %s: %w", path, err)
	}
	return fd, nil
}

func releaseLock(fd int) {
	if fd >= 0 {
		_ = syscall.Flock(fd, syscall.LOCK_UN)
		_ = syscall.Close(fd)
	}
}

func atomicWriteString(path, data string) error {
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(data); err != nil {
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

func armCrashFlag(runDir string) {
	path := filepath.Join(runDir, crashFlagFile)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		log.Printf("WARN: arm crash flag: %v", err)
		return
	}
	defer f.Close()
	_, _ = fmt.Fprintf(f, "%d\n", time.Now().Unix())
	_ = f.Sync()
}

func clearCrashFlag(runDir string) {
	_ = os.Remove(filepath.Join(runDir, crashFlagFile))
}

func checkCrashLoop(runDir string) string {
	path := filepath.Join(runDir, crashFlagFile)
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	cutoff := time.Now().Add(-maxCrashesWindow).Unix()
	recent := 0
	start := 0
	for i := 0; i <= len(b); i++ {
		if i == len(b) || b[i] == '\n' {
			if i > start {
				if ts, err := strconv.ParseInt(string(b[start:i]), 10, 64); err == nil && ts >= cutoff {
					recent++
				}
			}
			start = i + 1
		}
	}
	if recent >= maxCrashesAllowed {
		return fmt.Sprintf("crash loop: %d starts in last %s", recent, maxCrashesWindow)
	}
	return ""
}
