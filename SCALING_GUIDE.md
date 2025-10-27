# PostgreSQL HA Cluster - Scaling Guide

## Overview

This guide explains how to **scale your PostgreSQL HA cluster** horizontally by adding or removing PostgreSQL nodes on Railway platform.

**Key Features:**
- ✅ Zero-downtime node addition via automated script
- ✅ Automatic ProxySQL discovery (no restart required)
- ✅ Repmgr automatic cluster registration
- ✅ Preserves high availability during scaling

---

## Architecture Recap

```
┌─────────────────────────────────────────────────────────────┐
│                    ProxySQL HA Layer                        │
│  ┌──────────────┐              ┌──────────────┐            │
│  │  ProxySQL-1  │              │  ProxySQL-2  │            │
│  │ (30k conns)  │◄────────────►│ (30k conns)  │            │
│  └──────┬───────┘              └──────┬───────┘            │
└─────────┼──────────────────────────────┼──────────────────┘
          │                              │
          └──────────────┬───────────────┘
                         │
          ┌──────────────┴───────────────┐
          │   PostgreSQL Cluster         │
          │   ┌────┐ ┌────┐ ┌────┐      │
          │   │pg-1│ │pg-2│ │pg-3│ ...  │ ← Can scale horizontally
          │   └────┘ └────┘ └────┘      │
          │   + witness node             │
          └──────────────────────────────┘
```

**When to scale:**
- CPU/Memory utilization > 70% on existing nodes
- Need more read replicas for query distribution
- Geographical distribution requirements
- Disaster recovery preparation

---

## Adding a New Node

### Automated Method (Recommended)

Use the provided script to add nodes automatically:

```bash
# Add pg-5
./railway-add-node.sh 5

# Add pg-6
./railway-add-node.sh 6

# Add pg-N
./railway-add-node.sh N
```

**What the script does:**
1. ✅ Creates `pg-N/` folder by copying from `pg-4/`
2. ✅ Configures `.env` with correct NODE_NAME and NODE_ID
3. ✅ Creates Railway service `pg-N`
4. ✅ Sets environment variables from `.env`
5. ✅ Adds volume for PostgreSQL data
6. ✅ Deploys service to Railway
7. ✅ **Updates ProxySQL without restart** (LOAD TO RUNTIME, SAVE TO DISK)

**Timeline:**
- Node creation: ~10 seconds
- Deployment: ~30-60 seconds
- ProxySQL update: Immediate (no restart)
- Total: **~1-2 minutes**

---

### Manual Method

If you prefer manual control:

#### Step 1: Create Node Directory

```bash
# Copy pg-4 as template
cp -r pg-4 pg-5
cd pg-5
```

#### Step 2: Update Configuration

Edit `pg-5/.env`:

```bash
# Node identification (REQUIRED)
NODE_NAME=pg-5
NODE_ID=5

# Peer nodes for discovery (at least 2 recommended)
PEERS=pg-1.railway.internal,pg-2.railway.internal

# Passwords (Railway references)
POSTGRES_PASSWORD=${{POSTGRES_PASSWORD}}
REPMGR_PASSWORD=${{REPMGR_PASSWORD}}

# Primary hint (bootstrap node)
PRIMARY_HINT=${{PRIMARY_HINT}}

# PostgreSQL settings
POSTGRES_USER=postgres
REPMGR_USER=repmgr
REPMGR_DB=repmgr
PG_PORT=5432
```

#### Step 3: Create Railway Service

```bash
# Add service to Railway project
railway add --service pg-5

# Link to service
railway service pg-5

# Set environment variables
cat .env | while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  railway variables --set "$key=$value" --skip-deploys
done
```

#### Step 4: Add Volume

```bash
# Add persistent volume for PostgreSQL data
railway volume add
# Enter mount path: /var/lib/postgresql
```

#### Step 5: Deploy

```bash
railway up --detach
```

#### Step 6: Update ProxySQL (No Restart!)

Wait for new node to be ready, then add to ProxySQL:

```bash
# Wait for pg-5 to initialize
sleep 30

# Add to ProxySQL instance 1
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

# Add to ProxySQL instance 2
railway service proxysql-2
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""
```

