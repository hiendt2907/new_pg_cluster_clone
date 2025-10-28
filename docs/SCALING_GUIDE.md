# PostgreSQL HA Cluster - Scaling Guide# PostgreSQL HA Cluster - Scaling Guide



Hướng dẫn scale PostgreSQL cluster và pgpool-II instances.## Overview



---This guide explains how to **scale your PostgreSQL HA cluster** horizontally by adding or removing PostgreSQL nodes on Railway platform.



## 📊 Current Architecture**Key Features:**

- ✅ Zero-downtime node addition via automated script

```- ✅ Automatic ProxySQL discovery (no restart required)

Applications- ✅ Repmgr automatic cluster registration

     │- ✅ Preserves high availability during scaling

     ├─── pgpool-1 (port 15432)

     │         │---

     │         ├─── pg-1 (PRIMARY)

     │         ├─── pg-2 (STANDBY)## Architecture Recap

     │         ├─── pg-3 (STANDBY)

     │         └─── pg-4 (STANDBY)```

     │┌─────────────────────────────────────────────────────────────┐

     └─── pgpool-2 (port 15433)│                    ProxySQL HA Layer                        │

               ││  ┌──────────────┐              ┌──────────────┐            │

               └─── (same backends)│  │  ProxySQL-1  │              │  ProxySQL-2  │            │

```│  │ (30k conns)  │◄────────────►│ (30k conns)  │            │

│  └──────┬───────┘              └──────┬───────┘            │

**When to Scale**:└─────────┼──────────────────────────────┼──────────────────┘

- CPU/Memory > 70% on existing nodes          │                              │

- Need more read replicas for query distribution          └──────────────┬───────────────┘

- Higher connection capacity required                         │

- Better fault tolerance needed          ┌──────────────┴───────────────┐

          │   PostgreSQL Cluster         │

---          │   ┌────┐ ┌────┐ ┌────┐      │

          │   │pg-1│ │pg-2│ │pg-3│ ...  │ ← Can scale horizontally

## 🔄 Scaling PostgreSQL Nodes          │   └────┘ └────┘ └────┘      │

          │   + witness node             │

### Add New STANDBY Node (pg-5)          └──────────────────────────────┘

```

#### Step 1: Create Node Directory

**When to scale:**

```bash- CPU/Memory utilization > 70% on existing nodes

# Copy pg-4 as template- Need more read replicas for query distribution

cp -r pg-4 pg-5- Geographical distribution requirements

cd pg-5- Disaster recovery preparation

```

---

#### Step 2: Update Configuration

## Adding a New Node

Edit `pg-5/.env` (if using env files):

```bash### Automated Method (Recommended)

NODE_NAME=pg-5

NODE_ID=5Use the provided script to add nodes automatically:

PEERS=pg-1,pg-2

``````bash

# Add pg-5

#### Step 3: Add to docker-compose.yml./railway-add-node.sh 5



```yaml# Add pg-6

pg-5:./railway-add-node.sh 6

  build: ./pg-5

  container_name: pg-5# Add pg-N

  hostname: pg-5./railway-add-node.sh N

  environment:```

    - NODE_NAME=pg-5

    - NODE_ID=5**What the script does:**

    - POSTGRES_PASSWORD=postgrespass1. ✅ Creates `pg-N/` folder by copying from `pg-4/`

    - REPMGR_PASSWORD=repmgrpass2. ✅ Configures `.env` with correct NODE_NAME and NODE_ID

    - APP_READWRITE_PASSWORD=appreadwritepass3. ✅ Creates Railway service `pg-N`

    - APP_READONLY_PASSWORD=appreadonlypass4. ✅ Sets environment variables from `.env`

    - PRIMARY_HOST=pg-15. ✅ Adds volume for PostgreSQL data

  volumes:6. ✅ Deploys service to Railway

    - pg5_data:/var/lib/postgresql/data7. ✅ **Updates ProxySQL without restart** (LOAD TO RUNTIME, SAVE TO DISK)

  networks:

    pg_cluster_network:**Timeline:**

      ipv4_address: 172.20.0.15- Node creation: ~10 seconds

  depends_on:- Deployment: ~30-60 seconds

    - pg-1- ProxySQL update: Immediate (no restart)

```- Total: **~1-2 minutes**



