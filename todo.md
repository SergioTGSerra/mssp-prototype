# Netzor Stack - Serviços a Implementar

## ✅ Implementados
- [x] BunkerWeb (WAF)
- [x] FreeIPA (LDAP/Kerberos)
- [x] Keycloak (SSO/IdP)
- [x] Stalwart (Mail Server)
- [x] Nextcloud AIO
- [x] ERPNext (ERP / Frappe HRMS)
- [x] GLPI (ITSM)
- [x] IRIS (DFIR)
- [x] JumpServer (PAM)
- [x] Zabbix (Monitoring)

---

## 🔄 Por Implementar

### Segurança / SIEM
- [ ] **Wazuh** - SIEM + XDR + Threat Detection
  - Integração com Keycloak SSO (SAML)
  - Agentes para endpoints
  - Alertas para n8n/Shuffle

### Acesso Remoto / Redes
- [ ] **Netbird** - Zero Trust Networking / VPN
  - Rede Mesh Privada
  - Integração com Keycloak (SSO)
- [ ] **Guacamole** - Clientless Remote Desktop Gateway

### Automação / SOAR
- [ ] **n8n** - Workflow Automation Platform
- [ ] **Shuffle SOAR** - Security Orchestration
  - Integração com Wazuh
  - Integração com MISP
  - Playbooks automáticos

### Threat Intelligence
- [ ] **MISP** - Threat Intelligence Platform
  - Feeds de IOCs
  - Integração com Wazuh
  - Partilha com comunidade

### Outros / Documentação
- [ ] **BookStack** - Wiki / Documentação
  - Organização de manuais e playbooks
  - Integração com Keycloak SSO

---

## 📋 Prioridades Sugeridas

1. **Netbird** - Rede seguras
2. **Wazuh** - Base de segurança/SIEM
3. **Shuffle SOAR** - Automação de resposta
4. **MISP** - Threat intelligence
5. **BookStack** - Documentação

---

## 🔗 Integrações Planeadas

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Wazuh     │────▶│   Shuffle   │────▶│    n8n      │
│   (SIEM)    │     │   (SOAR)    │     │ (Automation)│
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│    MISP     │     │    IRIS     │
│   (CTI)     │     │   (DFIR)    │
└─────────────┘     └─────────────┘

┌─────────────┐     ┌─────────────┐
│   Zabbix    │────▶│  Keycloak   │◀──── Todos os serviços
│ (Monitoring)│     │   (SSO)     │
└─────────────┘     └─────────────┘
```
