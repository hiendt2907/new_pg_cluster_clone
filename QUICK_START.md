# Quick Start Guide

Get your PostgreSQL HA cluster running in **5 minutes**.

---

## Prerequisites

- Railway account ([sign up free](https://railway.app/))
- Railway CLI installed:
  ```bash
  curl -fsSL https://railway.app/install.sh | sh
  ```

---

## Step 1: Clone & Setup (30 seconds)

```bash
# Clone repository
git clone https://github.com/hiendt2907/new_pg_cluster_clone.git
cd new_pg_cluster_clone

# Login to Railway
railway login

# Create new project or link existing
railway link
```

---

## Step 2: Generate Passwords (10 seconds)

```bash
./railway-setup-shared-vars.sh
```

**Output:**
```
[SUCCESS] Generated: POSTGRES_PASSWORD (32 chars)
[SUCCESS] Generated: REPMGR_PASSWORD (32 chars)
[SUCCESS] Generated: APP_READONLY_PASSWORD (32 chars)
[SUCCESS] Generated: APP_READWRITE_PASSWORD (32 chars)
[SUCCESS] Generated: PROXYSQL_ADMIN_PASSWORD (32 chars)

⚠️  Save these passwords securely!
```

**Note:** Passwords are automatically stored in Railway environment variables.

---

## Step 3: Deploy Cluster (3-5 minutes)

```bash
./railway-deploy.sh
```

**Choose ProxySQL option:**
```
Select connection pooling solution:
1) No proxy (direct connections)
2) ProxySQL 3.0 BETA (2 instances for HA)  ← Choose this
3) pgpool-II

Your choice: 2
```

**Deployment Progress:**
```
[INFO] Deploying primary node (pg-1)...
[INFO] Deploying witness node...
[INFO] Deploying standby nodes (pg-2, pg-3, pg-4)...
[INFO] Deploying ProxySQL instances...
[SUCCESS] All services deployed!
```

---

## Step 4: Save Credentials (30 seconds)

After deployment completes, you'll see:

```bash
cat cluster-security-info.txt
```

**This file contains:**
- All 5 passwords (plaintext)
- Connection strings (PostgreSQL, Python, Node.js)
- ProxySQL admin commands
- Operational procedures

**⚠️ CRITICAL:**
1. **Save** this file to your password manager (1Password, LastPass, etc.)
2. **Delete** the local file:
   ```bash
   rm cluster-security-info.txt
   ```
3. **Never commit** to Git (already in .gitignore)

---

## Step 5: Get Public URL (30 seconds)

```bash
# Get ProxySQL public domain
railway service proxysql
railway domain
```

**Output:**
```
Service: proxysql
Domain: proxysql-production-abc123.up.railway.app
```

**Copy this domain** - you'll need it for connections.

---

## Step 6: Connect! (10 seconds)

### Using psql

```bash
# Replace <password> and <domain> with your values
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres"
```

**Example:**
```bash
psql "postgresql://app_readwrite:xYz123...@proxysql-production-abc123.up.railway.app:5432/postgres"
```

### Test Query

```sql
-- Check connection
SELECT current_user, version();

-- Create test table
CREATE TABLE test (id serial PRIMARY KEY, name text);
INSERT INTO test (name) VALUES ('Hello from Railway!');
SELECT * FROM test;

-- Cleanup
DROP TABLE test;
```

---

## ✅ Verification

### 1. Check Cluster Status

```bash
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Expected Output:**
```
 ID | Name    | Role    | Status    | Upstream | Location
----+---------+---------+-----------+----------+----------
  1 | pg-1    | primary | * running |          | default
  2 | pg-2    | standby |   running | pg-1     | default
  3 | pg-3    | standby |   running | pg-1     | default
  4 | pg-4    | standby |   running | pg-1     | default
 99 | witness | witness | * running | pg-1     | default
```

### 2. Check ProxySQL Status

```bash
railway ssh --service proxysql

# Access ProxySQL admin (get password from cluster-security-info.txt)
PGPASSWORD='<admin_password>' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql

# Check servers
SELECT hostgroup_id, hostname, status, Queries, Latency_us 
FROM stats_pgsql_connection_pool;
```

**Expected Output:**
```
 hostgroup_id |        hostname          | status  | Queries | Latency_us
--------------+--------------------------+---------+---------+-----------
            1 | pg-1.railway.internal    | ONLINE  |     123 |       250
            2 | pg-2.railway.internal    | ONLINE  |      45 |       180
            2 | pg-3.railway.internal    | ONLINE  |      67 |       200
            2 | pg-4.railway.internal    | ONLINE  |      89 |       190
```

### 3. Test Read/Write Splitting

```bash
# Write query (goes to primary)
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres" \
  -c "INSERT INTO test (name) VALUES ('write test');"

# Read query (goes to standbys)
psql "postgresql://app_readonly:<password>@<proxysql-domain>:5432/postgres" \
  -c "SELECT * FROM test;"
```

---

## 🎯 What's Next?

### For Development
```bash
# View logs
railway logs --service pg-1
railway logs --service proxysql

# Monitor cluster
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

### For Production

1. **Review Security:**
   ```bash
   # Read security guide
   cat SECURITY.md
   
   # Verify ProxySQL admin port NOT public
   nmap -p 6132 <proxysql-domain>  # Should be closed
   ```

2. **Set Up Monitoring:**
   - Railway metrics dashboard
   - Custom alerts (connections, query latency, replication lag)

3. **Plan Scaling:**
   ```bash
   # Add more PostgreSQL nodes
   ./railway-add-node.sh 5  # Adds pg-5
   
   # Read scaling guide
   cat SCALING_GUIDE.md
   ```

4. **Document Procedures:**
   - Password rotation (every 90 days)
   - Backup/restore testing
   - Incident response

---

## 🆘 Troubleshooting

### Issue: Can't connect to database

**Check 1:** Verify ProxySQL domain
```bash
railway service proxysql
railway domain
```

**Check 2:** Test connection
```bash
psql "postgresql://app_readwrite:<password>@<domain>:5432/postgres" -c "SELECT 1;"
```

**Check 3:** View logs
```bash
railway logs --service proxysql
```

### Issue: Cluster not forming

**Check 1:** View pg-1 logs
```bash
railway logs --service pg-1
```

**Check 2:** SSH into pg-1
```bash
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Check 3:** Verify environment variables
```bash
railway variables
```

### Issue: Permission denied

**Cause:** Using wrong user or password

**Solution:**
```bash
# Read-only user can only SELECT
psql "postgresql://app_readonly:<password>@<domain>:5432/postgres"

# Read-write user can INSERT/UPDATE/DELETE
psql "postgresql://app_readwrite:<password>@<domain>:5432/postgres"

# Superuser (admin only, NOT for apps)
psql "postgresql://postgres:<password>@<domain>:5432/postgres"
```

---

## 📚 Documentation

| File | Description |
|------|-------------|
| [README.md](README.md) | Complete architecture and configuration guide |
| [SECURITY.md](SECURITY.md) | Security guide, penetration testing, incident response |
| [SCALING_GUIDE.md](SCALING_GUIDE.md) | How to add/remove PostgreSQL nodes |

---

## 💡 Quick Reference

### Railway CLI Commands
```bash
# View all services
railway status

# Switch service
railway service <service-name>

# View logs
railway logs --service <service-name>

# SSH into service
railway ssh --service <service-name>

# Get public domain
railway domain

# Environment variables
railway variables
railway variables --set "KEY=value"
```

### PostgreSQL Commands
```bash
# Inside container (after railway ssh)
gosu postgres psql -U postgres

# Check cluster status
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Check replication
gosu postgres psql -c "SELECT * FROM pg_stat_replication;"
```

### ProxySQL Commands
```bash
# Access admin interface (Railway SSH only)
railway ssh --service proxysql
PGPASSWORD='<admin_pass>' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql

# Useful queries
SELECT * FROM stats_pgsql_connection_pool;
SELECT * FROM pgsql_servers;
SELECT * FROM pgsql_users;
SELECT * FROM stats_pgsql_query_digest ORDER BY sum_time DESC LIMIT 10;
```

---

## 🚀 You're All Set!

Your PostgreSQL HA cluster is now running with:
- ✅ 4 PostgreSQL nodes + witness
- ✅ 2 ProxySQL instances (60,000 connections)
- ✅ Automatic failover
- ✅ Query routing (write→primary, read→standbys)
- ✅ Security hardening (strong passwords, audit logging)

**Next Steps:**
1. Build your application
2. Review [SECURITY.md](SECURITY.md) before production
3. Set up monitoring and alerts
4. Test disaster recovery procedures

**Need help?** Check the full [README.md](README.md) or open an issue on GitHub.

---

**Last Updated:** October 27, 2025  
**Railway Platform:** https://railway.app  
**PostgreSQL Docs:** https://www.postgresql.org/docs/17/
