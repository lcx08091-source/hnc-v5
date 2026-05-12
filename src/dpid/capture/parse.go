package capture

import (
	"encoding/binary"
	"net"
	"strings"
	"time"
)

type EventKind int

const (
	EventUnknown EventKind = iota
	EventDNS
	EventTLSClientHello
)

type DNSInfo struct {
	IsResponse bool
	QName      string
	QType      uint16
	Answers    []string
	TTL        uint32
}

type TLSInfo struct {
	SNI  string
	ALPN []string
}

type Event struct {
	Kind    EventKind
	Time    time.Time
	SrcMAC  net.HardwareAddr
	DstMAC  net.HardwareAddr
	SrcIP   net.IP
	DstIP   net.IP
	SrcPort uint16
	DstPort uint16
	IsUDP   bool

	// Direction-aware fields used by rc2 DNS/IP/device correlation.
	ClientMAC net.HardwareAddr
	ClientIP  net.IP
	RemoteIP  net.IP

	DNS DNSInfo
	TLS TLSInfo
}

const (
	etherTypeIPv4 = 0x0800
	ipProtoTCP    = 6
	ipProtoUDP    = 17
)

type ParseResult int

const (
	ParseOK ParseResult = iota
	ParseIgnore
	ParseMalformed
)

// parsePacket returns event metadata and a result code.
// ParseIgnore means a valid packet is not useful to rc1.2.
// ParseMalformed means broken headers or malformed DNS/TLS input.
func parsePacket(b []byte, ts time.Time) (Event, ParseResult) {
	if len(b) < 14 {
		return Event{}, ParseMalformed
	}
	if binary.BigEndian.Uint16(b[12:14]) != etherTypeIPv4 {
		return Event{}, ParseIgnore
	}
	dstMAC := append(net.HardwareAddr(nil), b[0:6]...)
	srcMAC := append(net.HardwareAddr(nil), b[6:12]...)

	ip := b[14:]
	if len(ip) < 20 {
		return Event{}, ParseMalformed
	}
	if ip[0]>>4 != 4 {
		return Event{}, ParseMalformed
	}
	ipHL := int(ip[0]&0x0f) * 4
	if ipHL < 20 || len(ip) < ipHL {
		return Event{}, ParseMalformed
	}
	totalLen := int(binary.BigEndian.Uint16(ip[2:4]))
	if totalLen == 0 || totalLen > len(ip) {
		totalLen = len(ip)
	}
	if totalLen < ipHL {
		return Event{}, ParseMalformed
	}
	proto := ip[9]
	srcIP := net.IPv4(ip[12], ip[13], ip[14], ip[15])
	dstIP := net.IPv4(ip[16], ip[17], ip[18], ip[19])
	payload := ip[ipHL:totalLen]

	ev := Event{Time: ts, SrcMAC: srcMAC, DstMAC: dstMAC, SrcIP: srcIP, DstIP: dstIP}

	switch proto {
	case ipProtoUDP:
		if len(payload) < 8 {
			return ev, ParseMalformed
		}
		ev.IsUDP = true
		ev.SrcPort = binary.BigEndian.Uint16(payload[0:2])
		ev.DstPort = binary.BigEndian.Uint16(payload[2:4])
		if ev.SrcPort != 53 && ev.DstPort != 53 {
			return ev, ParseIgnore
		}
		dnsPayload := payload[8:]
		if d, ok := parseDNS(dnsPayload); ok {
			ev.Kind = EventDNS
			ev.DNS = d
			assignClient(&ev, d.IsResponse)
			return ev, ParseOK
		}
		return ev, ParseMalformed

	case ipProtoTCP:
		if len(payload) < 20 {
			return ev, ParseMalformed
		}
		ev.SrcPort = binary.BigEndian.Uint16(payload[0:2])
		ev.DstPort = binary.BigEndian.Uint16(payload[2:4])
		tcpHL := int(payload[12]>>4) * 4
		if tcpHL < 20 || len(payload) < tcpHL {
			return ev, ParseMalformed
		}
		tcpData := payload[tcpHL:]

		if ev.DstPort == 53 || ev.SrcPort == 53 {
			if len(tcpData) > 2 {
				if d, ok := parseDNS(tcpData[2:]); ok {
					ev.Kind = EventDNS
					ev.DNS = d
					assignClient(&ev, d.IsResponse)
					return ev, ParseOK
				}
			}
			return ev, ParseMalformed
		}

		if ev.DstPort == 443 || ev.SrcPort == 443 {
			if sni, alpn, ok := parseTLSClientHello(tcpData); ok {
				ev.Kind = EventTLSClientHello
				ev.TLS.SNI = sni
				ev.TLS.ALPN = alpn
				assignClient(&ev, false)
				return ev, ParseOK
			}
			return ev, ParseIgnore
		}
	}

	return ev, ParseIgnore
}

// assignClient fills client/remote direction fields.
// DNS response: client is destination; DNS query and TLS ClientHello: client is source.
func assignClient(ev *Event, isResponseToClient bool) {
	if isResponseToClient {
		ev.ClientMAC = ev.DstMAC
		ev.ClientIP = ev.DstIP
		ev.RemoteIP = ev.SrcIP
	} else {
		ev.ClientMAC = ev.SrcMAC
		ev.ClientIP = ev.SrcIP
		ev.RemoteIP = ev.DstIP
	}
}

