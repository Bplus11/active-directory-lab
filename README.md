# active-directory-lab
Documentation for my Active Directory Lab

# Homelab Expansion: Mini PC Integration, Proxmox Cluster, and AD Lab Setup

## Project Overview

This document covers the integration of a new mini PC into an existing Proxmox homelab environment, including cluster joining, network architecture changes, VLAN configuration, and standing up a Windows Server 2022 Active Directory lab environment.

### Environment

| Component | Details |
|---|---|
| **Node 1 (pve)** | Existing Proxmox host — runs Security Onion VM (inline tap), management IP `192.168.177.12` |
| **Node 2 (pve2)** | New mini PC — joined to cluster, hosts AD lab VMs, management IP `192.168.177.112` |
| **Router** | Firewalla Gold — primary gateway |
| **Switch** | Firewalla Switch SE — managed switch, VLAN trunking |
| **AP** | Firewalla AP7 |
| **Hypervisor** | Proxmox VE (two-node cluster) |
| **AD Lab VM (201)** | Windows Server 2022 Evaluation — domain controller on VLAN 30 |

---

## Phase 1: Windows 11 Image Capture from Mini PC

Before wiping the mini PC for Proxmox, the pre-installed Windows 11 image was captured for potential future use as a VM.

### Method: Raw Disk Image via Linux Live USB

Boot from a Linux live USB and create a raw full-disk image:

```bash
dd if=/dev/nvme0n1 of=/mnt/usb/win11.raw bs=4M status=progress
```

Convert to qcow2 for Proxmox:

```bash
qemu-img convert -f raw -O qcow2 win11.raw win11.qcow2
```

### Importing into Proxmox (for future use)

```bash
qm importdisk <vmid> win11.qcow2 local-lvm
```

> **Note:** The OEM Windows 11 license is tied to the hardware. It may or may not activate inside a VM on the same physical machine via SLIC/ACPI passthrough.

---

## Phase 2: Proxmox Installation and Cluster Join

### Pre-Installation

- Verified VT-x/VT-d was enabled in BIOS on the mini PC
- Flashed Proxmox VE ISO to USB and installed on the mini PC

### Hostname Fix

The mini PC was initially set up with `pve2.domain.local` but needed to match Node 1's domain convention (`bplus11.lan`).

Since the node had **not yet joined the cluster**, the fix was straightforward:

```bash
hostnamectl set-hostname pve2.bplus11.lan
```

Edit `/etc/hosts`:

```
127.0.0.1 localhost
192.168.177.112  pve2.bplus11.lan pve2
```

Update postfix if installed:

```bash
nano /etc/postfix/main.cf
# change myhostname to pve2.bplus11.lan
```

Reboot and verify:

```bash
reboot
hostname --fqdn
# Should return: pve2.bplus11.lan
```

### Cluster Join

Both nodes' `/etc/hosts` files were updated to include entries for both nodes:

```
<192.168.177.12>    pve.bplus11.lan pve
192.168.177.112   pve2.bplus11.lan pve2
```

Initial `pvecm add` failed with a hostname verification error. Resolved by fetching the correct certificate fingerprint directly from the API endpoint:

```bash
# On Node 1 — get the fingerprint the API is actually presenting
echo | openssl s_client -connect <192.168.177.12>:8006 2>/dev/null | openssl x509 -noout -fingerprint -sha256
```

Then joined from the mini PC using the fingerprint:

```bash
pvecm add <192.168.177.12> --fingerprint <SHA256_fingerprint>
```

### Post-Join Verification

```bash
pvecm status
pvecm nodes
```

Both nodes visible, quorum established. The `two_node: 1` quorum setting was already present in `/etc/pve/corosync.conf` (shared cluster filesystem — no need to edit on each node separately).

> **Key learning:** `/etc/pve/` is a shared cluster filesystem (pmxcfs). Any edit on either node applies to both nodes automatically.

---

## Phase 3: Network Architecture

### Current Topology

Security Onion remains inline between the router and the Firewalla SE switch until port mirroring support is added to the Switch SE:

```
Internet → Router → [Proxmox Node 1 - inline tap] → Firewalla SE Switch → AP
                                                                          → Mini PC (Node 2)
                                                                          → Primary PC
```

### Future Topology (when Firewalla SE adds port mirroring)

The planned migration moves the inline tap to a passive SPAN-based setup:

