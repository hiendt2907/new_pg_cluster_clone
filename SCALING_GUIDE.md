# Horizontal Scaling Guide - PostgreSQL HA Cluster

Hướng dẫn chi tiết để scale cluster lên hoặc xuống bằng cách thêm/xóa PostgreSQL nodes.

---

## 📊 Overview

**Current Architecture:**
- Core Cluster: `pg-1`, `pg-2`, `pg-3`, `pg-4` (protected, cannot remove)
- Witness: `witness` (quorum voting only)
- ProxySQL HA: `proxysql`, `proxysql-2` (connection pooling + query routing)

**Scalable Nodes:**
- Can add: `pg-5`, `pg-6`, `pg-7`, ... `pg-N`
- Can remove: Only nodes with ID >= 5
- Protection: Core nodes (pg-1 to pg-4) cannot be removed

---

## ⬆️ Scale Up - Adding Nodes

### Method 1: Automated Script (Recommended)

```bash
# Add pg-5
./railway-add-node.sh 5

# Add pg-6
./railway-add-node.sh 6

# Add pg-7
./railway-add-node.sh 7
```

#### What the script does:
1. ✅ Validates node number (must be >= 5)
2. ✅ Copies folder structure from `pg-4` template
3. ✅ Generates `.env` file with:
   - `NODE_NAME=pg-5`
   - `NODE_ID=5`
   - `PEERS=pg-1,pg-2,pg-3`
   - Railway password references: `${{POSTGRES_PASSWORD}}`, `${{REPMGR_PASSWORD}}`
4. ✅ Creates Railway service
5. ✅ Sets environment variables from `.env`
6. ✅ Adds persistent volume at `/var/lib/postgresql`
7. ✅ Deploys new node
8. ✅ Updates both ProxySQL instances (`proxysql` and `proxysql-2`)
9. ✅ Redeploys ProxySQL to discover new node

#### Script Output Example:
```
[INFO] === Adding PostgreSQL Node: pg-5 ===
[INFO] Step 1: Creating node directory from pg-4 template...
[SUCCESS] Directory created: /root/new_pg_cluster_clone/pg-5
[INFO] Step 2: Updating .env configuration...
[SUCCESS] .env file configured for pg-5 (ID: 5)
[INFO] Step 3: Creating Railway service 'pg-5'...
[SUCCESS] Service 'pg-5' created on Railway
[INFO] Step 4: Linking to service 'pg-5'...
[SUCCESS] Linked to service pg-5
[INFO] Step 5: Setting environment variables...
[SUCCESS] Environment variables set
[INFO] Step 6: Adding persistent volume at /var/lib/postgresql...
[SUCCESS] Volume added to pg-5
[INFO] Step 7: Deploying pg-5 to Railway...
[SUCCESS] Deployment started for pg-5
[INFO] Step 8: Updating ProxySQL configuration...
[SUCCESS] Updated proxysql/entrypoint.sh
[INFO] Redeploying proxysql...
[SUCCESS] Updated proxysql-2/entrypoint.sh
[INFO] Redeploying proxysql-2...
[SUCCESS] 
=== Node pg-5 added successfully! ===

Next steps:
1. Wait 30-60 seconds for pg-5 to initialize
2. Check deployment: railway logs --service pg-5
3. Verify cluster status:
   railway ssh --service pg-1
   gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

---

### Method 2: Manual Process

If you prefer manual control or the script fails:

#### Step 1: Copy Template
```bash
cp -r pg-4 pg-5
cd pg-5
```

#### Step 2: Update Configuration
```bash
cat > .env << 'EOF'
NODE_NAME=pg-5
NODE_ID=5
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal

# Passwords from Railway shared variables
POSTGRES_PASSWORD=${{POSTGRES_PASSWORD}}
REPMGR_PASSWORD=${{REPMGR_PASSWORD}}
PRIMARY_HINT=${{PRIMARY_HINT}}

# PostgreSQL settings
POSTGRES_USER=postgres
REPMGR_USER=repmgr
REPMGR_DB=repmgr
PG_PORT=5432
EOF
```

#### Step 3: Create Railway Service
```bash
# Add service
railway add --service pg-5

# Link to service
railway service pg-5

# Set environment variables
railway variables --set "NODE_NAME=pg-5" --skip-deploys
railway variables --set "NODE_ID=5" --skip-deploys
railway variables --set "PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal" --skip-deploys