Add volume:---

```yaml

volumes:### Manual Method

  pg5_data:

```If you prefer manual control:



#### Step 4: Update Pgpool Configuration#### Step 1: Create Node Directory



Edit `pgpool/pgpool.conf`:```bash

# Copy pg-4 as template

```confcp -r pg-4 pg-5

# Backend 4 - NEW STANDBYcd pg-5

backend_hostname4 = 'pg-5'```

backend_port4 = 5432

backend_weight4 = 1#### Step 2: Update Configuration

backend_data_directory4 = '/var/lib/postgresql/data'

backend_flag4 = 'ALLOW_TO_FAILOVER'Edit `pg-5/.env`:

```

```bash

#### Step 5: Deploy# Node identification (REQUIRED)

NODE_NAME=pg-5

```bashNODE_ID=5

# Start new node

docker-compose up -d pg-5# Peer nodes for discovery (at least 2 recommended)

PEERS=pg-1.railway.internal,pg-2.railway.internal

# Wait for replication to sync (30-60 seconds)

sleep 60# Passwords (Railway references)

POSTGRES_PASSWORD=${{POSTGRES_PASSWORD}}

# Reload pgpool configREPMGR_PASSWORD=${{REPMGR_PASSWORD}}

docker exec pgpool-1 pcp_reload_config -h localhost -p 9898 -U postgres -w

docker exec pgpool-2 pcp_reload_config -h localhost -p 9899 -U postgres -w# Primary hint (bootstrap node)

```PRIMARY_HINT=${{PRIMARY_HINT}}



#### Step 6: Verify# PostgreSQL settings

POSTGRES_USER=postgres

```bashREPMGR_USER=repmgr

# Check repmgr clusterREPMGR_DB=repmgr

docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster showPG_PORT=5432

```

# Should show:

# 1 | pg-1 | primary | running#### Step 3: Create Railway Service

# 2 | pg-2 | standby | running | pg-1

# 3 | pg-3 | standby | running | pg-1```bash

# 4 | pg-4 | standby | running | pg-1# Add service to Railway project

# 5 | pg-5 | standby | running | pg-1  ← NEWrailway add --service pg-5



# Check pgpool# Link to service

docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"railway service pg-5



# Should show all 5 backends (0-4)# Set environment variables

```cat .env | while IFS='=' read -r key value; do

  [[ -z "$key" || "$key" =~ ^# ]] && continue

**Timeline**: ~2-3 minutes total  railway variables --set "$key=$value" --skip-deploys

done

---```



## 📈 Scaling Pgpool Instances#### Step 4: Add Volume



### Add Third Pgpool Instance (pgpool-3)```bash

# Add persistent volume for PostgreSQL data

#### Step 1: Create Directoryrailway volume add

# Enter mount path: /var/lib/postgresql

```bash```

cp -r pgpool pgpool-3

cd pgpool-3#### Step 5: Deploy

```

```bash

#### Step 2: Update Entrypointrailway up --detach

```

Edit `pgpool-3/entrypoint.sh`:

#### Step 6: Update ProxySQL (No Restart!)

```bash

# Change PGPOOL_NODE_IDWait for new node to be ready, then add to ProxySQL:

echo "2" > /var/log/pgpool/pgpool_node_id

``````bash

# Wait for pg-5 to initialize

#### Step 3: Add to docker-compose.ymlsleep 30