```
Internet → Router → Firewalla SE Switch → AP, PCs, both Proxmox nodes
                            |
                      mirror port → Proxmox Node 1 (dedicated sniff NIC)
```

This eliminates the single point of failure and simplifies cluster networking. Node 1 already has two physical NICs to support this:

- **NIC 1 (eno1):** Management, VM traffic, cluster communication → vmbr0
- **NIC 2:** Mirror/sniff target for Security Onion → vmbr1 (to be created)

#### Security Onion VM (101) — Current Config

| Interface | Bridge | Purpose |
|---|---|---|
| net0 (tag=33) | vmbr0 | Management — Security Onion web UI, updates |
| net1 | vmbr0 | Monitoring/sniff — captures inline traffic |

#### Security Onion VM — Future Config (post-mirror)

| Interface | Bridge | Purpose |
|---|---|---|
| net0 (tag=33) | vmbr0 | Management (unchanged) |
| net1 | vmbr1 | Monitoring — receives mirrored traffic from switch |

Future net1 change:

```bash
qm set 101 -net1 virtio=BC:24:11:CE:4C:9E,bridge=vmbr1,firewall=0
```

> **Important:** Firewall must be **off** on the sniff interface so all packets reach Security Onion unfiltered.

---

## Phase 4: VLAN Configuration on Proxmox Node 2

### VLAN Architecture

| VLAN | Subnet | Bridge | Purpose |
|---|---|---|---|
| Native (untagged) | 192.168.177.0/24 | vmbr0 | Proxmox management, home network |
| 30 | 192.168.30.0/24 | vmbr3 | AD lab, homelab VMs |
| 60 | 10.66.0.0/16 | vmbr6 | Threat hunting (fully isolated) |

### Design Decision: Separate Bridges per VLAN

Rather than using a single VLAN-aware bridge, each VLAN gets its own dedicated bridge with a VLAN sub-interface. This provides:

- Visual separation in the Proxmox UI
- Zero risk of VLAN bleed between lab environments and the home network
- Consistent approach across vmbr3 (AD lab) and vmbr6 (threat hunting)

### Network Configuration (`/etc/network/interfaces` on pve2)

```
auto lo
iface lo inet loopback

# Physical NIC — untagged management traffic
auto eno1
iface eno1 inet manual

# Management bridge — untagged, home network
auto vmbr0
iface vmbr0 inet static
    address 192.168.177.112/24
    gateway 192.168.177.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# VLAN 30 sub-interface
auto eno1.30
iface eno1.30 inet manual

# AD / Homelab bridge — VLAN 30
auto vmbr3
iface vmbr3 inet manual
    bridge-ports eno1.30
    bridge-stp off
    bridge-fd 0
    #AD - Homelab Env

# VLAN 60 sub-interface
auto eno1.60
iface eno1.60 inet manual

# Threat hunting bridge — VLAN 60
auto vmbr6
iface vmbr6 inet manual
    bridge-ports eno1.60
    bridge-stp off
    bridge-fd 0
    #Threat Hunting VLAN
```

### Key Configuration Notes

- **No IP address on vmbr3 or vmbr6** — the Firewalla Gold is the gateway for both VLANs
- **No VLAN-aware flag** on vmbr3/vmbr6 — the sub-interfaces (eno1.30, eno1.60) handle VLAN tagging
- **No gateway** on anything except vmbr0 — only one default gateway per host
- **Firewalla SE switch** must have the port connected to pve2 configured as a trunk port carrying VLANs 30 and 60
- **Firewalla Gold** must have VLAN 30 and VLAN 60 defined as network segments

---

## Phase 5: Windows Server 2022 VM Setup (VM 201)

### VM Hardware Configuration

| Setting | Value |
|---|---|
| Memory | 4 GiB |
| Processors | 4 (2 sockets, 2 cores) |
| BIOS | OVMF (UEFI) |
| Machine | pc-i440fx-10.0 |
| SCSI Controller | VirtIO SCSI single |
| Hard Disk | 32G on local-lvm |
| Network | virtio, bridge=vmbr3 |
| CD/DVD (ide0) | virtio-win-0.1.285.iso |
| CD/DVD (ide2) | SERVER_EVAL_x64FRE_en-us.iso |
| EFI Disk | 4M, pre-enrolled keys |
| TPM State | v2.0 |

### Network Configuration

The VM NIC is bridged to vmbr3 with **no VLAN tag** (since vmbr3 is already dedicated to VLAN 30):

