# Quick Reference - PostgreSQL HA Cluster Commands

## 🚀 Deployment

```bash
# 1. Generate passwords (one-time setup)
./railway-setup-shared-vars.sh

# 2. Deploy cluster
./railway-deploy.sh
# Choose option 2: ProxySQL 3.0 BETA (2 instances)

# 3. View cluster info
cat cluster-info.txt
```

---

## 📈 Horizontal Scaling

### Add Node
```bash
./railway-add-node.sh 5     # Add pg-5
./railway-add-node.sh 6     # Add pg-6
```

### Remove Node
```bash
./railway-remove-node.sh 5  # Remove pg-5
# Type 'yes' to confirm
```

---

## 🔍 Monitoring

### Cluster Status
```bash
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

### Node Logs
```bash
railway logs --service pg-1 --tail 100
railway logs --service proxysql --tail 100
```

### ProxySQL Stats
```bash
railway ssh --service proxysql
psql -h 127.0.0.1 -p 6132 -U admin -d proxysql
SELECT * FROM stats_pgsql_connection_pool;
```

---

## 🔧 Troubleshooting

### Node Not Joining Cluster
```bash
# Check node logs
railway logs --service pg-5

# Check repmgr on primary
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

### ProxySQL Not Discovering Node
```bash
# Check ProxySQL logs
railway logs --service proxysql | grep pg-5

# Check ProxySQL config
railway ssh --service proxysql
cat /etc/proxysql.cnf | grep PG_NODES
```

### Manual Failover
```bash
# Promote pg-2 to primary
railway ssh --service pg-2
gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.conf
```

---

## 🗄️ Backup & Restore

### Backup
```bash
railway ssh --service pg-1
gosu postgres pg_dump -Fc postgres > /tmp/backup_$(date +%Y%m%d).dump
```

### Restore
```bash
railway ssh --service pg-1
gosu postgres pg_restore -d postgres /tmp/backup_20251027.dump
```

---

## 🔐 Security

### Change ProxySQL Admin Password
```bash
railway ssh --service proxysql
psql -h 127.0.0.1 -p 6132 -U admin -d proxysql
UPDATE global_variables SET variable_value='new_password' WHERE variable_name='admin-admin_credentials';
LOAD ADMIN VARIABLES TO RUNTIME;
SAVE ADMIN VARIABLES TO DISK;
```

### Rotate PostgreSQL Passwords
```bash
# Generate new passwords
NEW_PASS=$(openssl rand -base64 32)
railway variables --set "POSTGRES_PASSWORD=$NEW_PASS"

# Redeploy all services
./railway-deploy.sh
```

---

## 📊 Performance

### Connection Pool Stats
```bash
railway ssh --service proxysql
psql -h 127.0.0.1 -p 6132 -U admin -d proxysql
SELECT hostgroup,srv_host,status,ConnUsed,ConnFree FROM stats_pgsql_connection_pool;
```

### Query Stats
```bash
SELECT * FROM stats_pgsql_query_digest ORDER BY sum_time DESC LIMIT 10;
```

### Replication Lag
```bash
railway ssh --service pg-1
gosu postgres psql -c "SELECT client_addr,state,sync_state,replay_lag FROM pg_stat_replication;"
```

---

## 🌐 Connection Strings

### Via ProxySQL (Recommended)
```bash
# Multi-host (automatic failover)
postgresql://postgres:PASSWORD@proxysql.railway.app:5432,proxysql-2.railway.app:5432/postgres

# Single host
postgresql://postgres:PASSWORD@proxysql.railway.app:5432/postgres
```

### Direct to Primary
```bash
# Internal (Railway network only)
postgresql://postgres:PASSWORD@pg-1.railway.internal:5432/postgres

# Public (after railway domain setup)
postgresql://postgres:PASSWORD@pg-1-production.up.railway.app:5432/postgres
```

---

## 📚 Documentation Links

- Main README: [README.md](README.md)
- Scaling Guide: [SCALING_GUIDE.md](SCALING_GUIDE.md)
- Security Audit: [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
- Client Examples: [CLIENT_CONNECTION_EXAMPLES.md](CLIENT_CONNECTION_EXAMPLES.md)
- ProxySQL HA: [PROXYSQL_HA_ENDPOINT.md](PROXYSQL_HA_ENDPOINT.md)

---

## 🆘 Support

- Issues: https://github.com/hiendt2907/new_pg_cluster_clone/issues
- Railway Docs: https://docs.railway.app
- PostgreSQL Docs: https://www.postgresql.org/docs/17/
- repmgr Docs: https://repmgr.org/docs/current/