```yaml# Add to ProxySQL instance 1

pgpool-3:railway service proxysql

  build: ./pgpool-3railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

  container_name: pgpool-3

  hostname: pgpool-3# Add to ProxySQL instance 2

  environment:railway service proxysql-2

    - PGPOOL_NODE_ID=2railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

    - POSTGRES_PASSWORD=postgrespass```

    - REPMGR_PASSWORD=repmgrpass

    - APP_READWRITE_PASSWORD=appreadwritepass**ProxySQL Commands Explained:**

    - APP_READONLY_PASSWORD=appreadonlypass- `INSERT INTO pgsql_servers`: Add new node to server list

  ports:- `LOAD PGSQL SERVERS TO RUNTIME`: Apply changes immediately (no restart needed!)

    - "15434:5432"- `SAVE PGSQL SERVERS TO DISK`: Persist changes across ProxySQL restarts

    - "9897:9898"

  networks:---

    pg_cluster_network:

      ipv4_address: 172.20.0.22## Verification

  depends_on:

    - pg-1### 1. Check Node Deployment

    - pg-2

    - pg-3```bash

    - pg-4# View deployment logs

```railway logs --service pg-5



#### Step 4: Deploy# Should see:

# [INFO] Node configuration: NAME=pg-5, ID=5

```bash# [INFO] Cloning standby from pg-1.railway.internal:5432

docker-compose up -d pgpool-3# [INFO] Standby registered.

``````



#### Step 5: Verify### 2. Verify Cluster Status



```bash```bash

# Test connection# SSH into primary node

psql -h localhost -p 15434 -U postgres -c "SHOW POOL_NODES;"railway ssh --service pg-1

```

# Check repmgr cluster

**Use Case**: gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

- HAProxy/Nginx load balancing across 3 pgpool instances```

- Higher connection capacity

- Better fault tolerance**Expected output:**

```

--- ID | Name   | Role    | Status    | Upstream | Location | Priority

----+--------+---------+-----------+----------+----------+----------

## 🔽 Scaling Down 1  | pg-1   | primary | * running |          | default  | 199

 2  | pg-2   | standby |   running | pg-1     | default  | 198

### Remove STANDBY Node (pg-5) 3  | pg-3   | standby |   running | pg-1     | default  | 197

 4  | pg-4   | standby |   running | pg-1     | default  | 196

⚠️ **WARNING**: Never remove PRIMARY node! Promote standby first if needed. 5  | pg-5   | standby |   running | pg-1     | default  | 195  ← New node

```

#### Step 1: Remove from Pgpool

### 3. Verify ProxySQL Discovery

Edit `pgpool/pgpool.conf`:

```bash

```conf# Check ProxySQL servers list

# Comment out backend 4railway service proxysql

# backend_hostname4 = 'pg-5'railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT hostgroup_id, hostname, port, status FROM pgsql_servers ORDER BY hostgroup_id, hostname;'"

# ...```

```

**Expected output:**

Reload:```

```bash hostgroup_id |          hostname          | port | status

docker exec pgpool-1 pcp_reload_config -h localhost -p 9898 -U postgres -w--------------+----------------------------+------+--------

docker exec pgpool-2 pcp_reload_config -h localhost -p 9899 -U postgres -w            1 | pg-1.railway.internal      | 5432 | ONLINE

```            2 | pg-2.railway.internal      | 5432 | ONLINE

            2 | pg-3.railway.internal      | 5432 | ONLINE

#### Step 2: Unregister from Repmgr            2 | pg-4.railway.internal      | 5432 | ONLINE

            2 | pg-5.railway.internal      | 5432 | ONLINE  ← New node

```bash```

# From pg-5

docker exec pg-5 gosu postgres repmgr standby unregister -f /etc/repmgr/repmgr.conf --node-id=5- **hostgroup_id=1**: Writer group (primary only)

```- **hostgroup_id=2**: Reader group (standby nodes)

- **status=ONLINE**: Node is healthy and accepting connections

#### Step 3: Stop and Remove

---

```bash

# Stop container## Removing a Node

docker-compose stop pg-5

**Important:** Node removal must be done via **Railway Dashboard**, not CLI.

# Remove container

docker-compose rm -f pg-5### Step 1: Unregister from Repmgr



# Optional: Remove volume (DELETES DATA!)```bash

