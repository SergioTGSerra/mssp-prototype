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
- [x] JumpServer (PAM)
- [x] ERPNext (ERP)

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


### SOAR / Threat Intelligence
- [ ] **Shuffle SOAR** - Security Orchestration
  - Integração com Wazuh
  - Integração com MISP
  - Playbooks automáticos

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

1. **Wazuh** - Base de segurança/SIEM
2. **Zabbix** - Monitorização de infraestrutura
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
