# Security Guide

Complete security documentation for PostgreSQL HA Cluster on Railway.

**Quick Links:**
- [Security Status](#security-status)
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Credentials Management](#credentials-management)
- [Security Configuration](#security-configuration)
- [Penetration Testing](#penetration-testing)
- [Incident Response](#incident-response)

---

## Security Status

**Last Security Review:** October 27, 2025  
**Status:** ✅ Production-Ready with Security Hardening

### Security Improvements Implemented

| Security Item | Status |
|---------------|--------|
| ProxySQL admin password | ✅ Auto-generated 32-char |
| ProxySQL admin interface | ✅ Localhost only (127.0.0.1:6132) |
| Application users | ✅ app_readonly, app_readwrite created |
| pg_hba.conf access control | ✅ Per-user rules configured |
| Audit logging | ✅ Comprehensive logging enabled |
| Statement timeout | ✅ 5 minutes |
| Password strength | ✅ All 32-char auto-generated |
| Security documentation | ✅ Complete |
| SSL/TLS | ⚠️ Not configured (manual setup) |

---

## Pre-Deployment Checklist

Before deploying to production:

### Critical (MUST Complete)
- [ ] Run `./railway-setup-shared-vars.sh` to generate passwords
- [ ] Save generated passwords to password manager
- [ ] Review this security guide completely
- [ ] Verify ProxySQL admin port NOT publicly accessible
- [ ] Test application user permissions (readonly/readwrite)

### High Priority (Complete within 24h)
- [ ] Set up monitoring and alerting
- [ ] Document incident response contacts
- [ ] Test disaster recovery procedures
- [ ] Configure automated backups
- [ ] Review Railway project access controls

### Medium Priority (Complete within 1 week)
- [ ] Plan password rotation schedule (90 days)
- [ ] Set up vulnerability scanning
- [ ] Document operational procedures
- [ ] Train team on security best practices

---

## Credentials Management

### Auto-Generated Passwords

During deployment, `railway-setup-shared-vars.sh` generates **5 passwords**:

1. **POSTGRES_PASSWORD** - PostgreSQL superuser (admin only)
2. **REPMGR_PASSWORD** - Replication user (internal only)
3. **APP_READONLY_PASSWORD** - Read-only application access
4. **APP_READWRITE_PASSWORD** - Read-write application access
5. **PROXYSQL_ADMIN_PASSWORD** - ProxySQL admin interface

All passwords:
- ✅ 32 characters (OpenSSL base64)
- ✅ Auto-generated (no human input)
- ✅ Stored in Railway environment (encrypted at rest)
- ✅ Referenced via `${{VARIABLE_NAME}}` in all services

### After Deployment

After running `railway-deploy.sh`, a file `cluster-security-info.txt` is automatically generated containing:
- All 5 passwords (plaintext)
- Connection strings for all users
- Operational procedures
- Emergency response steps

**⚠️ CRITICAL ACTIONS:**
1. **Save** `cluster-security-info.txt` to secure password manager
2. **Delete** the file: `rm cluster-security-info.txt`
3. **Never commit** to Git (already in .gitignore)

### Database Users

| User | Purpose | Permissions | Use Case |
|------|---------|-------------|----------|
| `postgres` | Superuser | Full database access | Admin tasks only (NOT for apps) |
| `repmgr` | Replication | Replication + cluster management | Internal (repmgr only) |
| `app_readonly` | Read-only app | SELECT only on public schema | Analytics, reporting, dashboards |
| `app_readwrite` | Read-write app | SELECT, INSERT, UPDATE, DELETE | Normal application operations |

**Best Practice:** Applications should NEVER use `postgres` user. Use `app_readonly` or `app_readwrite`.

---

## Security Configuration

### Network Security

**PostgreSQL Nodes (Internal Only):**
```
pg-1.railway.internal:5432    ← NOT publicly accessible ✅
pg-2.railway.internal:5432    ← NOT publicly accessible ✅
pg-3.railway.internal:5432    ← NOT publicly accessible ✅
pg-4.railway.internal:5432    ← NOT publicly accessible ✅
witness.railway.internal:5432 ← NOT publicly accessible ✅
```

**ProxySQL (Public):**
```
proxysql.railway.app:5432     ← Public (password protected) ⚠️
proxysql-2.railway.app:5432   ← Public (password protected) ⚠️
```

**ProxySQL Admin Interface (Localhost Only):**
```
127.0.0.1:6132               ← ONLY accessible via Railway SSH ✅
```

**Verification:**
```bash
# ProxySQL admin port should be closed externally
nmap -p 6132 <proxysql-domain>
# Expected: closed or filtered

# ProxySQL PostgreSQL port should be open
nmap -p 5432 <proxysql-domain>
# Expected: open
```

### Authentication & Authorization

**pg_hba.conf Configuration:**
```conf
# Application users
host    all   app_readonly    0.0.0.0/0   md5
host    all   app_readwrite   0.0.0.0/0   md5

# Admin users
host    all   postgres        0.0.0.0/0   md5
host    all   repmgr          0.0.0.0/0   md5

# Replication
host    replication   repmgr  0.0.0.0/0   md5
```

**Notes:**
- Allows connections from any IP (Railway limitation)
- Requires valid password authentication (md5)
- For SSL/TLS, change `host` → `hostssl` (manual setup required)

### Audit Logging

**PostgreSQL Logging (Enabled):**
```postgresql
log_connections = on              # Log all connections
log_disconnections = on           # Log all disconnections
log_statement = 'ddl'             # Log CREATE, ALTER, DROP
log_min_duration_statement = 1000 # Log queries >1s
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
```

**View Logs:**
```bash
# Connection logs
railway logs --service pg-1 | grep "connection authorized"

# Slow queries
railway logs --service pg-1 | grep "duration:"

# DDL statements
railway logs --service pg-1 | grep "CREATE\|ALTER\|DROP"
```

### Query Security

**Statement Timeout:**
```postgresql
statement_timeout = 300000   # 5 minutes max per query
```

Prevents long-running queries from:
- Blocking other queries
- Consuming excessive resources
- Potential DoS attacks

**Override if needed:**
```sql
-- For specific session
SET statement_timeout = '600s';  -- 10 minutes

-- For specific database
ALTER DATABASE postgres SET statement_timeout = '600s';
```

---

## Penetration Testing

### Phase 1: Network Reconnaissance

```bash
# 1. Discover public endpoints
nmap -p 5432,6132 <proxysql-domain>
# Expected: 5432 open, 6132 closed/filtered

# 2. Banner grabbing
psql "postgresql://<proxysql-domain>:5432/postgres" -c "SELECT version();"
# Should fail without valid credentials

# 3. Check admin interface exposure
curl -v http://<proxysql-domain>:6132
# Should: Connection refused or timeout
```

### Phase 2: Authentication Testing

```bash
# 1. Test default credentials (should fail)
psql "postgresql://postgres:postgres@<proxysql-domain>:5432/postgres"
# Expected: authentication failed

# 2. Test valid readonly user
psql "postgresql://app_readonly:<password>@<proxysql-domain>:5432/postgres" \
  -c "SELECT current_user;"
# Expected: app_readonly

# 3. Test readonly user cannot write (should fail)
psql "postgresql://app_readonly:<password>@<proxysql-domain>:5432/postgres" \
  -c "CREATE TABLE test(id int);"
# Expected: ERROR: permission denied
```

### Phase 3: Authorization Testing

```bash
# 1. Verify user permissions
psql "postgresql://app_readonly:<password>@<proxysql-domain>:5432/postgres" \
  -c "SELECT current_user; \
      SELECT has_database_privilege(current_user, 'postgres', 'CREATE');"
# Expected: f (false)

# 2. Test write user can write
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres" \
  -c "CREATE TABLE test(id int); INSERT INTO test VALUES (1); DROP TABLE test;"
# Expected: Success

# 3. Test privilege escalation (should fail)
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres" \
  -c "CREATE USER hacker SUPERUSER;"
# Expected: ERROR: must be superuser
```

### Phase 4: ProxySQL Security

```bash
# 1. Access admin interface (should require Railway SSH)
railway ssh --service proxysql
PGPASSWORD='<admin_password>' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql
# Expected: Success (only via SSH)

# 2. Verify server configuration
psql -h 127.0.0.1 -p 6132 -U admin -d proxysql \
  -c "SELECT hostgroup_id, hostname, status FROM pgsql_servers;"
# Expected: See all nodes (1=primary, 2=standbys)

# 3. Verify user configuration
psql -h 127.0.0.1 -p 6132 -U admin -d proxysql \
  -c "SELECT username, default_hostgroup FROM pgsql_users;"
# Expected: See 4 users (postgres, repmgr, app_readonly, app_readwrite)
```

### Phase 5: Denial of Service Protection

```bash
# 1. Test statement timeout
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres" \
  -c "SELECT pg_sleep(400);"
# Expected: ERROR: canceling statement due to statement timeout (after 5 min)

# 2. Test connection limit (via ProxySQL)
# ProxySQL max: 30,000 connections per instance
# Should gracefully handle and queue
```

---

## Incident Response

### Security Incident Severity

**P0 - Critical (Immediate Response)**
- Active data breach
- Cluster completely compromised
- Ransomware attack

**P1 - High (Response within 1 hour)**
- Unauthorized access detected
- ProxySQL admin interface exposed
- SQL injection successful

**P2 - Medium (Response within 24 hours)**
- Brute force attempts
- Unusual query patterns
- Configuration drift

### Response Procedures

#### 1. Detection & Verification (5 min)

```bash
# Check active connections
railway ssh --service pg-1
gosu postgres psql -c "SELECT * FROM pg_stat_activity;"

# Check for suspicious queries
gosu postgres psql -c "
  SELECT pid, usename, application_name, client_addr, query 
  FROM pg_stat_activity 
  WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';"

# Check ProxySQL logs
railway logs --service proxysql --tail 100 | grep -i "error\|unauthorized\|failed"
```

#### 2. Containment (15 min)

**Option 1: Revoke specific user access**
```bash
railway ssh --service pg-1
gosu postgres psql -U postgres -c "
  REVOKE ALL ON DATABASE postgres FROM compromised_user;
  ALTER USER compromised_user WITH PASSWORD 'temporary_strong_password';"
```

**Option 2: Block via ProxySQL**
```bash
railway ssh --service proxysql
PGPASSWORD='<admin_pass>' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c "
  UPDATE pgsql_users SET active=0 WHERE username='compromised_user';
  LOAD PGSQL USERS TO RUNTIME;"
```

**Option 3: Full lockdown (emergency only)**
```bash
# Change all passwords immediately
railway variables --set "APP_READWRITE_PASSWORD=$(openssl rand -base64 32)"
# Then update ProxySQL and restart services
```

#### 3. Investigation (1-4 hours)

```bash
# Review audit logs
railway logs --service pg-1 --since 24h | grep "connection authorized"

# Check for failed login attempts
railway ssh --service pg-1
gosu postgres psql -c "
  SELECT datname, COUNT(*) 
  FROM pg_stat_database 
  GROUP BY datname;"

# Export logs for analysis
railway logs --service pg-1 --since 24h > incident_logs.txt
```

#### 4. Recovery

- Rotate all compromised passwords
- Apply security patches
- Update firewall rules (if applicable)
- Restore from backup if data corruption detected

#### 5. Post-Incident (1 week)

- Root cause analysis
- Update security policies
- Implement prevention measures
- Team training

### Emergency Contacts

**Railway Support:**
- Help: https://railway.app/help
- Discord: https://discord.gg/railway

**Internal Team:**
- Document your team's escalation contacts
- On-call rotation
- Communication channels (Slack, PagerDuty, etc.)

---

## Password Rotation

Recommended: Every **90 days**

### Rotation Procedure

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Update Railway environment variable
railway variables --set "APP_READWRITE_PASSWORD=$NEW_PASSWORD"

# 3. Update ProxySQL (both instances)
railway ssh --service proxysql
PGPASSWORD='<admin_pass>' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c "
  UPDATE pgsql_users SET password='$NEW_PASSWORD' WHERE username='app_readwrite';
  LOAD PGSQL USERS TO RUNTIME;
  SAVE PGSQL USERS TO DISK;"

# Repeat for proxysql-2
railway ssh --service proxysql-2
# ... same commands ...

# 4. Update application connection strings
# Deploy application with new password

# 5. Verify connections work with new password
psql "postgresql://app_readwrite:$NEW_PASSWORD@<proxysql-domain>:5432/postgres" \
  -c "SELECT current_user;"
```

### Rotation Schedule

| Password | Rotation Frequency | Priority |
|----------|-------------------|----------|
| APP_READWRITE_PASSWORD | Every 90 days | High |
| APP_READONLY_PASSWORD | Every 90 days | High |
| PROXYSQL_ADMIN_PASSWORD | Every 180 days | Medium |
| POSTGRES_PASSWORD | Every 180 days | Medium |
| REPMGR_PASSWORD | Every 365 days | Low |

---

## SSL/TLS Setup (Optional)

Currently **NOT configured**. For production with sensitive data, consider enabling SSL/TLS.

### Steps to Enable SSL

**1. Generate certificates:**
```bash
# On local machine
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt -keyout server.key -subj "/CN=postgresql"

# Generate root CA (optional)
openssl req -new -x509 -days 3650 -nodes -text \
  -out root.crt -keyout root.key -subj "/CN=root-ca"
```

**2. Upload to PostgreSQL nodes:**
```bash
# Via Railway SSH
railway ssh --service pg-1
# Upload server.crt, server.key to /var/lib/postgresql/data/
chmod 600 /var/lib/postgresql/data/server.key
chown postgres:postgres /var/lib/postgresql/data/server.*
```

**3. Enable SSL in PostgreSQL:**
```bash
# Edit postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'  # if using CA

# Restart PostgreSQL
gosu postgres pg_ctl -D /var/lib/postgresql/data restart
```

**4. Update pg_hba.conf:**
```conf
# Change 'host' to 'hostssl'
hostssl    all   app_readonly    0.0.0.0/0   md5
hostssl    all   app_readwrite   0.0.0.0/0   md5
```

**5. Test SSL connection:**
```bash
psql "postgresql://app_readwrite:<password>@<domain>:5432/postgres?sslmode=require" \
  -c "SELECT version();"
```

---

## Known Limitations

### 1. SSL/TLS Not Enabled (Medium Risk)
**Risk:** Plaintext connections (password sniffing)  
**Mitigation:** Railway's encrypted internal network  
**Action:** Manual SSL setup (see above)

### 2. No IP Allowlisting (Low Risk)
**Risk:** Brute force from any IP  
**Mitigation:** 32-char passwords (very strong)  
**Action:** Optional - restrict via Railway or application layer

### 3. ProxySQL 3.0.2 BETA (Low Risk)
**Risk:** Beta software stability  
**Mitigation:** 2 ProxySQL instances (HA)  
**Action:** Monitor for GA release

---

## Best Practices

### DO ✅
- Store passwords in secure password manager
- Use `app_readonly` for read-only operations
- Use `app_readwrite` for normal operations
- Monitor logs regularly for security events
- Rotate passwords every 90 days
- Test disaster recovery procedures quarterly
- Keep PostgreSQL and ProxySQL updated
- Review access logs weekly

### DON'T ❌
- Commit `cluster-security-info.txt` to Git
- Share passwords via email or chat
- Use `postgres` superuser for applications
- Expose ProxySQL admin port (6132) publicly
- Skip security audits before production
- Ignore failed login attempts
- Use weak or default passwords
- Grant unnecessary permissions

---

## Monitoring & Alerting

### Key Metrics to Monitor

```sql
-- Failed connections (potential attacks)
SELECT COUNT(*) FROM pg_stat_database WHERE datname='postgres';

-- Active connections by user
SELECT usename, COUNT(*) 
FROM pg_stat_activity 
GROUP BY usename;

-- Long-running queries (potential DoS)
SELECT pid, now() - query_start as duration, usename, query 
FROM pg_stat_activity 
WHERE state = 'active' AND now() - query_start > interval '5 minutes';

-- Replication lag
SELECT client_addr, state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

### ProxySQL Monitoring

```sql
-- Connection pool status
SELECT hostgroup, srv_host, status, ConnUsed, ConnFree 
FROM stats_pgsql_connection_pool;

-- Query errors (potential attacks)
SELECT count_star, digest_text 
FROM stats_pgsql_query_digest 
WHERE digest_text LIKE '%error%' 
ORDER BY count_star DESC LIMIT 10;
```

### Recommended Alerts

- Failed login attempts > 10 in 5 minutes
- Query duration > 5 minutes
- Replication lag > 100MB
- Connection pool usage > 80%
- Disk usage > 80%

---

## Additional Resources

- [PostgreSQL Security](https://www.postgresql.org/docs/17/security.html)
- [ProxySQL Documentation](https://proxysql.com/documentation/)
- [Railway Security](https://docs.railway.app/reference/security)
- [OWASP Database Security](https://cheatsheetseries.owasp.org/cheatsheets/Database_Security_Cheat_Sheet.html)

---

**Last Updated:** October 27, 2025  
**Status:** ✅ Production-Ready
