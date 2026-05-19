# Fake Access Point

Rogue open Wi-Fi AP for traffic capture in controlled environments. Uses `hostapd` (native nl80211 AP mode) + `dnsmasq` (DHCP/DNS) + `iptables` NAT toward an uplink interface.

## Requirements

- Linux, root.
- Wireless card with AP-mode support (`iw phy` → `Supported interface modes: ... AP`).
- Packages: `hostapd`, `dnsmasq`, `iw`, `iptables`, `rfkill`, `wireshark`.

## Configuration

Edit the variables at the top of `fake_ap.sh`:

```bash
FAKE_SSID="Free_Public_WiFi"
CHANNEL="6"
INTERNET_IFACE="eth0"              # uplink with internet: ip route | grep default
AP_IFACE="wlan0"                   # wireless card for AP: iw dev
GATEWAY_IP="10.0.0.1"
```

## Run

```bash
sudo ./fake_ap.sh
```

The script:

1. Creates the AP interface (e.g. `wlan0`) in managed mode on the wireless phy.
2. Starts `hostapd` with an open SSID on the chosen channel.
3. Starts `dnsmasq` (DHCP + DNS forwarder to 1.1.1.1 / 8.8.8.8).
4. Enables IP forwarding and MASQUERADE toward the uplink.
5. Prints connected clients in real time (MAC + IP + hostname from lease).
6. Ctrl+C runs full cleanup (iptables rules, interface, NM, ip_forward).

## Live monitoring

```bash
sudo journalctl -t dnsmasq -f          # DHCP leases + every client DNS query
sudo wireshark -i wlan0                # capture client L3 traffic (use your AP_IFACE)
sudo iw dev wlan0 station dump         # client L2 state (RSSI, rate, traffic)
cat /var/lib/misc/dnsmasq.leases       # active leases
```

## Wireshark — enumeration filters

Open Wireshark on your AP interface (e.g. `wlan0`) and apply the display filter you need.

### Identify the device

| What you learn | Filter |
| --- | --- |
| Hostname and vendor (DHCP options 12/55/60) | `dhcp` |
| Device name + services (Bonjour/AirPlay/Chromecast) | `mdns` |
| Windows hostname / SMB | `nbns` |
| Device model (UPnP) | `ssdp` |
| Vendor from MAC | `eth.addr == aa:bb:cc:dd:ee:ff` |
| All traffic from one client | `ip.addr == 10.0.0.X` |

### Where it is browsing (including HTTPS)

| What you learn | Filter |
| --- | --- |
| Domains resolved via DNS | `dns.qry.name` |
| HTTPS domains (SNI in ClientHello) | `tls.handshake.type == 1` |
| DNS responses with resolved IPs | `dns.flags.response == 1` |
| QUIC connections (Google, YouTube, Meta) | `quic` |
| Plain HTTP (full URL) | `http.request` |
| App/browser User-Agent | `http.user_agent` |

### Sessions and new connections

| What you learn | Filter |
| --- | --- |
| SYN only (new TCP connections) | `tcp.flags.syn == 1 && tcp.flags.ack == 0` |
| TLS handshakes in progress | `tls.handshake` |
| Large transfers (HTTP/2 over TLS) | `tcp.len > 1000` |
| ICMP (client diagnostic pings) | `icmp` |

### Credentials / forms (rare with HTTPS, still worth checking)

| What you learn | Filter |
| --- | --- |
| HTTP POST (login on http:// sites) | `http.request.method == "POST"` |
| FTP credentials | `ftp.request.command in {"USER","PASS"}` |
| Telnet | `telnet` |
| Plain SMTP/IMAP/POP3 | `smtp || imap || pop` |
| Suspicious strings in payload | `frame contains "password"` |

### Useful combinations

```text
# one client's encrypted traffic + contacted domains
ip.src == 10.0.0.42 && (dns || tls.handshake.type == 1)

# passive phone model discovery
ip.src == 10.0.0.42 && (dhcp || mdns || ssdp || nbns)

# traffic to a specific domain (e.g. social)
tls.handshake.extensions_server_name contains "instagram"

# exclude broadcast/multicast noise
not (eth.dst == ff:ff:ff:ff:ff:ff) && not (ip.dst >= 224.0.0.0 && ip.dst <= 239.255.255.255)
```

### Tips

- To quickly extract only the **SNI** visited by a client:
  ```bash
  sudo tshark -i wlan0 -Y 'tls.handshake.type==1 && ip.src==10.0.0.42' \
    -T fields -e tls.handshake.extensions_server_name
  ```
- For continuous pcap dumps to analyze offline:
  ```bash
  sudo tcpdump -i wlan0 -w /tmp/capture.pcap
  ```
- DNS queries are also visible in `journalctl -t dnsmasq -f` without Wireshark.

## License

MIT — see [LICENSE](LICENSE).

## Legal notice

Use only on networks and devices you own or have written authorization to test. Intercepting others' traffic is illegal.