**ProxySQL Commands Explained:**
- `INSERT INTO pgsql_servers`: Add new node to server list
- `LOAD PGSQL SERVERS TO RUNTIME`: Apply changes immediately (no restart needed!)
- `SAVE PGSQL SERVERS TO DISK`: Persist changes across ProxySQL restarts

---

## Verification

### 1. Check Node Deployment

```bash
# View deployment logs
railway logs --service pg-5

# Should see:
# [INFO] Node configuration: NAME=pg-5, ID=5
# [INFO] Cloning standby from pg-1.railway.internal:5432
# [INFO] Standby registered.
```

### 2. Verify Cluster Status

```bash
# SSH into primary node
railway ssh --service pg-1

# Check repmgr cluster
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Expected output:**
```
 ID | Name   | Role    | Status    | Upstream | Location | Priority
----+--------+---------+-----------+----------+----------+----------
 1  | pg-1   | primary | * running |          | default  | 199
 2  | pg-2   | standby |   running | pg-1     | default  | 198
 3  | pg-3   | standby |   running | pg-1     | default  | 197
 4  | pg-4   | standby |   running | pg-1     | default  | 196
 5  | pg-5   | standby |   running | pg-1     | default  | 195  ← New node
```

### 3. Verify ProxySQL Discovery

```bash
# Check ProxySQL servers list
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT hostgroup_id, hostname, port, status FROM pgsql_servers ORDER BY hostgroup_id, hostname;'"
```

**Expected output:**
```
 hostgroup_id |          hostname          | port | status
--------------+----------------------------+------+--------
            1 | pg-1.railway.internal      | 5432 | ONLINE
            2 | pg-2.railway.internal      | 5432 | ONLINE
            2 | pg-3.railway.internal      | 5432 | ONLINE
            2 | pg-4.railway.internal      | 5432 | ONLINE
            2 | pg-5.railway.internal      | 5432 | ONLINE  ← New node
```

- **hostgroup_id=1**: Writer group (primary only)
- **hostgroup_id=2**: Reader group (standby nodes)
- **status=ONLINE**: Node is healthy and accepting connections

---

## Removing a Node

**Important:** Node removal must be done via **Railway Dashboard**, not CLI.

### Step 1: Unregister from Repmgr

```bash
# SSH into the node to remove (e.g., pg-5)
railway ssh --service pg-5

# Unregister from cluster
gosu postgres repmgr -f /etc/repmgr/repmgr.conf standby unregister

# Exit SSH
exit
```

### Step 2: Remove from ProxySQL

```bash
# Remove from ProxySQL instance 1
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"DELETE FROM pgsql_servers WHERE hostname='pg-5.railway.internal'; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

# Remove from ProxySQL instance 2
railway service proxysql-2
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"DELETE FROM pgsql_servers WHERE hostname='pg-5.railway.internal'; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""
```

### Step 3: Delete Service via Railway Dashboard

1. Open Railway Dashboard: `railway open`
2. Navigate to project
3. Find service `pg-5`
4. Click **Settings** → **Danger Zone** → **Delete Service**
5. Confirm deletion

### Step 4: Clean Up Local Files (Optional)

```bash
# Remove local folder
rm -rf pg-5/
```

**Why Railway Dashboard for deletion?**
- Railway CLI doesn't support service deletion
- Dashboard deletion ensures:
  - Proper volume cleanup
  - Environment variable cleanup
  - Deployment history preservation
  - Billing adjustments

---

## Scaling Scenarios

### Scenario 1: High Read Load

**Problem:** Read queries overwhelming current standbys

**Solution:** Add 2-3 read replicas

```bash
./railway-add-node.sh 5
./railway-add-node.sh 6
./railway-add-node.sh 7
```

**Result:**
- ProxySQL distributes reads across 6 standbys (pg-2 through pg-7)
- Primary (pg-1) handles writes only
- Read throughput increases 2-3x

### Scenario 2: Geographical Distribution

**Problem:** Need nodes in multiple regions

**Solution:** Deploy nodes to different Railway regions

1. Add node in current region: `./railway-add-node.sh 5`
2. In Railway Dashboard:
   - Change `pg-5` region to target location
   - Redeploy service
3. Update `PEERS` in `pg-5/.env` to include cross-region nodes

### Scenario 3: Disaster Recovery

**Problem:** Need cold standby for disaster recovery

**Solution:** Add DR node with paused deployment

```bash
# Add pg-6 as DR node
./railway-add-node.sh 6