docker volume rm pg_ha_cluster_production_pg5_data# SSH into the node to remove (e.g., pg-5)

```railway ssh --service pg-5



#### Step 4: Clean docker-compose.yml# Unregister from cluster

gosu postgres repmgr -f /etc/repmgr/repmgr.conf standby unregister

Remove `pg-5` service and `pg5_data` volume from docker-compose.yml.

# Exit SSH

**Timeline**: ~1-2 minutesexit

```

---

### Step 2: Remove from ProxySQL

## 🎯 Vertical Scaling

```bash

### Increase Resources for Existing Nodes# Remove from ProxySQL instance 1

railway service proxysql

Edit `docker-compose.yml`:railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"DELETE FROM pgsql_servers WHERE hostname='pg-5.railway.internal'; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""



```yaml# Remove from ProxySQL instance 2

pg-1:railway service proxysql-2

  # ... existing config ...railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"DELETE FROM pgsql_servers WHERE hostname='pg-5.railway.internal'; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

  deploy:```

    resources:

      limits:### Step 3: Delete Service via Railway Dashboard

        cpus: '4'      # Increase CPU

        memory: 8G     # Increase RAM1. Open Railway Dashboard: `railway open`

      reservations:2. Navigate to project

        cpus: '2'3. Find service `pg-5`

        memory: 4G4. Click **Settings** → **Danger Zone** → **Delete Service**

```5. Confirm deletion



Restart:### Step 4: Clean Up Local Files (Optional)

```bash

docker-compose up -d pg-1```bash

```# Remove local folder

rm -rf pg-5/

### Tune PostgreSQL Config```



Edit `pg-1/Dockerfile` or mount custom postgresql.conf:**Why Railway Dashboard for deletion?**

- Railway CLI doesn't support service deletion

```conf- Dashboard deletion ensures:

# postgresql.conf  - Proper volume cleanup

shared_buffers = 2GB              # 25% of RAM  - Environment variable cleanup

effective_cache_size = 6GB        # 75% of RAM  - Deployment history preservation

maintenance_work_mem = 512MB  - Billing adjustments

max_connections = 300

work_mem = 16MB---

```

## Scaling Scenarios

Restart:

```bash### Scenario 1: High Read Load

docker-compose restart pg-1

```**Problem:** Read queries overwhelming current standbys



---**Solution:** Add 2-3 read replicas



## 🔁 Load Balancing Strategies```bash

./railway-add-node.sh 5

### Application-Level (Recommended)./railway-add-node.sh 6

./railway-add-node.sh 7

```javascript```

// Read/write pool (via pgpool-1)

const writePool = new Pool({**Result:**

  host: 'localhost',- ProxySQL distributes reads across 6 standbys (pg-2 through pg-7)

  port: 15432,- Primary (pg-1) handles writes only

  user: 'app_readwrite',- Read throughput increases 2-3x

  password: 'appreadwritepass',

});### Scenario 2: Geographical Distribution



// Read-only pool (via pgpool-2)**Problem:** Need nodes in multiple regions

const readPool = new Pool({

  host: 'localhost',**Solution:** Deploy nodes to different Railway regions

  port: 15433,

  user: 'app_readonly',1. Add node in current region: `./railway-add-node.sh 5`

  password: 'appreadonlypass',2. In Railway Dashboard:

});   - Change `pg-5` region to target location

   - Redeploy service

// Writes3. Update `PEERS` in `pg-5/.env` to include cross-region nodes

await writePool.query('INSERT INTO ...');

### Scenario 3: Disaster Recovery

// Reads

await readPool.query('SELECT * FROM ...');**Problem:** Need cold standby for disaster recovery

```

**Solution:** Add DR node with paused deployment

### HAProxy (Advanced)

```bash

```conf# Add pg-6 as DR node

# haproxy.cfg./railway-add-node.sh 6

frontend pgpool_frontend

  bind *:5432# In Railway Dashboard, pause pg-6 service

  default_backend pgpool_backend# Resume only during DR scenarios

```

