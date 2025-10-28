# Quick Start Guide

Get your PostgreSQL HA cluster running in **5 minutes** with **secure auto-generated passwords**.

---

## Prerequisites

- Docker 20.10+ & Docker Compose 2.0+
- 4GB+ RAM
- 20GB+ disk space
- `openssl` command (for password generation)

---

## Step 1: Clone & Setup (30 seconds)

```bash
# Clone repository
git clone https://github.com/hiendt2907/new_pg_cluster_clone.git
cd pg_ha_cluster_production
```

---

## Step 2: Generate Passwords (10 seconds)

```bash
# Generate secure random passwords
./scripts/generate-passwords.sh
```

This creates `.env` file with:
- ✅ 24-character random passwords
- ✅ Secure for production use
- ✅ Automatically used by docker-compose

**⚠️ Important:** `.env` is in `.gitignore` - never commit it to Git!

---

## Step 3: Start Cluster (2-3 minutes)

```bash
# Start all services
docker-compose up -d

# Wait for cluster to initialize (30-60 seconds)
sleep 60
```

**Deployment Progress:**
```
Creating pg-1    ... done
Creating witness ... done
Creating pg-2    ... done
Creating pg-3    ... done
Creating pg-4    ... done
Creating pgpool-1 ... done
Creating pgpool-2 ... done
```

---

## Step 3: Verify Cluster (30 seconds)

```bash
# Check all services are running
docker-compose ps

# Check pgpool status
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"
```

**Expected Output:**
```
 node_id | hostname | port | status | pg_status | role    
---------+----------+------+--------+-----------+---------
 0       | pg-1     | 5432 | up     | up        | primary 
 1       | pg-2     | 5432 | up     | up        | standby 
 2       | pg-3     | 5432 | up     | up        | standby 
 3       | pg-4     | 5432 | up     | up        | standby 
```

---

## Step 4: View Credentials (10 seconds)

```bash
# Display all connection info & passwords
./scripts/show-credentials.sh
```

This shows:
- ✅ All user passwords
- ✅ Connection strings for Node.js, Python, psql
- ✅ Monitoring dashboard URLs
- ✅ Quick commands

---

## Step 5: Verify Cluster (30 seconds)

```bash
# Check all services are running
docker-compose ps

# Check pgpool status
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"
```

**Expected Output:**
```
 node_id | hostname | port | status | pg_status | role    
---------+----------+------+--------+-----------+---------
 0       | pg-1     | 5432 | up     | up        | primary 
 1       | pg-2     | 5432 | up     | up        | standby 
 2       | pg-3     | 5432 | up     | up        | standby 
 3       | pg-4     | 5432 | up     | up        | standby 
```

---

## Step 6: Connect! (10 seconds)

### Using psql

```bash
# Get password from show-credentials.sh, then connect via pgpool-1
PGPASSWORD='YOUR_PASSWORD' psql -h localhost -p 15432 -U app_readwrite -d postgres
```

### Or use the full connection string from show-credentials.sh

### Test Query

```sql
-- Check connection
SELECT current_user, inet_server_addr(), version();

-- Create test table
CREATE TABLE test (id serial PRIMARY KEY, name text);
INSERT INTO test (name) VALUES ('Hello from pgpool!');
SELECT * FROM test;

-- Cleanup
DROP TABLE test;
```

---

## ✅ Verification

### 1. Check Cluster Status

```bash
# SSH into pg-1
docker exec -it pg-1 bash

# Check repmgr cluster
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

### 2. Check Pgpool Status

```bash
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"
```

**Expected Output:**
```
 node_id | hostname | port | status | pg_status | role    | select_cnt | load_balance_node
---------+----------+------+--------+-----------+---------+------------+-------------------
 0       | pg-1     | 5432 | up     | up        | primary | 0          | false
 1       | pg-2     | 5432 | up     | up        | standby | 45         | true
 2       | pg-3     | 5432 | up     | up        | standby | 67         | true
 3       | pg-4     | 5432 | up     | up        | standby | 89         | true
```

### 3. Test Read/Write Splitting

```bash
cd test-app
npm install

# Simple cluster test (recommended)
node test-simple.js