func parseDNS(b []byte) (DNSInfo, bool) {
	if len(b) < 12 {
		return DNSInfo{}, false
	}
	flags := binary.BigEndian.Uint16(b[2:4])
	qdcount := binary.BigEndian.Uint16(b[4:6])
	ancount := binary.BigEndian.Uint16(b[6:8])
	if qdcount != 1 {
		return DNSInfo{}, false
	}
	out := DNSInfo{IsResponse: flags&0x8000 != 0}

	p := 12
	qname, np, ok := dnsReadName(b, p)
	if !ok {
		return DNSInfo{}, false
	}
	p = np
	if len(b) < p+4 {
		return DNSInfo{}, false
	}
	out.QName = strings.ToLower(qname)
	out.QType = binary.BigEndian.Uint16(b[p : p+2])
	p += 4

	if !out.IsResponse {
		return out, true
	}

	var minTTL uint32
	for i := uint16(0); i < ancount; i++ {
		_, np, ok := dnsReadName(b, p)
		if !ok {
			break
		}
		p = np
		if len(b) < p+10 {
			break
		}
		atype := binary.BigEndian.Uint16(b[p : p+2])
		ttl := binary.BigEndian.Uint32(b[p+4 : p+8])
		rdlen := int(binary.BigEndian.Uint16(b[p+8 : p+10]))
		p += 10
		if len(b) < p+rdlen {
			break
		}
		rdataStart := p
		p += rdlen

		switch atype {
		case 1: // A
			if rdlen == 4 {
				out.Answers = append(out.Answers, net.IPv4(b[rdataStart], b[rdataStart+1], b[rdataStart+2], b[rdataStart+3]).String())
			}
		case 28: // AAAA answer in DNS payload, even though packet capture is IPv4-only in rc1.2.
			if rdlen == 16 {
				ip := make(net.IP, 16)
				copy(ip, b[rdataStart:rdataStart+16])
				out.Answers = append(out.Answers, ip.String())
			}
		case 5: // CNAME
			if name, _, ok := dnsReadName(b, rdataStart); ok {
				out.Answers = append(out.Answers, "CNAME:"+strings.ToLower(name))
			}
		}
		if minTTL == 0 || ttl < minTTL {
			minTTL = ttl
		}
	}
	out.TTL = minTTL
	return out, true
}

func dnsReadName(b []byte, off int) (string, int, bool) {
	var sb strings.Builder
	nextOff := off
	jumped := false
	jumps := 0
	for i := 0; i < 256; i++ {
		if off >= len(b) {
			return "", 0, false
		}
		l := b[off]
		if l == 0 {
			if !jumped {
				nextOff = off + 1
			}
			return sb.String(), nextOff, true
		}
		if l&0xc0 == 0xc0 {
			if off+1 >= len(b) {
				return "", 0, false
			}
			ptr := int(binary.BigEndian.Uint16(b[off:off+2]) & 0x3fff)
			if !jumped {
				nextOff = off + 2
				jumped = true
			}
			if ptr >= len(b) || ptr == off {
				return "", 0, false
			}
			off = ptr
			jumps++
			if jumps > 8 {
				return "", 0, false
			}
			continue
		}
		if l > 63 {
			return "", 0, false
		}
		off++
		if off+int(l) > len(b) {
			return "", 0, false
		}
		if sb.Len() > 0 {
			sb.WriteByte('.')
		}
		sb.Write(b[off : off+int(l)])
		off += int(l)
	}
	return "", 0, false
}

func parseTLSClientHello(b []byte) (string, []string, bool) {
	if len(b) < 5 || b[0] != 0x16 {
		return "", nil, false
	}
	recLen := int(binary.BigEndian.Uint16(b[3:5]))
	if recLen < 4 || len(b) < 5+recLen {
		return "", nil, false
	}
	hs := b[5 : 5+recLen]
	if len(hs) < 4 || hs[0] != 0x01 {
		return "", nil, false
	}
	bodyLen := int(hs[1])<<16 | int(hs[2])<<8 | int(hs[3])
	if len(hs) < 4+bodyLen {
		return "", nil, false
	}
	body := hs[4 : 4+bodyLen]

	p := 0
	if len(body) < p+2+32+1 {
		return "", nil, false
	}
	p += 2 + 32
	sidLen := int(body[p])
	p++
	if len(body) < p+sidLen+2 {
		return "", nil, false
	}
	p += sidLen
	csLen := int(binary.BigEndian.Uint16(body[p : p+2]))
	p += 2 + csLen
	if len(body) < p+1 {
		return "", nil, false
	}
	cmLen := int(body[p])
	p += 1 + cmLen
	if len(body) < p+2 {
		return "", nil, false
	}
	extLen := int(binary.BigEndian.Uint16(body[p : p+2]))
	p += 2
	if len(body) < p+extLen {
		return "", nil, false
	}
	ext := body[p : p+extLen]

	var sni string
	var alpn []string
	for len(ext) >= 4 {
		etype := binary.BigEndian.Uint16(ext[0:2])
		elen := int(binary.BigEndian.Uint16(ext[2:4]))
		ext = ext[4:]
		if len(ext) < elen {
			break
		}
		data := ext[:elen]
		ext = ext[elen:]

		switch etype {
		case 0x0000: // server_name
			if len(data) < 5 {
				continue
			}
			data = data[2:]
			if data[0] != 0 {
				continue
			}
			nameLen := int(binary.BigEndian.Uint16(data[1:3]))
			if len(data) < 3+nameLen {
				continue
			}
			sni = strings.ToLower(string(data[3 : 3+nameLen]))
		case 0x0010: // ALPN
			if len(data) < 2 {
				continue
			}
			list := data[2:]
			for len(list) >= 1 {
				n := int(list[0])
				if len(list) < 1+n {
					break
				}
				alpn = append(alpn, string(list[1:1+n]))
				list = list[1+n:]
			}
		}
	}

	if sni == "" && len(alpn) == 0 {
		return "", nil, false
	}
	return sni, alpn, true
}