# Add volume
echo "/var/lib/postgresql" | railway volume add
```

#### Step 4: Deploy Node
```bash
railway up --detach
```

#### Step 5: Update ProxySQL Configuration

Edit `proxysql/entrypoint.sh`:
```bash
# Find line:
: "${PG_NODES:=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal}"

# Change to:
: "${PG_NODES:=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal,pg-5.railway.internal}"
```

Edit `proxysql-2/entrypoint.sh` (same change).

#### Step 6: Redeploy ProxySQL
```bash
cd ../proxysql
railway service proxysql
railway up --detach

cd ../proxysql-2
railway service proxysql-2
railway up --detach
```

---

### Verification After Adding Node

#### 1. Check Node Logs
```bash
railway logs --service pg-5 --tail 50

# Expected output:
# [entrypoint] Node configuration: NAME=pg-5, ID=5
# [entrypoint] Cloning standby from pg-1.railway.internal:5432
# [entrypoint] Standby registered.
# [entrypoint] Starting repmgrd...
```

#### 2. Verify Cluster Status
```bash
railway ssh --service pg-1

# Inside pg-1 container:
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Expected output:
#  ID | Name | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
# ----+------+---------+-----------+----------+----------+----------+----------+-------------------
#  1  | pg-1 | primary | * running |          | default  | 199      | 1        | host=pg-1 ...
#  2  | pg-2 | standby |   running | pg-1     | default  | 198      | 1        | host=pg-2 ...
#  3  | pg-3 | standby |   running | pg-1     | default  | 197      | 1        | host=pg-3 ...
#  4  | pg-4 | standby |   running | pg-1     | default  | 196      | 1        | host=pg-4 ...
#  5  | pg-5 | standby |   running | pg-1     | default  | 195      | 1        | host=pg-5 ...  ← NEW
# 99  | witness | witness | * running | pg-1  | default  | 0        |          | host=witness ...
```

#### 3. Check ProxySQL Discovery
```bash
railway logs --service proxysql | grep pg-5

# Expected output:
# [proxysql] Checking pg-5.railway.internal:5432
# [proxysql]   → pg-5.railway.internal:5432 is STANDBY (hostgroup 2)
```

#### 4. Test Connection via ProxySQL
```bash
# Get ProxySQL domain
railway service proxysql
railway domain

# Connect (replace with your domain)
psql -h proxysql-production-abc123.up.railway.app -p 5432 -U postgres -d postgres

# Check connection distribution
SELECT * FROM pg_stat_replication;
```

---

## ⬇️ Scale Down - Removing Nodes

### Method 1: Automated Script (Recommended)

```bash
# Remove pg-5
./railway-remove-node.sh 5

# Confirmation prompt will appear:
# Type 'yes' to continue
```

#### What the script does:
1. ✅ Validates node number (must be >= 5, cannot remove core nodes)
2. ✅ Prompts for confirmation
3. ✅ Unregisters node from repmgr cluster via pg-1
4. ✅ Deletes Railway service (including volume data - **WARNING: DATA LOSS**)
5. ✅ Removes node from both ProxySQL configurations
6. ✅ Redeploys ProxySQL instances
7. ✅ Deletes local directory

#### Script Output Example:
```
[WARN] === Removing PostgreSQL Node: pg-5 ===
[WARN] This will:
[WARN]   1. Unregister node from repmgr cluster
[WARN]   2. Delete Railway service (volume data will be deleted!)
[WARN]   3. Remove from ProxySQL configuration
[WARN]   4. Delete local directory

Are you sure? Type 'yes' to continue: yes

[INFO] === Removing pg-5 ===
[INFO] Step 1: Unregistering from repmgr cluster...
[SUCCESS]   Node unregistered from repmgr
[INFO] Step 2: Deleting Railway service 'pg-5'...
[SUCCESS]   Railway service deleted
[INFO] Step 3: Removing from ProxySQL configuration...
[SUCCESS]   Removed from proxysql configuration
[SUCCESS]   Removed from proxysql-2 configuration
[INFO] Step 4: Deleting local directory...
[SUCCESS]   Directory deleted: /root/new_pg_cluster_clone/pg-5

=== Node pg-5 removed successfully! ===
```

---

### Method 2: Manual Process

#### Step 1: Unregister from repmgr
```bash
# SSH into primary (pg-1)
railway ssh --service pg-1