# Test INSERT routing
node test-insert-routing.js
```

**Expected Results:**
- ✅ Connection to Pgpool successful
- ✅ INSERT → PRIMARY
- ✅ SELECT → STANDBYs (load-balanced)
- ✅ Transactions work correctly

---

## 🎯 What's Next?

### For Development
```bash
# View logs
docker-compose logs -f pgpool-1
docker-compose logs -f pg-1

# Monitor cluster
docker exec -it pg-1 bash
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Access monitoring
open http://localhost:3001  # Grafana (admin/admin)
```

### For Production

1. **Review Security:**
   ```bash
   # Read security guide
   cat SECURITY.md
   
   # Change default passwords
   docker exec pg-1 psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'new_secure_pass';"
   ```

2. **Set Up Monitoring:**
   - Grafana dashboards: http://localhost:3001
   - Pre-configured dashboards for PostgreSQL, pgpool, infrastructure

3. **Plan Scaling:**
   ```bash
   # Add more PostgreSQL nodes (future)
   # Add more pgpool instances
   
   # Read scaling guide
   cat SCALING_GUIDE.md
   ```

4. **Document Procedures:**
   - Password rotation
   - Backup/restore testing
   - Incident response

---

## 🆘 Troubleshooting

### Issue: Can't connect to database

**Check 1:** Verify pgpool is running
```bash
docker ps | grep pgpool
```

**Check 2:** Test connection
```bash
psql -h localhost -p 15432 -U postgres -c "SELECT 1;"
```

**Check 3:** View logs
```bash
docker logs pgpool-1
```

### Issue: Cluster not forming

**Check 1:** View pg-1 logs
```bash
docker logs pg-1
```

**Check 2:** Check repmgr status
```bash
docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Check 3:** Verify network
```bash
docker network inspect pg_ha_cluster_production_pg_cluster_network
```

### Issue: Pgpool cannot detect PRIMARY

**Cause:** sr_check_user authentication failed

**Solution:**
```bash
# Check logs
docker logs pgpool-1 | grep sr_check

# Verify repmgr user
docker exec pg-1 psql -U repmgr -c "SELECT 1"

# Reload pgpool
docker restart pgpool-1
```

---

## 📚 Documentation

| File | Description |
|------|-------------|
| [README.md](README.md) | Complete architecture and configuration guide |
| [PGPOOL_DEPLOYMENT.md](PGPOOL_DEPLOYMENT.md) | Pgpool-II detailed documentation |
| [SECURITY.md](SECURITY.md) | Security guide and best practices |
| [SCALING_GUIDE.md](SCALING_GUIDE.md) | How to add/remove nodes |

---

## 💡 Quick Reference

### Docker Commands
```bash
# View all services
docker-compose ps

# Start/stop cluster
docker-compose up -d
docker-compose down

# View logs
docker-compose logs -f <service-name>

# Restart service
docker restart <service-name>

# Execute command in container
docker exec -it <service-name> bash
```

### PostgreSQL Commands
```bash
# Inside container (after docker exec)
gosu postgres psql -U postgres

# Check cluster status
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Check replication
gosu postgres psql -c "SELECT * FROM pg_stat_replication;"
```

### Pgpool Commands
```bash
# Show pool nodes
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"

# Show pool processes
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_PROCESSES;"

# Reload config
docker exec pgpool-1 pcp_reload_config -h localhost -p 9898 -U postgres -w
```

---

## 🚀 You're All Set!

Your PostgreSQL HA cluster is now running with:
- ✅ 4 PostgreSQL nodes + witness
- ✅ 2 Pgpool-II instances for HA
- ✅ Automatic failover (repmgr)
- ✅ Query routing (write→primary, read→standbys)
- ✅ SCRAM-SHA-256 authentication
- ✅ Monitoring stack (Grafana, Prometheus, Loki)

**Next Steps:**
1. Build your application
2. Review [PGPOOL_DEPLOYMENT.md](PGPOOL_DEPLOYMENT.md) for advanced config
3. Set up monitoring alerts
4. Test failover procedures

**Need help?** Check the full [README.md](README.md) or consult [PGPOOL_DEPLOYMENT.md](PGPOOL_DEPLOYMENT.md).

---

**Last Updated:** October 28, 2025  
**PostgreSQL:** 17.6  
**Pgpool-II:** 4.3.5 (tamahomeboshi)