backend pgpool_backend

  balance roundrobin---

  server pgpool1 pgpool-1:5432 check

  server pgpool2 pgpool-2:5432 check## Best Practices

  server pgpool3 pgpool-3:5432 check

```### Node Naming



### DNS Round-Robin (Simple)- ✅ **Use sequential naming**: pg-5, pg-6, pg-7 (not pg-backup, pg-test)

- ✅ **Match NODE_ID to number**: pg-5 → NODE_ID=5

```bash- ❌ **Avoid gaps**: Don't skip numbers (pg-4 → pg-6)

# /etc/hosts or DNS

pgpool.local  172.20.0.20  # pgpool-1### PEERS Configuration

pgpool.local  172.20.0.21  # pgpool-2

pgpool.local  172.20.0.22  # pgpool-3- ✅ **Include at least 2 peers**: `PEERS=pg-1.railway.internal,pg-2.railway.internal`

```- ✅ **Mix primary and standbys**: Ensure new nodes can discover cluster

- ❌ **Don't include self**: pg-5 should not include pg-5 in PEERS

---

### ProxySQL Updates

## 📊 Monitoring Scaling Impact

- ✅ **Use LOAD TO RUNTIME**: Applies changes immediately (no restart!)

### Key Metrics to Watch- ✅ **Use SAVE TO DISK**: Persists changes across restarts

- ✅ **Add to both instances**: proxysql AND proxysql-2

**Before Scaling**:- ❌ **Don't restart ProxySQL**: LOAD TO RUNTIME is sufficient

```bash

# Check current load### Volume Management

docker exec pg-1 psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"

- ✅ **Always add volume before first deployment**

# Check replication lag- ✅ **Use `/var/lib/postgresql` mount path**

docker exec pg-1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"- ❌ **Never delete volume with data**: Causes data loss

```

---

**After Scaling**:

```bash## Troubleshooting

# Verify new node in cluster

docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show### Issue: Node stuck in "cloning" state



# Check load distribution```bash

docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"# Check logs

railway logs --service pg-5 | tail -50

# Should see select_cnt increasing on new node

```# Common causes:

# 1. Primary not reachable

### Grafana Dashboards# 2. Incorrect PEERS configuration

# 3. Password mismatch

Monitor these metrics:

- Active connections per node# Fix: Verify PEERS and passwords

- Replication lag per standbyrailway service pg-5

- Query distribution (select_cnt)railway variables | grep -E "POSTGRES_PASSWORD|REPMGR_PASSWORD|PEERS"

- CPU/Memory usage per node```



---### Issue: ProxySQL not detecting new node



## 🚨 Best Practices```bash

# Manually add to ProxySQL

### DO ✅railway service proxysql

railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'pg-5.railway.internal',5432,1000,100); LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\""

- **Test in staging first**: Always test scaling procedures in non-production

- **Monitor replication lag**: Wait for lag < 1MB before adding to pool# Verify

- **Backup before scaling**: Take backup before major changesrailway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT * FROM pgsql_servers;'"

- **Document changes**: Update architecture diagrams```

- **Use automation**: Scripts reduce human error

### Issue: Repmgr registration failed

### DON'T ❌

```bash

- **Don't remove PRIMARY**: Always promote standby first# SSH into new node

- **Don't skip verification**: Always check cluster status after changesrailway ssh --service pg-5

- **Don't scale during peak hours**: Schedule during maintenance windows

- **Don't ignore alerts**: Watch for replication lag spikes# Manually register

- **Don't forget pgpool reload**: Config changes need reloadgosu postgres repmgr -h pg-1.railway.internal -U repmgr -d repmgr -f /etc/repmgr/repmgr.conf standby register --force



---# Check cluster

gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

## 📋 Scaling Checklist```



### Pre-Scaling---



- [ ] Check current cluster health## Performance Considerations

- [ ] Review resource utilization

- [ ] Plan node IDs and IPs### Node Count vs Performance

- [ ] Backup configuration files