# Unregister node
gosu postgres repmgr -f /etc/repmgr/repmgr.conf primary unregister --node-id=5 --force
```

#### Step 2: Delete Railway Service
```bash
# Delete service (WARNING: This deletes volume data!)
railway service pg-5
railway service delete --yes pg-5
```

#### Step 3: Remove from ProxySQL

Edit `proxysql/entrypoint.sh`:
```bash
# Find line:
: "${PG_NODES:=pg-1.railway.internal,...,pg-5.railway.internal}"

# Remove pg-5:
: "${PG_NODES:=pg-1.railway.internal,...,pg-4.railway.internal}"
```

Edit `proxysql-2/entrypoint.sh` (same change).

#### Step 4: Redeploy ProxySQL
```bash
cd proxysql
railway service proxysql
railway up --detach

cd ../proxysql-2
railway service proxysql-2
railway up --detach
```

#### Step 5: Delete Local Directory
```bash
cd ..
rm -rf pg-5
```

---

### Verification After Removing Node

#### 1. Verify Cluster Status
```bash
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# pg-5 should NOT appear in output
```

#### 2. Check ProxySQL
```bash
railway logs --service proxysql | grep -i pg-5

# Should show no recent mentions of pg-5
```

#### 3. Verify Railway Services
```bash
railway status

# pg-5 should NOT be listed
```

---

## 🔧 Common Scaling Scenarios

### Scenario 1: Add 2 Nodes for Read Scaling
```bash
# Trading system needs more read capacity
./railway-add-node.sh 5
sleep 60  # Wait for pg-5 to stabilize
./railway-add-node.sh 6
```

**Result:**
- 6 data nodes total (pg-1 to pg-6)
- Read queries distributed across 5 standbys (pg-2, pg-3, pg-4, pg-5, pg-6)
- 60k connections via ProxySQL HA pair

### Scenario 2: Temporary Node for Testing
```bash
# Add test node
./railway-add-node.sh 99

# Run tests...
railway ssh --service pg-99
# ...test queries...

# Remove when done
./railway-remove-node.sh 99
```

### Scenario 3: Replace Failed Node
```bash
# Old pg-5 has hardware issues, remove it
./railway-remove-node.sh 5

# Add fresh pg-5
./railway-add-node.sh 5
```

---

## ⚠️ Important Considerations

### Node ID Limits
- **Core nodes**: 1-4 (protected, cannot remove)
- **Witness**: 99 (protected, quorum voting)
- **Scalable nodes**: 5-98 (can add/remove freely)

### Railway Resource Limits
- **Pro Plan**: Up to 20 services per project
- **Starter Plan**: Up to 5 services (not enough for this cluster)
- Check your plan: `railway plan`

### Performance Impact
- **Adding nodes**: No downtime, ProxySQL discovers automatically
- **Removing nodes**: Brief connection interruption during ProxySQL redeploy
- **Repmgr registration**: Takes 10-30 seconds per node

### Cost Estimation
Each additional PostgreSQL node adds:
- Compute: ~$10-20/month (Railway Pro pricing)
- Storage: $0.25/GB/month for persistent volume
- Network: Included in Railway pricing

### Data Replication
- New nodes clone from primary (pg-1) by default
- Cloning time depends on database size:
  - 1GB: ~10 seconds
  - 10GB: ~1 minute
  - 100GB: ~10 minutes
  - 1TB: ~2 hours

---

## 🛡️ Safety Features

### Core Node Protection
```bash
# Attempting to remove pg-1
./railway-remove-node.sh 1

# Output:
# [ERROR] Cannot remove core nodes (pg-1 to pg-4)
# [ERROR] These are essential for cluster quorum and availability
```

### Confirmation Prompts
All removal operations require explicit confirmation:
```bash
Are you sure? Type 'yes' to continue:
```

### Automatic Cleanup
Scripts handle all cleanup automatically:
- Unregister from repmgr cluster
- Delete Railway service + volumes
- Remove from ProxySQL config
- Delete local directories

---

## 📚 References

- Main README: [README.md](README.md)
- Scripts Documentation: [README.md#scripts-documentation](README.md#-scripts-documentation)
- Security Audit: [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
- Client Connection Examples: [CLIENT_CONNECTION_EXAMPLES.md](CLIENT_CONNECTION_EXAMPLES.md)

---

**Last Updated**: October 27, 2025  
**Scripts Version**: 2.0.0
