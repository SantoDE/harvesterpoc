# OVH vRack Networking on Harvester (SUSE Linux)

## Node: harvester01

### NICs
| Interface | MAC | Role |
|-----------|-----|------|
| eno1 | d0:50:99:d6:3e:e1 | Public NIC — unused post-reinstall (future: VM network) |
| eno2 | d0:50:99:d6:3e:e0 | vRack NIC — Harvester management + VIP |

### IP Block (OVH public block, routed via vRack)
| Address | Role |
|---------|------|
| 51.38.122.160 | Network |
| 51.38.122.161 | Harvester VIP (UI + kubectl) |
| 51.38.122.162 | harvester01 node IP |
| 51.38.122.163–.165 | Available for VMs |
| 51.38.122.166 | Gateway (OVH vRack) |
| 51.38.122.167 | Broadcast |

> Internet access works natively — this is a public IP block, no NAT needed.
> Outbound traffic from .162 routes via .166 → OVH backbone → internet.

---

## Target Architecture (post-reinstall)

```
eno2 (vRack NIC, d0:50:99:d6:3e:e0)
  └── mgmt-br (Harvester management bridge)
        ├── node IP: 51.38.122.162/29
        └── VIP:     51.38.122.161/32  ← managed by kube-vip

eno1 (public NIC, d0:50:99:d6:3e:e1)
  └── unused / future VM bridge
```

kube-vip naturally manages the VIP on the same bridge as the management interface.
No asymmetric routing hacks needed.

---

## Reinstall Config (`/oem/harvester.config`)

```yaml
install:
  managementinterface:
    interfaces:
      - name: eno2
        hwaddr: d0:50:99:d6:3e:e0
    method: static
    ip: 51.38.122.162
    subnetmask: 255.255.255.248
    gateway: 51.38.122.166
    defaultroute: true
    bondoptions:
      miimon: "100"
      mode: active-backup
    mtu: 0
    vlanid: 0
  vip: 51.38.122.161
```

### How to Reinstall

1. Boot from the Harvester ISO (USB or OVH IPMI virtual media)
2. At the installer, choose **"Edit config"** or use the **interactive install**
3. On the **Management Interface** screen:
   - Select `eno2` (MAC `d0:50:99:d6:3e:e0`)
   - Set IP: `51.38.122.162`, Mask: `255.255.255.248`, Gateway: `51.38.122.166`
4. On the **VIP** screen: set `51.38.122.161`
5. Complete the rest of the install (hostname, token, password, disk)

Alternatively, provide the config file directly for an unattended install:
- Mount/serve the config and pass it via kernel boot parameter:
  `harvester.install.config_url=http://<server>/harvester.config`

---

## What Went Wrong (original setup — for reference)

- Harvester was installed with eno1 (public NIC) as management, VIP set to 51.38.122.161 (vRack IP)
- kube-vip defaulted to the management interface (eno1/mgmt-br) with `vip_interface=` empty
- kube-vip's iptables DNAT rules were in place but the reply path was asymmetric
- Packets arrived on eno2 (vRack), replies went out eno1 (public NIC) — TCP connections never completed
- Ping worked (ICMP is stateless), port 443 did not

### Partial workaround applied (not needed after reinstall)
```bash
# Policy routing to force vRack-sourced replies back out vrack-br
sudo ip rule add from 51.38.122.161 table 100
sudo ip route add default via 51.38.122.166 dev vrack-br table 100
```

---

## Post-Reinstall: VMs on vRack

Create a VM network in Harvester that maps to the management bridge.
VMs can then be assigned IPs from `51.38.122.163`–`51.38.122.165`.

If you later want a separate VM network on eno1 (public NIC), create a new bridge
on eno1 post-install via Harvester's network configuration UI.