# In Railway Dashboard, pause pg-6 service
# Resume only during DR scenarios
```

---

## Best Practices

### Node Naming

- ✅ **Use sequential naming**: pg-5, pg-6, pg-7 (not pg-backup, pg-test)
- ✅ **Match NODE_ID to number**: pg-5 → NODE_ID=5
- ❌ **Avoid gaps**: Don't skip numbers (pg-4 → pg-6)

### PEERS Configuration

- ✅ **Include at least 2 peers**: `PEERS=pg-1.railway.internal,pg-2.railway.internal`
- ✅ **Mix primary and standbys**: Ensure new nodes can discover cluster
- ❌ **Don't include self**: pg-5 should not include pg-5 in PEERS

### ProxySQL Updates

- ✅ **Use LOAD TO RUNTIME**: Applies changes immediately (no restart!)
- ✅ **Use SAVE TO DISK**: Persists changes across restarts
- ✅ **Add to both instances**: proxysql AND proxysql-2
- ❌ **Don't restart ProxySQL**: LOAD TO RUNTIME is sufficient

### Volume Management

- ✅ **Always add volume before first deployment**
- ✅ **Use `/var/lib/postgresql` mount path**
- ❌ **Never delete volume with data**: Causes data loss

---

## Troubleshooting

### Issue: Node stuck in "cloning" state

```bash
# Check logs
railway logs --service pg-5 | tail -50

# Common causes:
# 1. Primary not reachable
# 2. Incorrect PEERS configuration
# 3. Password mismatch

# Fix: Verify PEERS and passwords
railway service pg-5
railway variables | grep -E "POSTGRES_PASSWORD|REPMGR_PASSWORD|PEERS"
```

### Issue: ProxySQL not detecting new node

```bash
# Manually add to ProxySQL
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

# Verify
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT * FROM pgsql_servers;'"
```

### Issue: Repmgr registration failed

```bash
# SSH into new node
railway ssh --service pg-5

# Manually register
gosu postgres repmgr -h pg-1.railway.internal -U repmgr -d repmgr -f /etc/repmgr/repmgr.conf standby register --force

# Check cluster
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

---

## Performance Considerations

### Node Count vs Performance

| Nodes | Read Capacity | Write Capacity | Failover Time | Recommended For |
|-------|---------------|----------------|---------------|-----------------|
| 4     | 3x            | 1x             | 10-30s        | Small apps      |
| 6     | 5x            | 1x             | 10-30s        | Medium apps     |
| 8     | 7x            | 1x             | 10-30s        | Large apps      |
| 10+   | 9x+           | 1x             | 10-30s        | Enterprise      |

**Key Points:**
- Write capacity = 1x (always limited by primary)
- Read capacity = (N-1)x where N = total nodes
- Failover time independent of node count
- More nodes = more replication overhead on primary

### ProxySQL Connection Limits

- Each ProxySQL instance: 30,000 connections
- Total capacity: 60,000 connections (2 instances)
- Per-backend limit: 100 connections (configurable)

**Formula:**
```
Max concurrent queries = ProxySQL instances × max_connections
                       = 2 × 30,000 = 60,000
```

---

## Monitoring

### Key Metrics to Watch

```bash
# Replication lag
railway ssh --service pg-5
gosu postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"

# Connection count
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT * FROM stats_pgsql_connection_pool;'"

# Node health
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

---

## Summary

**Adding a node:**
1. Run `./railway-add-node.sh N`
2. Wait 1-2 minutes for deployment
3. Verify with `repmgr cluster show` and ProxySQL query
4. ProxySQL automatically includes new node (no restart!)

**Removing a node:**
1. Unregister from repmgr: `gosu postgres repmgr standby unregister`
2. Remove from ProxySQL: `DELETE FROM pgsql_servers; LOAD TO RUNTIME; SAVE TO DISK`
3. Delete service via Railway Dashboard
4. Clean up local files: `rm -rf pg-N/`

**Best practices:**
- ✅ Use automated script for consistency
- ✅ Always update ProxySQL without restart (LOAD TO RUNTIME)
- ✅ Monitor replication lag after scaling
- ✅ Test failover after major topology changes

For detailed deployment guide, see `README.md`.  
For security audit, see `SECURITY_AUDIT.md`.
