# Project Structure

Clean and organized structure for easy navigation.

```
new_pg_cluster_clone/
├── 📄 QUICK_START.md           # Start here! 5-minute deployment guide
├── 📄 README.md                # Complete documentation
├── 📄 SECURITY.md              # Security guide & penetration testing
├── 📄 SCALING_GUIDE.md         # How to add/remove nodes
│
├── 🔧 railway-setup-shared-vars.sh  # Generate passwords (run first)
├── 🚀 railway-deploy.sh             # Deploy cluster (run second)
├── ➕ railway-add-node.sh            # Add PostgreSQL nodes (pg-5, pg-6, ...)
│
├── �� PostgreSQL Nodes/
│   ├── pg-1/                    # Primary node (or standby after failover)
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh        # Cluster init & failover logic
│   │   ├── monitor.sh           # Health monitoring
│   │   └── .env                 # NODE_NAME=pg-1, NODE_ID=1
│   ├── pg-2/                    # Standby node
│   ├── pg-3/                    # Standby node
│   ├── pg-4/                    # Standby node
│   └── witness/                 # Witness node (quorum only, no data)
│
├── 🔀 Connection Pooling/
│   ├── proxysql/                # ProxySQL instance 1
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh        # Auto-discover nodes, query routing
│   │   ├── monitor.sh
│   │   └── .env                 # PG_NODES=pg-1,pg-2,pg-3,pg-4
│   ├── proxysql-2/              # ProxySQL instance 2 (HA pair)
│   └── pgpool/                  # Alternative: pgpool-II (not deployed by default)
│
├── 📜 scripts/
│   ├── generate-security-info.sh  # Auto-generate cluster-security-info.txt
│   └── test_full_flow.sh          # Integration tests (optional)
│
├── ⚙️ Configuration/
│   ├── docker-compose.yml       # Local testing (not used on Railway)
│   ├── railway.toml             # Railway build config
│   └── .gitignore               # Prevent committing sensitive files
│
└── 🔒 Generated Files (DO NOT COMMIT)/
    └── cluster-security-info.txt  # Auto-generated after deployment
                                   # Contains all passwords & procedures
                                   # SAVE TO PASSWORD MANAGER THEN DELETE
```

---

## File Descriptions

### 📄 Documentation (Read These)

| File | Purpose | When to Read |
|------|---------|--------------|
| `QUICK_START.md` | **Start here!** 5-minute deployment guide | First time setup |
| `README.md` | Complete architecture, configuration, troubleshooting | Deep dive |
| `SECURITY.md` | Security hardening, penetration testing, incident response | Before production |
| `SCALING_GUIDE.md` | Add/remove PostgreSQL nodes, performance tuning | When scaling |

### 🔧 Deployment Scripts (Run These)

| Script | Purpose | Usage |
|--------|---------|-------|
| `railway-setup-shared-vars.sh` | Generate 5 secure passwords | **Run FIRST** before deployment |
| `railway-deploy.sh` | Deploy entire cluster (7 services) | **Run SECOND** after passwords |
| `railway-add-node.sh` | Add new PostgreSQL node (pg-5, pg-6, ...) | When horizontal scaling |

### 🐘 PostgreSQL Nodes (4 + Witness)

Each node directory contains:
- `Dockerfile`: PostgreSQL 17 + repmgr 5.5.0 image
- `entrypoint.sh`: Cluster initialization & failover logic
- `monitor.sh`: Health monitoring (PID checks, repmgr status)
- `.env`: Node-specific config (NODE_NAME, NODE_ID, PEERS)

**Node Roles:**
- `pg-1`: Typically primary (but can change after failover)
- `pg-2, pg-3, pg-4`: Standby nodes (read-only replicas)
- `witness`: Quorum node (no data, only votes in elections)

### 🔀 Connection Pooling

**ProxySQL (Recommended):**
- 2 instances (HA pair)
- 30,000 connections each (60,000 total)
- Auto-discovery of PostgreSQL nodes
- Query routing (writes→primary, reads→standbys)
- Admin interface: `127.0.0.1:6132` (localhost only)

**pgpool-II (Alternative):**
- Available but not deployed by default
- Use if you prefer pgpool over ProxySQL

### 📜 Scripts Directory