```bash
qm set 201 -net0 virtio=BC:24:11:05:B3:45,bridge=vmbr3,firewall=1
```

### Issues Encountered and Resolved

#### Issue 1: No network adapter visible in Windows

**Symptom:** `ipconfig -all` showed no Ethernet adapter. Pings failed with "General failure."

**Cause:** VirtIO network drivers were not installed. Windows does not natively recognize the VirtIO NIC.

**Fix:** 
1. Open Device Manager
2. Found "Ethernet Controller" with yellow triangle under "Other devices"
3. Right-click → Update driver → Browse → pointed to the virtio-win ISO drive → included subfolders
4. NetKVM driver installed, Ethernet adapter appeared

#### Issue 2: No default gateway

**Symptom:** Could ping 192.168.30.1 (gateway) but not 8.8.8.8 or any external address. `ipconfig -all` showed Default Gateway as blank.

**Cause:** Static IP was set without specifying a default gateway.

**Fix:**
```powershell
Remove-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.30.10 -Confirm:$false
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.30.10 -PrefixLength 24 -DefaultGateway 192.168.30.1
```

#### Issue 3: DNS resolution failing

**Symptom:** `ping 8.8.8.8` succeeded but `ping google.com` failed with "could not find host." Windows Update unable to reach update servers.

**Cause:** DNS was set to 127.0.0.1 (localhost), but no DNS server was running on the machine yet (AD DS with DNS not yet installed).

**Fix:** Temporarily pointed to public DNS for pre-promotion updates:
```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 8.8.8.8,8.8.4.4
```

> **Note:** After promoting to a DC with DNS installed, DNS should be changed to:
> ```powershell
> Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1,192.168.30.1
> ```

### Final Network Configuration (pre-DC promotion)

```
IPv4 Address:      192.168.30.10
Subnet Mask:       255.255.255.0
Default Gateway:   192.168.30.1
DNS Servers:       8.8.8.8, 8.8.4.4 (temporary — will change post-promotion)
```

---

## Proxmox Snapshots

Snapshots are taken at key milestones for rollback capability:

```bash
# Pre-AD install — clean, hardened, updated server
qm snapshot 201 pre-ad-install --description "Clean server, updated, network configured"

# Post-DC promotion — clean domain controller baseline
qm snapshot 201 post-dc-promo --description "DC promoted, AD DS and DNS verified"

# After OU/GPO structure — before populating users
qm snapshot 201 ou-structure-complete --description "OUs and GPOs created"
```

---

## Lessons Learned

1. **Hostname/domain must match before cluster join.** Fixing it on a standalone node is trivial; fixing it after joining requires removing and rejoining.

2. **Certificate fingerprint for cluster join** should be pulled from the API endpoint directly (`openssl s_client -connect <ip>:8006`), not from the CA PEM file.

3. **`/etc/pve/` is a shared cluster filesystem.** No manual syncing needed between nodes — edits on either node apply everywhere.

4. **VLAN bridges without physical ports are isolated.** For VLANs to route through the Firewalla, VLAN sub-interfaces (e.g., `eno1.30`) must be added as bridge ports.

5. **Don't set vmbr IP to the network address.** `192.168.30.0/24` is invalid as a host IP — use `.1` or another valid address (or no IP at all when the Firewalla is the gateway).

6. **Only one default gateway per host.** Additional bridges (vmbr3, vmbr6) should not have a gateway configured.

7. **VirtIO drivers are not optional.** Windows VMs on Proxmox won't see network or storage devices without them. Mount the virtio-win ISO and install drivers before anything else.

8. **DNS must point to a running resolver.** Setting DNS to 127.0.0.1 before a DNS server is installed results in total name resolution failure. Use external DNS until the DC/DNS role is active.

9. **Firewalla SE does not currently support port mirroring (SPAN).** This is planned for a future release. Until then, the inline tap topology remains necessary for Security Onion.

---

## Next Steps

- [ ] Complete Windows Updates on VM 201
- [ ] Rename server to DC01
- [ ] Take pre-AD Proxmox snapshot
- [ ] Promote to domain controller (AD DS + DNS)
- [ ] Switch DNS to 127.0.0.1 post-promotion
- [ ] Take post-promotion Proxmox snapshot
- [ ] Build OU structure, security groups, and users per scenario doc
- [ ] Configure Group Policy baselines
- [ ] Revisit port mirroring migration when Firewalla SE adds SPAN support
- [ ] Set up VLAN 60 bridges and threat hunting lab