- [ ] Schedule maintenance window| Nodes | Read Capacity | Write Capacity | Failover Time | Recommended For |

- [ ] Notify stakeholders|-------|---------------|----------------|---------------|-----------------|

| 4     | 3x            | 1x             | 10-30s        | Small apps      |

### During Scaling| 6     | 5x            | 1x             | 10-30s        | Medium apps     |

| 8     | 7x            | 1x             | 10-30s        | Large apps      |

- [ ] Create new node directory| 10+   | 9x+           | 1x             | 10-30s        | Enterprise      |

- [ ] Update docker-compose.yml

- [ ] Update pgpool.conf**Key Points:**

- [ ] Deploy new node- Write capacity = 1x (always limited by primary)

- [ ] Wait for replication sync- Read capacity = (N-1)x where N = total nodes

- [ ] Reload pgpool config- Failover time independent of node count

- [ ] Verify cluster status- More nodes = more replication overhead on primary



### Post-Scaling### ProxySQL Connection Limits



- [ ] Monitor replication lag- Each ProxySQL instance: 30,000 connections

- [ ] Check query distribution- Total capacity: 60,000 connections (2 instances)

- [ ] Update documentation- Per-backend limit: 100 connections (configurable)

- [ ] Update monitoring dashboards

- [ ] Test failover scenarios**Formula:**

- [ ] Commit changes to Git```

Max concurrent queries = ProxySQL instances × max_connections

---                       = 2 × 30,000 = 60,000

```

## 🔗 Related Documentation

---

- [README.md](README.md) - Architecture overview

- [PGPOOL_DEPLOYMENT.md](PGPOOL_DEPLOYMENT.md) - Pgpool configuration## Monitoring

- [QUICK_START.md](QUICK_START.md) - Quick start guide

### Key Metrics to Watch

---

```bash

## 🆘 Troubleshooting# Replication lag

railway ssh --service pg-5

### New node not joining clustergosu postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"



**Check 1**: Network connectivity# Connection count

```bashrailway service proxysql

docker exec pg-5 ping pg-1railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT * FROM stats_pgsql_connection_pool;'"

```

# Node health

**Check 2**: Repmgr logsgosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

```bash```

docker logs pg-5 | grep repmgr

```---



**Check 3**: Primary connectivity## Summary

```bash

docker exec pg-5 psql -h pg-1 -U repmgr -c "SELECT 1"**Adding a node:**

```1. Run `./railway-add-node.sh N`

2. Wait 1-2 minutes for deployment

### Pgpool not detecting new backend3. Verify with `repmgr cluster show` and ProxySQL query

4. ProxySQL automatically includes new node (no restart!)

**Check 1**: Config file syntax

```bash**Removing a node:**

docker exec pgpool-1 pgpool -n -f /etc/pgpool2/pgpool.conf -C1. Unregister from repmgr: `gosu postgres repmgr standby unregister`

```2. Remove from ProxySQL: `DELETE FROM pgsql_servers; LOAD TO RUNTIME; SAVE TO DISK`

3. Delete service via Railway Dashboard

**Check 2**: Reload successful4. Clean up local files: `rm -rf pg-N/`

```bash

docker logs pgpool-1 | grep reload**Best practices:**

```- ✅ Use automated script for consistency

- ✅ Always update ProxySQL without restart (LOAD TO RUNTIME)

**Check 3**: Manual attach- ✅ Monitor replication lag after scaling

```bash- ✅ Test failover after major topology changes

pcp_attach_node -h localhost -p 9898 -U postgres -w -n 4

```For detailed deployment guide, see `README.md`.  

For security audit, see `SECURITY_AUDIT.md`.

### Replication lag after scaling

**Check**: WAL sender capacity
```bash
docker exec pg-1 psql -U postgres -c "SHOW max_wal_senders;"
```

**Solution**: Increase max_wal_senders
```conf
# postgresql.conf
max_wal_senders = 10  # Default, increase if needed
```

---

**Last Updated**: 2025-10-28  
**Version**: 2.0.0 (Pgpool-II)
