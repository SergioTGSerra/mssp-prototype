# 🚀 Netzor Script v2

**Automated Infrastructure Deployment for Self-Hosted Enterprise Services**

A comprehensive shell script suite that deploys a fully integrated, enterprise-grade infrastructure stack using **Podman containers**. Deploy identity management, authentication, email, cloud storage, and security services with a single command.

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
| 📧 **Email Services** | Full mail server with webmail client |
| ☁️ **Cloud Storage** | Nextcloud with office integration |
| 🛡️ **Web Application Firewall** | BunkerWeb for security and reverse proxy |
| 🔄 **Workflow Automation** | n8n for process automation |
| 🖥️ **Remote Access** | Apache Guacamole for remote desktop |

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
         └────────► │ Mailserver  │ ◄────────────┘
                    │ + Roundcube │
                    └─────────────┘
```

---

## 🧩 Components

### Core Services

| Service | Image | Description |
|---------|-------|-------------|
| **BunkerWeb** | `bunkerity/bunkerweb-all-in-one:1.6.7` | Web Application Firewall & Reverse Proxy |
| **FreeIPA** | `quay.io/freeipa/freeipa-server:rocky-9` | Identity & Access Management (LDAP/Kerberos) |
| **Keycloak** | `quay.io/keycloak/keycloak:26.5` | OpenID Connect (OIDC) / SSO Provider |
| **Mailserver** | `ghcr.io/docker-mailserver/docker-mailserver:15.1.0` | SMTP/IMAP Mail Server |
| **Roundcube** | `roundcube/roundcubemail:1.6.12-apache` | Webmail Client |
| **Nextcloud** | `ghcr.io/nextcloud-releases/aio-*` | File Sync & Collaboration Platform |

### Optional Services

| Service | Description |
|---------|-------------|
| **GLPI** | IT Asset Management & Helpdesk |
| **IRIS** | Digital Forensics & Incident Response |
| **Guacamole** | Clientless Remote Desktop Gateway |
| **n8n** | Workflow Automation Platform |

---

## ⚙️ Prerequisites

### System Requirements

- **OS**: Linux (Debian/Ubuntu, RHEL/CentOS/Fedora)
- **RAM**: Minimum 8GB (16GB+ recommended)
- **Storage**: 50GB+ available disk space
- **Network**: Public IP with DNS records configured

### Required Ports

| Port | Service |
|------|---------|
| 80/443 | HTTP/HTTPS (BunkerWeb) |
| 25, 465, 587 | SMTP (Mail) |
| 143, 993 | IMAP (Mail) |
| 389, 636 | LDAP/LDAPS (FreeIPA) |
| 88, 464 | Kerberos (FreeIPA) |

### DNS Configuration

Before running the script, configure the following DNS records pointing to your server:

```
waf.yourdomain.com       → Your Server IP
ipa.yourdomain.com       → Your Server IP
auth.yourdomain.com      → Your Server IP
mail.yourdomain.com      → Your Server IP
webmail.yourdomain.com   → Your Server IP
cloud.yourdomain.com     → Your Server IP
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

The script will:
1. ✅ Install prerequisites (Podman, jq, podman-compose)
2. ✅ Deploy BunkerWeb (WAF/Reverse Proxy)
3. ✅ Deploy FreeIPA (Identity Management)
4. ✅ Deploy Keycloak (SSO/OIDC)
5. ✅ Deploy Mail Services (Mailserver + Roundcube)
6. ✅ Deploy Nextcloud (Cloud Storage)

---

## 🔧 Configuration

### Environment Variables

The `.env` file contains all configuration options:

#### Global Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Primary domain name | `netzor.pt` |

#### BunkerWeb
| Variable | Description |
|----------|-------------|
| `BUNKERWEB_HOSTNAME` | WAF hostname |
| `BUNKERWEB_ADMIN_USERNAME` | Admin username |
| `BUNKERWEB_ADMIN_PASSWORD` | Admin password |

#### FreeIPA
| Variable | Description |
|----------|-------------|
| `FREEIPA_HOSTNAME` | IPA server hostname |
| `FREEIPA_REALM` | Kerberos realm |
| `FREEIPA_ADMIN_PASSWORD` | Admin password |
| `FREEIPA_DS_PASSWORD` | Directory Server password |

#### Keycloak
| Variable | Description |
|----------|-------------|
| `KEYCLOAK_HOSTNAME` | Auth server hostname |
| `KEYCLOAK_ADMIN_USERNAME` | Admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Admin password |

#### Mail Services
| Variable | Description |
|----------|-------------|
| `MAILSERVER_HOSTNAME` | Mail server hostname |
| `ROUNDCUBE_HOSTNAME` | Webmail hostname |

#### Nextcloud
| Variable | Description |
|----------|-------------|
| `NEXTCLOUD_HOSTNAME` | Cloud storage hostname |
| `NEXTCLOUD_ADMIN_USER` | Admin username |
| `NEXTCLOUD_ADMIN_PASSWORD` | Admin password |

