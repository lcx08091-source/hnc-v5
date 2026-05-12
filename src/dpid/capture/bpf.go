// Package capture: classic BPF filter for hnc_dpid rc1.2-fixed.
package capture

import (
	"fmt"
	"syscall"
)

const ETH_P_ALL = 0x0003

func htons(v uint16) uint16 { return v<<8 | v>>8 }

// BuildFilter builds the cBPF program that lets the kernel hand only the
// packets we care about up to userspace. IPv4 only (IPv6 deferred).
//
// Accepts:
//   - UDP src or dst port 53                          (DNS over UDP)
//   - TCP src or dst port 53                          (DNS over TCP)
//   - TCP dst port 443 AND first payload byte == 0x16 (TLS handshake)
//
// Layout:
//
//	ACCEPT = 27
//	DROP   = 28
func BuildFilter(snaplen uint32) ([]syscall.SockFilter, error) {
	if snaplen == 0 {
		snaplen = 1024
	}

	const (
		// Classic BPF opcodes from linux/filter.h.
		ld   = 0x00
		ldx  = 0x01
		alu  = 0x04
		jmp  = 0x05
		ret  = 0x06
		misc = 0x07

		w   = 0x00
		h   = 0x08
		b   = 0x10
		abs = 0x20
		ind = 0x40
		msh = 0xa0

		jeq  = 0x10
		jset = 0x40

		add = 0x00
		and = 0x50
		rsh = 0x70

		k = 0x00
		x = 0x08

		tax = 0x00
	)

	prog := []syscall.SockFilter{
		// [0..1] EtherType must be IPv4.
		/* 00 */ {Code: ld | h | abs, K: 12},
		/* 01 */ {Code: jmp | jeq | k, K: 0x0800, Jt: 0, Jf: 26},

		// [2..4] dispatch by IP proto.
		/* 02 */ {Code: ld | b | abs, K: 23},
		/* 03 */ {Code: jmp | jeq | k, K: 17, Jt: 1, Jf: 0}, // UDP -> 5
		/* 04 */ {Code: jmp | jeq | k, K: 6, Jt: 7, Jf: 23}, // TCP -> 12, else DROP

		// [5..11] UDP path.
		/* 05 */ {Code: ld | h | abs, K: 20},
		/* 06 */ {Code: jmp | jset | k, K: 0x1fff, Jt: 21, Jf: 0},
		/* 07 */ {Code: ldx | b | msh, K: 14}, // X = IPHL
		/* 08 */ {Code: ld | h | ind, K: 14}, // UDP src port
		/* 09 */ {Code: jmp | jeq | k, K: 53, Jt: 17, Jf: 0},
		/* 10 */ {Code: ld | h | ind, K: 16}, // UDP dst port
		/* 11 */ {Code: jmp | jeq | k, K: 53, Jt: 15, Jf: 16},

		// [12..19] TCP path.
		/* 12 */ {Code: ld | h | abs, K: 20},
		/* 13 */ {Code: jmp | jset | k, K: 0x1fff, Jt: 14, Jf: 0},
		/* 14 */ {Code: ldx | b | msh, K: 14}, // X = IPHL
		/* 15 */ {Code: ld | h | ind, K: 14}, // TCP src port
		/* 16 */ {Code: jmp | jeq | k, K: 53, Jt: 10, Jf: 0},
		/* 17 */ {Code: ld | h | ind, K: 16}, // TCP dst port
		/* 18 */ {Code: jmp | jeq | k, K: 53, Jt: 8, Jf: 0},
		/* 19 */ {Code: jmp | jeq | k, K: 443, Jt: 0, Jf: 8},

		// [20..26] TLS handshake check. X is still IPHL.
		// TCP byte 12 is at packet offset 14 + IPHL + 12 = X + 26.
		/* 20 */ {Code: ld | b | ind, K: 26}, // A = TCP byte 12
		/* 21 */ {Code: alu | and | k, K: 0xf0}, // data offset nibble << 4
		/* 22 */ {Code: alu | rsh | k, K: 2}, // TCPHL bytes
		/* 23 */ {Code: alu | add | x}, // A = IPHL + TCPHL
		/* 24 */ {Code: misc | tax}, // X = A
		/* 25 */ {Code: ld | b | ind, K: 14}, // first TCP payload byte
		/* 26 */ {Code: jmp | jeq | k, K: 0x16, Jt: 0, Jf: 1},

		// [27..28] returns.
		/* 27 */ {Code: ret | k, K: snaplen},
		/* 28 */ {Code: ret | k, K: 0},
	}

	if len(prog) != 29 {
		return nil, fmt.Errorf("unexpected bpf instruction count: %d", len(prog))
	}
	return prog, nil
}

// AttachFilter installs the compiled program on a raw socket.
func AttachFilter(fd int, filters []syscall.SockFilter) error {
	if len(filters) == 0 {
		return fmt.Errorf("empty filter")
	}
	if len(filters) > 4096 {
		return fmt.Errorf("filter too long: %d", len(filters))
	}
	return syscall.AttachLsf(fd, filters)
}
