# Netzor Stack - Serviços a Implementar

## ✅ Implementados
- [x] BunkerWeb (WAF)
- [x] FreeIPA (LDAP/Kerberos)
- [x] Keycloak (SSO/IdP)
- [x] Mail Server + Roundcube
- [x] Nextcloud AIO
- [x] GLPI (ITSM)
- [x] IRIS (DFIR)
- [x] n8n (Automation)
- [x] Guacamole (Remote Access)

---

## 🔄 Por Implementar

### Segurança / SIEM
- [ ] **Wazuh** - SIEM + XDR + Threat Detection
  - Integração com Keycloak SSO (SAML)
  - Agentes para endpoints
  - Alertas para n8n/Shuffle

### Monitorização
- [ ] **Zabbix** - Monitoring + Alerting
  - Integração com Keycloak SSO (SAML)
  - Templates para serviços existentes
  - Alertas para n8n

### Acesso Remoto (PAM)
- [ ] **JumpServer** - Privileged Access Management
  - Substituir/complementar Guacamole
  - SSO OIDC com Keycloak
  - Gravação de sessões
  - Aprovações just-in-time

### SOAR / Threat Intelligence
- [ ] **Shuffle SOAR** - Security Orchestration
  - Integração com Wazuh
  - Integração com MISP
  - Playbooks automáticos

- [ ] **MISP** - Threat Intelligence Platform
  - Feeds de IOCs
  - Integração com Wazuh
  - Partilha com comunidade

### ERP
- [ ] **ERPNext** - Enterprise Resource Planning
  - SSO OIDC com Keycloak
  - Módulos: HR, Inventory, Accounting
  - Integração com GLPI

---

## 📋 Prioridades Sugeridas

1. **Wazuh** - Base de segurança/SIEM
2. **Zabbix** - Monitorização de infraestrutura
3. **JumpServer** - PAM completo com gravação
4. **Shuffle SOAR** - Automação de resposta
5. **MISP** - Threat intelligence
6. **ERPNext** - ERP (se necessário)

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