| Script | Purpose |
|--------|---------|
| `generate-security-info.sh` | Auto-called by `railway-deploy.sh` after deployment |
| `test_full_flow.sh` | Optional integration tests |

### ⚙️ Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Local testing (not used on Railway) |
| `railway.toml` | Railway build configuration |
| `.gitignore` | Prevent committing sensitive files |

### 🔒 Generated Files (Git-Ignored)

| File | Contents | Action Required |
|------|----------|-----------------|
| `cluster-security-info.txt` | All 5 passwords, connection strings, procedures | **SAVE TO PASSWORD MANAGER** then DELETE |

---

## Deployment Flow

```
1. railway-setup-shared-vars.sh
   ↓ Generates 5 passwords (32 chars each)
   ↓ Stores in Railway environment variables
   
2. railway-deploy.sh
   ↓ Deploys 7 services in order:
   ↓   • pg-1 (primary)
   ↓   • witness
   ↓   • pg-2, pg-3, pg-4 (standbys)
   ↓   • proxysql, proxysql-2
   ↓ Calls generate-security-info.sh
   ↓ Creates cluster-security-info.txt
   
3. User Actions:
   ↓ Save cluster-security-info.txt to password manager
   ↓ Delete local file: rm cluster-security-info.txt
   ↓ Get ProxySQL domain: railway domain
   ↓ Connect: psql "postgresql://app_readwrite:...@domain:5432/postgres"
```

---

## Service Dependencies

```
Primary Node (pg-1)
  ↓
  ├─→ Witness (connects to primary for quorum)
  ├─→ pg-2 (replicates from primary)
  ├─→ pg-3 (replicates from primary)
  └─→ pg-4 (replicates from primary)

ProxySQL-1 & ProxySQL-2 (discover all nodes)
  ↓
  ├─→ Hostgroup 1 (primary): pg-1
  └─→ Hostgroup 2 (standbys): pg-2, pg-3, pg-4
```

---

## File Size & Complexity

| Component | Lines of Code | Complexity |
|-----------|--------------|------------|
| `entrypoint.sh` (PostgreSQL) | ~450 lines | High (failover logic, last-known-primary) |
| `entrypoint.sh` (ProxySQL) | ~180 lines | Medium (auto-discovery, topology monitor) |
| `railway-deploy.sh` | ~470 lines | Medium (service orchestration) |
| `railway-add-node.sh` | ~200 lines | Low (template-based node creation) |
| `SECURITY.md` | ~500 lines | Reference (security procedures) |

---

## What's NOT in This Repository

- ❌ Application code (this is database infrastructure only)
- ❌ Sample data or migrations
- ❌ Kubernetes manifests (Railway-specific)
- ❌ Terraform/IaC (uses Railway CLI)
- ❌ CI/CD pipelines (manual deployment via scripts)

---

## Clean vs. Dirty State

### ✅ Clean State (After Setup)
```
new_pg_cluster_clone/
├── Documentation (4 files)
├── Scripts (3 files)
├── Node directories (9 folders)
├── Configuration (3 files)
└── .git/
```

### ⚠️ Dirty State (During/After Deployment)
```
new_pg_cluster_clone/
├── ...
├── cluster-security-info.txt    ← DELETE AFTER SAVING!
└── cluster-info.txt             ← Optional, can delete
```

**Remember:** Files matching `.gitignore` are automatically excluded from Git.

---

## Key Takeaways

1. **Start with:** `QUICK_START.md` → 5 minutes to deployed cluster
2. **Deep dive:** `README.md` → Full architecture & configuration
3. **Production:** `SECURITY.md` → Security hardening & pentesting
4. **Scaling:** `SCALING_GUIDE.md` → Add nodes dynamically

5. **Always:**
   - Run `railway-setup-shared-vars.sh` BEFORE deployment
   - Save `cluster-security-info.txt` to password manager
   - Delete `cluster-security-info.txt` after saving
   - Review `SECURITY.md` before production

6. **Never:**
   - Commit `cluster-security-info.txt` to Git
   - Use `postgres` superuser for applications
   - Expose ProxySQL admin port (6132) publicly
   - Skip security review before production

---

**Last Updated:** October 27, 2025  
**Total Files:** ~30 (code + docs)  
**Total Size:** ~150KB (excluding .git)