---

## 🌐 Network Architecture

The infrastructure uses isolated Podman networks for security:

| Network | Purpose | Connected Services |
|---------|---------|-------------------|
| `waf` | Public-facing services | BunkerWeb, Keycloak, Nextcloud, Roundcube |
| `ipa` | Identity services | FreeIPA, Keycloak, Mailserver |
| `keycloak-network` | Authentication | Keycloak, Keycloak-Postgres |
| `mail-network` | Email services | Mailserver, Roundcube, Nextcloud |

---

## 📖 Service Details

### BunkerWeb (WAF)

Web Application Firewall and reverse proxy with built-in security features:

- **Country Whitelisting**: Configured for PT (Portugal) by default
- **IP Whitelisting**: Internal network (10.0.0.0/8)
- **Multi-site Support**: Routes traffic to all backend services
- **Automatic HTTPS**: SSL/TLS certificate management

### FreeIPA

Enterprise-grade identity management:

- **LDAP Directory**: Centralized user/group storage
- **Kerberos Authentication**: Single sign-on for services
- **System Accounts Group**: Special group for service accounts with no password expiry

### Keycloak

Modern authentication platform:

- **LDAP Federation**: Syncs users from FreeIPA
- **OIDC/OAuth2**: Provides SSO for Nextcloud, Roundcube, and Mail
- **Client Management**: Pre-configured clients for all services

### Mail Server

Full-featured email platform:

- **LDAP Authentication**: Users authenticate via FreeIPA
- **OAuth2 Support**: Token-based authentication via Keycloak
- **Anti-spam/Anti-virus**: Rspamd and ClamAV integration
- **Fail2ban**: Brute-force protection

### Nextcloud

Cloud storage with collaboration features:

- **Office Integration**: Collabora/OnlyOffice support
- **Talk**: Video conferencing
- **OIDC Login**: SSO via Keycloak
- **Full-text Search**: Elasticsearch integration

---

## 📝 Post-Installation

### Access Your Services

After installation, access your services at:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **BunkerWeb Admin** | `https://waf.yourdomain.com` | `.env` credentials |
| **FreeIPA Admin** | `https://ipa.yourdomain.com` | admin / FREEIPA_ADMIN_PASSWORD |
| **Keycloak Admin** | `https://auth.yourdomain.com` | admin / KEYCLOAK_ADMIN_PASSWORD |
| **Roundcube** | `https://webmail.yourdomain.com` | FreeIPA user credentials |
| **Nextcloud** | `https://cloud.yourdomain.com` | admin / NEXTCLOUD_ADMIN_PASSWORD |

### Creating Users

1. Log into **FreeIPA** admin console
2. Navigate to **Identity → Users**
3. Click **Add** and fill in user details
4. Ensure the user has an email attribute set

Users will automatically be available in Keycloak (via LDAP federation) and can log into all services.

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
- Review logs: `podman logs freeipa`

#### Keycloak can't connect to FreeIPA
- Verify the `ipa` network exists: `podman network ls`
- Check FreeIPA is healthy: `podman inspect freeipa --format='{{.State.Health.Status}}'`

#### Mail not working
- Verify MX records point to your server
- Check SPF, DKIM, and DMARC records
- Review logs: `podman logs mailserver`

#### SSL/TLS certificate issues
- Ensure DNS records are correctly configured
- Check BunkerWeb logs: `podman logs bunkerweb`

### Useful Commands

```bash
# List all containers
podman ps -a

# View container logs
podman logs -f <container-name>

# Restart a service
podman restart <container-name>

# Check network connectivity
podman exec <container> ping <hostname>

# View all networks
podman network ls

# Inspect a network
podman network inspect <network-name>
```

---

## 📁 Project Structure

```
netzor-script-v2/
├── .env                    # Environment configuration
├── setup.sh                # Main installation script
├── prerequisites.sh        # Dependency installer
├── utils.sh                # Helper functions
├── bunkerweb/
│   ├── setup.sh            # BunkerWeb deployment
│   └── configs/            # Service-specific WAF configs
├── freeipa/
│   └── setup.sh            # FreeIPA deployment
├── keycloak/
│   ├── setup.sh            # Keycloak deployment
│   └── compose.yaml        # Docker Compose definition
├── mail/
│   ├── setup.sh            # Mail services deployment
│   ├── compose.yaml        # Docker Compose definition
│   └── oauth2.inc.php      # Roundcube OAuth2 config
├── nextcloud/
│   ├── setup.sh            # Nextcloud deployment
│   ├── compose.yaml        # Docker Compose definition
│   └── apps/               # Custom Nextcloud apps
├── glpi/                   # GLPI (optional)
├── iris/                   # DFIR IRIS (optional)
├── guacamole/              # Apache Guacamole (optional)
└── n8n/                    # n8n automation (optional)
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
