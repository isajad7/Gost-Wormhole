<div dir="rtl" align="center">

# 🚇 GOST-WORMHOLE
### Professional Tunnel Builder (Iran ↔ Abroad)

Bash-based automation for building **fast, stable and manageable network tunnels**
between restricted and unrestricted networks.

![bash](https://img.shields.io/badge/Bash-Script-green)
![Linux](https://img.shields.io/badge/Linux-Ubuntu%20%7C%20Debian-blue)
![Version](https://img.shields.io/badge/Version-9.0.0-orange)

</div>

---

## 📌 What is GOST-WORMHOLE?

GOST-WORMHOLE is **not a VPN**.  
It is a **tunneling automation tool** designed for real-world Iran ↔ Abroad scenarios.

It focuses on:
- Low latency
- High availability
- Service isolation
- Easy recovery after network failures

---

## 🎯 Typical Use Cases

- 🌍 Connecting **Iran VPS → Foreign VPS**
- 🚀 Forwarding services securely through an external server
- 🛡️ Bypassing unstable or filtered networks
- 🧱 Building infrastructure for VPN / proxy services
- 🔁 Maintaining long-running tunnels with auto-recovery

---

## 🚀 Performance & Security Design

### Why is it fast?
- Uses **UDP-based protocols** (KCP / QUIC) to reduce latency
- Avoids unnecessary encryption layers when not required
- Multi-port forwarding in a single tunnel

### Why is it secure?
- Services are bound to `localhost`, not exposed directly
- Supports TLS-based protocols (gRPC / WS)
- No inbound service exposure on Iran server

⚠️ **Important**  
Security depends on **protocol choice and correct configuration**.  
This tool does not magically make insecure setups safe.

---

## 🔁 Reliability & Restart Logic

Network instability is expected — especially in restricted regions.

This project handles it using:
- `systemd` restart policies
- Cron-based watchdog monitoring
- Automatic service recovery on crash or drop

❗ Restarting is **not a fix for bad configuration**.  
Logs must be checked before assuming stability.

---

## ⚙️ Supported Protocols

| Protocol | Strength | Notes |
|--------|---------|------|
| KCP-FEC | High stability | ~1.2x bandwidth usage |
| KCP-Classic | Maximum speed | High bandwidth usage |
| QUIC | Streaming-friendly | ISP dependent |
| WS (MW) | Stealth | TCP-based |
| gRPC | Strong anti-filtering | Requires TLS |

---

## 🧠 Architecture Overview



[ Client (Iran) ]
|
(KCP / QUIC / WS / gRPC)
|
[ Server (Abroad) ]
|
Internet / Services


---

## 🖥️ Requirements

- Ubuntu 18+ / Debian 10+
- Root access
- Active network on both servers

---

## 🚀 Quick Start

Run on both servers:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isajad7/Gost-Wormhole/main/install.sh)


Then:

Abroad server → Setup Server

Iran server → Setup Client

🧭 Script Menu
1) Setup IRAN (Client)
2) Setup KHAREJ (Server)
3) List Active Services
4) View Live Logs
5) Delete Service
0) Exit

🇮🇷 Client Setup (Iran)

Choose option 1

Enter abroad server IP

Set tunnel port (e.g. 9000)

Define forwarded ports (e.g. 80,443,2082)

Select protocol (Recommended: KCP-FEC)

Result:

Dedicated systemd service

Localhost-bound forwarded ports

Active watchdog

Live logs available

🌍 Server Setup (Abroad)

Choose option 2

Enter listening port

Select same protocol as client

Result:

Listening service ready

Firewall rules applied

Persistent background service

🗑️ Removing a Tunnel

Menu option:

5) Delete Service


This will:

Stop the service

Remove systemd unit

Remove watchdog cron

🧠 Important Notes

This is a tunnel, not a full VPN

Bandwidth usage depends on protocol

Each tunnel = one systemd service

Multiple tunnels are fully supported

Always test with real traffic

⚠️ Known Issues & Limitations

KCP may be unstable on some datacenters

QUIC can be throttled by certain ISPs

UFW and iptables may conflict on some systems

Restart loops indicate configuration issues

🏷️ Versioning
v9.0.0

Improved watchdog logic

Multi-port stability fixes

Breaking change: old services must be recreated

📡 Offline Installation (Iran Servers)

If GitHub access is blocked:

curl http://178.239.144.62:8081/install-wormhole.sh | bash


Advantages:

No GitHub dependency

Suitable for restricted servers

Fast deployment

⚠️ Disclaimer

This project is provided for educational and network management purposes.
The author is not responsible for misuse.

<div align="center">

⭐ If this project helped you, consider giving it a star
Made with ❤️ by Tunnel Master

</div> 