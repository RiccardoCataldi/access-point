# Fake Access Point Script

## Overview
This script creates a configurable WiFi access point that can be used for network testing and monitoring in controlled environments. It sets up a complete network infrastructure including DHCP services and NAT routing.

## ⚠️ Security Notice
This tool is intended for educational and authorized testing purposes only. Using this script to create unauthorized access points or monitor network traffic without permission may be illegal in your jurisdiction. Always obtain proper authorization before use.

## Core Components

### 1. Network Interface Configuration
- Uses two network interfaces:
  - Internet Interface (eth0): Provides internet connectivity
  - Wireless Interface (wlan0): Creates the access point
- Configurable interface names in the script

### 2. Monitor Mode Setup
- Automatically handles interfering processes
- Enables monitor mode on wireless interface
- Creates a dedicated monitoring interface

### 3. Access Point Creation
- Configurable SSID and channel
- Uses airbase-ng for AP creation
- Creates virtual interface (at0) for client connections

### 4. Network Configuration
- Configurable IP range and network settings
- Default configuration:
  - Gateway: 10.0.0.1
  - Netmask: 255.255.255.0
  - DHCP Range: 10.0.0.10 - 10.0.0.50

### 5. DHCP Services
- Automatic IP assignment for clients
- DNS and gateway configuration
- Uses dnsmasq for DHCP services

### 6. NAT Configuration
- Enables IP forwarding
- Sets up NAT rules using iptables
- Manages traffic routing between interfaces

### 7. Safety Features
- Automatic cleanup on script termination
- Restores normal network configuration
- Removes temporary files and configurations

## Requirements
- Linux operating system
- Root privileges
- Wireless adapter supporting monitor mode
- Required packages:
  - aircrack-ng
  - dnsmasq
  - iptables
  - xterm

## Configuration
Edit the following variables in the script according to your needs:
```bash
FAKE_SSID="Free_Public_WiFi"
CHANNEL="6"
INTERNET_IFACE="eth0"
MON_IFACE="wlan0"# access-point
