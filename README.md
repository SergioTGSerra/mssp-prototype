# 🚀 Netzor Script v2

**Automated Infrastructure Deployment for Self-Hosted Enterprise Services**

A comprehensive shell script suite that deploys a fully integrated, enterprise-grade infrastructure stack using **Podman containers**. Deploy identity management, authentication, email, ERP, cloud storage, ITSM, PAM, and security services sequentially with a single command.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Components](#-components)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Service Details](#-service-details)
- [Network Architecture](#-network-architecture)
- [Post-Installation](#-post-installation)
- [Troubleshooting](#-troubleshooting)

---

## 🌐 Overview

Netzor Script v2 automates the deployment of a complete self-hosted infrastructure with:

| Feature | Description |
|---------|-------------|
| 🔐 **Single Sign-On (SSO)** | Centralized authentication via Keycloak |
| 👤 **Identity Management** | FreeIPA for LDAP and user management |
| 📧 **Email Services** | Stalwart All-in-one Mail Server |
| 🏢 **ERP & HRMS** | ERPNext & Frappe for business management |
| ☁️ **Cloud Storage** | Nextcloud with office and collaboration tools |
| 🛡️ **Web Application Firewall** | BunkerWeb for security and reverse proxy |
| 🎛️ **Privileged Access** | JumpServer for PAM and secure infrastructure access |
| 📈 **Monitoring & ITSM** | Zabbix for monitoring, GLPI for asset management |
| 🔍 **Incident Response** | IRIS for Digital Forensics and Incident Response |

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   BunkerWeb (WAF / Reverse Proxy)               │
│                     waf.yourdomain.com                          │
│                   Ports: 80, 443 (HTTP/HTTPS)                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  FreeIPA    │     │  Keycloak   │     │  Nextcloud  │
│  (LDAP)     │ ◄── │  (SSO/OIDC) │ ──► │  (Cloud)    │
└─────────────┘     └─────────────┘     └─────────────┘
         │                   │                   │
         │                   ▼                   │
         │          ┌─────────────┐              │
         └────────► │  Stalwart   │ ◄────────────┘
                    │ Mail Server │
                    └─────────────┘
```

---

## 🧩 Components

### Core Infrastruture Services

| Service | Image | Description |
|---------|-------|-------------|
| **BunkerWeb** | `bunkerity/bunkerweb-all-in-one:1.6.7` | Web Application Firewall & Reverse Proxy |
| **FreeIPA** | `quay.io/freeipa/freeipa-server:rocky-9` | Identity & Access Management (LDAP/Kerberos) |
| **Keycloak** | `quay.io/keycloak/keycloak:26.5` | OpenID Connect (OIDC) / SSO Provider |
| **Stalwart** | `stalwartlabs/stalwart:v0.15.5-alpine` | All-in-one Modern Mail Server |
| **Nextcloud** | `ghcr.io/nextcloud-releases/aio-*` | File Sync & Collaboration Platform |

### Additional Business & Security Services

| Service | Description |
|---------|-------------|
| **ERPNext** | ERP & HRMS System built on Frappe Framework |
| **GLPI** | IT Asset Management & Helpdesk |
| **IRIS** | Digital Forensics & Incident Response |
| **JumpServer** | Privileged Access Management (PAM) |
| **Zabbix** | Infrastructure Monitoring & Alerting |

---

## ⚙️ Prerequisites

### System Requirements

- **OS**: Linux (Debian/Ubuntu, RHEL/CentOS/Fedora)
- **RAM**: Minimum 16GB (32GB+ recommended)
- **Storage**: 100GB+ available disk space
- **Network**: Public IP with DNS records configured

### Required Ports

| Port | Service |
|------|---------|
| 80/443 | HTTP/HTTPS (BunkerWeb) |
| 25, 465, 587 | SMTP (Mail) |
| 110, 995 | POP3 (Mail) |
| 143, 993 | IMAP (Mail) |
| 4190 | ManageSieve (Mail) |
| 389, 636 | LDAP/LDAPS (FreeIPA) |
| 88, 464 | Kerberos (FreeIPA) |
| 2222 | JumpServer SSH Access |

### DNS Configuration

Before running the script, configure the following DNS records pointing to your server:

```
waf.yourdomain.com       → Your Server IP
ipa.yourdomain.com       → Your Server IP
auth.yourdomain.com      → Your Server IP
mail.yourdomain.com      → Your Server IP
cloud.yourdomain.com     → Your Server IP
erp.yourdomain.com       → Your Server IP
glpi.yourdomain.com      → Your Server IP
iris.yourdomain.com      → Your Server IP
jms.yourdomain.com       → Your Server IP
zabbix.yourdomain.com    → Your Server IP
```

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/netzor-script-v2.git
cd netzor-script-v2
```

### 2. Configure Environment

Edit the `.env` file with your domain and credentials:

```bash
nano .env
```

**Key settings to change:**

```env
DOMAIN=yourdomain.com

# Main Admin User (created in ERPNext, JumpServer etc)
MAIN_USER_USERNAME=admin
MAIN_USER_PASSWORD=YourSecurePassword

# BunkerWeb
BUNKERWEB_HOSTNAME=waf.yourdomain.com
BUNKERWEB_ADMIN_PASSWORD=YourSecurePassword

# FreeIPA
FREEIPA_HOSTNAME=ipa.yourdomain.com
FREEIPA_ADMIN_PASSWORD=YourSecurePassword

# Keycloak
KEYCLOAK_HOSTNAME=auth.yourdomain.com
KEYCLOAK_ADMIN_PASSWORD=YourSecurePassword
```

### 3. Run Installation

```bash
chmod +x setup.sh
./setup.sh
```

The script will automatically check for prerequisites and sequentially deploy:
1. **01_bunkerweb**: Web Application Firewall (WAF)
2. **02_freeipa**: LDAP and Identity Management
3. **03_keycloak**: Single Sign-On / OIDC
4. **04_stalwart**: Mail Server
5. **05_frappe**: ERPNext & HRMS
6. **06_glpi**: IT Asset Management
7. **07_iris**: DFIR Platform
8. **08_jumpserver**: PAM Solution
9. **09_nextcloud-aio**: Cloud Storage
10. **10_zabbix**: Infrastructure Monitoring

---

## 🔧 Configuration

### Environment Variables

The `.env` file contains all configuration options:

#### Global Settings
| Variable | Description |
|----------|-------------|
| `DOMAIN` | Primary domain name |

#### Service Hostnames
| Variable | Description |
|----------|-------------|
| `BUNKERWEB_HOSTNAME` | WAF hostname |
| `FREEIPA_HOSTNAME` | IPA server hostname |
| `KEYCLOAK_HOSTNAME` | Auth server hostname |
| `MAILSERVER_HOSTNAME` | Mail server hostname |
| `NEXTCLOUD_HOSTNAME` | Cloud storage hostname |
| `FRAPPE_HOSTNAME` | ERP server hostname |

---

## 🌐 Network Architecture

The infrastructure uses isolated Podman networks for security:

| Network | Purpose | Connected Services |
|---------|---------|-------------------|
| `waf_default` | Public-facing services | BunkerWeb, Keycloak, Nextcloud, JumpServer, Stalwart, etc. |
| `ipa_default` | Identity services | FreeIPA, Keycloak |
| `stalwart_default` | Email services | Stalwart Mail Server |
| `jumpserver_default` | PAM services | JumpServer Core & DB components |

---

## 📖 Service Details

### BunkerWeb (WAF)

Web Application Firewall and reverse proxy with built-in security features:
- **Automatic HTTPS**: SSL/TLS certificate management
- **Multi-site Support**: Routes traffic to all backend services

### FreeIPA

Enterprise-grade identity management:
- **LDAP Directory**: Centralized user/group storage
- **System Accounts**: Special groups for service binding accounts (e.g., mailserver-bind, jumpserver-bind)

### Keycloak

Modern authentication platform:
- **LDAP Federation**: Syncs users from FreeIPA
- **OIDC/OAuth2**: Provides SSO for Nextcloud, ERPNext, Stalwart, and others

### Stalwart Mail Server

Robust and modern all-in-one mail server:
- **LDAP/OIDC Authentication**: Native integration with FreeIPA and Keycloak
- Supports IMAP, SMTP, POP3, and ManageSieve

### ERPNext & Frappe

Full-featured business management:
- Integrated HRMS, CRM, and accounting modules
- Configured out-of-the-box with Keycloak SSO login

### JumpServer (PAM)

Open-source Privileged Access Management:
- Enforces secure remote access to web assets and infrastructure
- Authenticates users via FreeIPA LDAP directory

### Nextcloud

Cloud storage with collaboration features:
- **Office Integration**: Collabora/OnlyOffice support
- **OIDC Login**: SSO via Keycloak

---

## 📝 Post-Installation

### Access Your Services

After installation, access your core services at:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **BunkerWeb Admin** | `https://waf.yourdomain.com` | From `.env` |
| **FreeIPA Admin** | `https://ipa.yourdomain.com` | admin / `FREEIPA_ADMIN_PASSWORD` |
| **Keycloak Admin** | `https://auth.yourdomain.com` | admin / `KEYCLOAK_ADMIN_PASSWORD` |
| **ERPNext** | `https://erp.yourdomain.com` | `MAIN_USER` / Keycloak SSO |
| **Nextcloud** | `https://cloud.yourdomain.com` | Keycloak SSO |

### Creating Users

1. Log into **FreeIPA** admin console
2. Navigate to **Identity → Users**
3. Click **Add** and fill in user details
4. Ensure the user has an email attribute set

Users will automatically sync to Keycloak (via LDAP federation) and to LDAP clients like JumpServer and Stalwart Mail Server.

### Verify Services

Check container status:
```bash
podman ps -a
```

Check container logs:
```bash
podman logs <container-name>
```

---

## 🔍 Troubleshooting

### Common Issues

#### FreeIPA fails to start
- Ensure ports 389, 636, 88, 464 are not in use
- Check if hostname is correctly set in `/etc/hosts`

#### Keycloak can't connect to FreeIPA
- Ensure FreeIPA is healthy. Check FreeIPA container state.

#### Mail not working
- Verify MX records point to your server's IP
- Check Stalwart logs: `podman logs mailserver`

### Useful Commands

```bash
# List all containers
podman ps -a

# View container logs
podman logs -f <container-name>

# Restart a service
podman restart <container-name>

# View all networks
podman network ls
```

---

## 📁 Project Structure

```
netzor-script-v2/
├── .env                    # Environment configuration
├── setup.sh                # Main installation script
├── prerequisites.sh        # Dependency installer
├── utils.sh                # Helper functions
├── 01_bunkerweb/           # BunkerWeb WAF deployment
├── 02_freeipa/             # FreeIPA deployment
├── 03_keycloak/            # Keycloak deployment
├── 04_stalwart/            # Stalwart Mail Server
├── 05_frappe/              # ERPNext / Frappe deployment
├── 06_glpi/                # GLPI ITSM deployment
├── 07_iris/                # DFIR IRIS deployment
├── 08_jumpserver/          # JumpServer PAM
├── 09_nextcloud-aio/       # Nextcloud deployment
└── 10_zabbix/              # Zabbix Monitoring
```

---

## 📄 License

This project is open-source. Feel free to use, modify, and distribute.

---

## 🤝 Contributing

Contributions are welcome! Please submit issues and pull requests on GitHub.

---

<p align="center">
  Made with ❤️ by the Netzor Team
</p>
