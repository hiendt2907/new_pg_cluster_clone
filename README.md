# PostgreSQL High Availability Cluster on Railway
## with ProxySQL 3.0 BETA - High Performance

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-336791?logo=postgresql)](https://www.postgresql.org/)
[![repmgr](https://img.shields.io/badge/repmgr-5.5.0-green)](https://repmgr.org/)
[![ProxySQL](https://img.shields.io/badge/ProxySQL-3.0.2%20BETA-orange)](https://proxysql.com/)
[![Railway](https://img.shields.io/badge/Railway-Platform-purple)](https://railway.app/)

**Production-ready PostgreSQL cluster** with automatic failover, connection pooling, and security hardening - optimized for 60,000+ concurrent connections.

---

## � Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/hiendt2907/new_pg_cluster_clone.git
cd new_pg_cluster_clone

# 2. Login to Railway
railway login

# 3. Link to your project
railway link

# 4. Generate secure passwords (auto)
./railway-setup-shared-vars.sh

# 5. Deploy cluster (choose option 2: ProxySQL HA)
./railway-deploy.sh

# 6. Save credentials (generated automatically)
cat cluster-security-info.txt  # Save to password manager
rm cluster-security-info.txt   # Delete after saving

# 7. Get ProxySQL public URL
railway service proxysql && railway domain

# 8. Connect!
psql "postgresql://app_readwrite:<password>@<proxysql-domain>:5432/postgres"
```

**Read More:**
- 📖 [Full Setup Guide](#-cài-đặt-và-deploy)
- 🔒 [Security Guide](SECURITY.md)
- 📈 [Scaling Guide](SCALING_GUIDE.md)

---

## 📖 Table of Contents

1. [Overview](#-overview)
2. [Architecture](#-architecture)
3. [Features](#-features)
4. [Requirements](#-requirements)
5. [Setup & Deployment](#-cài-đặt-và-deploy)
6. [Client Connections](#-kết-nối-từ-client)
7. [Monitoring](#-monitoring--troubleshooting)
8. [Scaling](#-scaling)
9. [Security](#-security)
10. [Scripts Reference](#-scripts-documentation)

---

## 🎯 Overview

### What This Solves
- ✅ **High Availability**: Automatic failover when primary fails (10-30s RTO)
- ✅ **Scalability**: 4 PostgreSQL nodes + witness + horizontal scaling support
- ✅ **Connection Pooling**: 60,000 concurrent connections via ProxySQL HA pair
- ✅ **Query Routing**: Auto-route writes → primary, reads → standbys
- ✅ **Security**: Strong passwords, audit logging, application user separation
- ✅ **Railway Optimized**: IPv6, dynamic hostnames, container networking

### Use Cases
- 🚀 **High-Performance Applications**: Low-latency, high-throughput workloads
- 💼 **Production Databases**: Mission-critical apps requiring 99.9% uptime
- 📊 **Read-Heavy Workloads**: Distribute reads across 3 standby nodes
- 🔄 **Disaster Recovery**: Automatic failover with no manual intervention

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ CLIENT APPLICATIONS (Python, Node.js, Go, Java, Ruby, C#, etc.)            │
│                                                                             │
│   Multi-host Connection String:                                            │
│   postgresql://postgres:pass@proxysql.railway.app:5432,                    │
│                              proxysql-2.railway.app:5432/postgres          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ PROXYSQL HA LAYER (Connection Pooling + Query Routing)                     │
│                                                                             │
│   ┌──────────────────────┐              ┌──────────────────────┐          │
│   │   proxysql           │  ←────HA────→ │   proxysql-2         │          │
│   │  • 32 threads        │              │  • 32 threads        │          │
│   │  • 30k connections   │              │  • 30k connections   │          │
│   │  • Port 5432         │              │  • Port 5432         │          │
│   │  • Query routing     │              │  • Query routing     │          │
│   └──────────────────────┘              └──────────────────────┘          │
│                                                                             │
│   Query Rules:                                                              │
│   • SELECT FOR UPDATE → Primary (hostgroup 1)                              │
│   • INSERT/UPDATE/DELETE/DDL → Primary (hostgroup 1)                       │
│   • SELECT → Standbys round-robin (hostgroup 2)                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ POSTGRESQL CLUSTER (repmgr automatic failover)                             │
│                                                                             │
│   ┌────────┐         ┌────────┐         ┌────────┐         ┌────────┐    │
│   │  pg-1  │─streaming→ pg-2  │         │  pg-3  │         │  pg-4  │    │
│   │Primary │         │Standby │         │Standby │         │Standby │    │
│   │Node 1  │         │Node 2  │         │Node 3  │         │Node 4  │    │
│   └────────┘         └────────┘         └────────┘         └────────┘    │
│       ↑                   ↑                   ↑                   ↑        │
│       └───────────────────┴───────────────────┴───────────────────┘        │
│                                  ↑                                          │
│                           ┌──────────┐                                     │
│                           │ witness  │                                     │
│                           │ Node 99  │                                     │
│                           │ (Quorum) │                                     │
│                           └──────────┘                                     │
│                                                                             │
│   PostgreSQL 17 + repmgr 5.5.0                                             │
│   Automatic promotion: 10-30 seconds                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

#### PostgreSQL Cluster Layer
- **pg-1**: Primary hoặc Standby (tùy election), priority 199
- **pg-2**: Standby node, priority 198
- **pg-3**: Standby node, priority 197
- **pg-4**: Standby node, priority 196
- **witness**: Witness node cho quorum voting, không lưu data

#### ProxySQL Layer
- **proxysql**: Primary ProxySQL instance (30k connections, 32 threads)
- **proxysql-2**: Secondary ProxySQL instance (HA pair, identical config)

### Failover Algorithm

#### PostgreSQL Failover (repmgr)
```
1. Primary node (pg-1) fails
2. repmgrd on all standbys detects failure (poll_timeout=10s)
3. Witness votes for new primary
4. Standby with highest priority becomes primary:
   - pg-2 (priority 198) → promotes to primary
   - pg-3, pg-4 → re-point to new primary
5. Total failover time: 10-30 seconds
```

#### ProxySQL Failover (Client-side)
```
1. Client connects to: proxysql.railway.app,proxysql-2.railway.app
2. PostgreSQL driver tries proxysql first
3. If proxysql fails:
   - Driver automatically connects to proxysql-2
   - Reconnection time: 2 seconds (connect_timeout=2)
4. ProxySQL discovers new primary:
   - Queries pg_is_in_recovery() every 60s
   - Updates hostgroups automatically
   - Clients transparently redirected
```

---

## ✨ Các tính năng chính

### 🔒 High Availability Features
- ✅ **Automatic Failover**: repmgr tự động promote standby → primary khi detect failure
- ✅ **Quorum-based Voting**: Witness node prevents split-brain scenarios
- ✅ **Health Monitoring**: Continuous health checks via repmgrd daemon
- ✅ **ProxySQL HA**: Dual ProxySQL instances cho redundancy

### ⚡ Performance Optimizations
- ✅ **32 Threads**: ProxySQL sử dụng 32 worker threads (vs default 4)
- ✅ **60k Connections**: Total 60,000 concurrent connections (30k per ProxySQL)
- ✅ **20s Poll Timeout**: Fast failure detection (vs default 2s)
- ✅ **Connection Multiplexing**: Reuse backend connections để giảm overhead
- ✅ **Query Routing**: Distribute reads across 3 standby nodes

### 🛡️ Railway Platform Fixes
- ✅ **IPv6 Support**: Added `::/0` entries to `pg_hba.conf` (Railway uses IPv6 internally)
- ✅ **Dynamic Hostnames**: NODE_NAME from env vars (Railway containers have random hostnames)
- ✅ **Shared Variables**: Railway environment-level variables cho passwords
- ✅ **Witness Fix**: Fixed repmgr user/database creation for witness node

### 🔌 Query Routing Rules (ProxySQL)

| Query Type | Destination | Hostgroup | Example |
|------------|-------------|-----------|---------|
| `SELECT FOR UPDATE` | Primary only | 1 | `SELECT * FROM orders WHERE id=123 FOR UPDATE` |
| `INSERT/UPDATE/DELETE` | Primary only | 1 | `INSERT INTO trades VALUES (...)` |
| `CREATE/ALTER/DROP` | Primary only | 1 | `CREATE TABLE positions (...)` |
| `SELECT` (read-only) | Standbys (round-robin) | 2 | `SELECT * FROM market_data WHERE ...` |

---

## 📋 Yêu cầu

### Railway Platform
- **Plan**: Railway Pro Plan ($20/month)
- **Reason**: Free plan chỉ cho 1 service, Pro plan unlimited services
- **Resources**: ~2.5GB RAM total, 4 volumes

### Local Requirements
```bash
# Railway CLI
curl -fsSL https://railway.app/install.sh | sh

# Login
railway login

# Verify
railway whoami
```

### Cost Estimate
| Item | Cost |
|------|------|
| Railway Pro Plan | $20/month |
| 7 services compute | ~$5-15/month |
| 6 volumes (4×PostgreSQL + 2×ProxySQL, 10GB each) | ~$15/month |
| **Total** | **$40-50/month** |

---

## 📁 Cấu trúc project

```
new_pg_cluster_clone/
├── README.md                          # 📘 This file
├── README.old.md                      # 📘 Original README (backup)
│
├── RAILWAY_SETUP.md                   # 🔧 Railway setup instructions
├── RAILWAY_DEPLOYMENT.md              # 🚀 Deployment guide
├── RAILWAY_CLEANUP_GUIDE.md           # 🗑️ Cleanup procedures
├── PROXYSQL_HA_ENDPOINT.md            # 🔗 ProxySQL HA endpoint strategy
├── CLIENT_CONNECTION_EXAMPLES.md      # 💻 Client connection code examples
│
├── railway-deploy.sh                  # 🤖 Interactive deployment script
├── railway-auto-deploy.sh             # 🤖 Automated deployment (non-interactive)
├── railway-setup-shared-vars.sh       # ⚙️ Set shared environment variables
├── railway-add-node.sh                # ➕ Add new PostgreSQL node (scaling)
│
├── docker-compose.yml                 # 🐳 Local testing
├── railway.toml                       # ⚙️ Railway config
│
├── pg-1/                              # 🗄️ PostgreSQL Node 1
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── pg-2/                              # 🗄️ PostgreSQL Node 2
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── pg-3/                              # 🗄️ PostgreSQL Node 3
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── pg-4/                              # 🗄️ PostgreSQL Node 4
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── witness/                           # 👁️ Witness Node
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── proxysql/                          # 🔌 ProxySQL Instance 1
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   ├── README.md
│   └── .env
│
├── proxysql-2/                        # 🔌 ProxySQL Instance 2 (HA)
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── monitor.sh
│   └── .env
│
├── pgpool/                            # 🔌 (Alternative) pgpool-II
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── monitor.sh
│
├── shared/                            # 📦 Shared files (backup)
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── monitor.sh
│
├── witness_backup/                    # 📦 Witness backup
│   ├── entrypoint.sh
│   └── monitor.sh
│
└── scripts/                           # 📜 Test scripts
    └── test_full_flow.sh
```

### File Descriptions

#### PostgreSQL Nodes (`pg-1/`, `pg-2/`, `pg-3/`, `pg-4/`)
- **Dockerfile**: PostgreSQL 17 + repmgr 5.5.0 container
- **entrypoint.sh** (17KB): Initialization script với:
  - IPv6 support (`::/0` in pg_hba.conf)
  - NODE_NAME validation (required env var)
  - Primary/standby detection
  - repmgr registration
  - Automatic failover monitoring
- **monitor.sh** (5.9KB): Health check và monitoring
- **.env**: Service-specific environment variables

#### Witness Node (`witness/`)
- **entrypoint.sh** (18KB): Witness-specific logic:
  - **FIX**: Creates repmgr user/database (was missing)
  - Registers as witness node
  - Doesn't store data (no volume)

#### ProxySQL Instances (`proxysql/`, `proxysql-2/`)
- **Dockerfile**: ProxySQL 3.0.2 BETA for PostgreSQL
- **entrypoint.sh** (5.1KB): ProxySQL configuration:
  - Trading optimizations (32 threads, 30k conn, 20s poll)
  - Query routing rules
  - Auto-discovery of primary/standby nodes
  - Admin interface on port 6132
- **monitor.sh** (796B): Simple health check
- **README.md**: ProxySQL usage guide

---

## 🚀 Cài đặt và Deploy

### Quick Start (3 bước)

```bash
# 1. Clone repository
git clone https://github.com/hiendt2907/new_pg_cluster_clone.git
cd new_pg_cluster_clone

# 2. Link to Railway project
railway link  # Select "pg-cluster" from list

# 3. Deploy full cluster
./railway-deploy.sh
# Choose option 2: ProxySQL 3.0 BETA (2 instances)
```

### Deployment Options

#### Option 1: Interactive Deployment (Recommended)
```bash
./railway-deploy.sh
```
- Prompts cho proxy choice (none, ProxySQL, pgpool)
- Tự động detect existing services
- Deploy theo sequence: pg-1 → witness → (pg-2,pg-3,pg-4) → (proxysql,proxysql-2)

#### Option 2: Automated Deployment
```bash
./railway-auto-deploy.sh
```
- Non-interactive deployment
- Automated cleanup and redeployment

### Deployment Sequence

**⚠️ IMPORTANT**: Deploy theo đúng thứ tự để tránh lỗi!

```
1. Set shared environment variables
   └─→ ./railway-setup-shared-vars.sh

2. Create volumes
   ├─→ PostgreSQL nodes: /var/lib/postgresql/data (4 volumes)
   └─→ ProxySQL instances: /var/lib/proxysql (2 volumes)

3. Deploy pg-1 (primary candidate)
   └─→ Wait 30 seconds for initialization

4. Deploy witness
   └─→ Wait 10 seconds for registration

5. Deploy pg-2, pg-3, pg-4 in parallel
   └─→ Wait 60 seconds for cluster formation

6. Deploy proxysql + proxysql-2 in parallel
   └─→ Wait 30 seconds for service start
```

### Manual Deployment (via Dashboard)

Nếu muốn deploy thủ công qua Railway Dashboard:

1. **Create Services** (7 total)
   - pg-1, pg-2, pg-3, pg-4, witness, proxysql, proxysql-2

2. **Set Source**
   - GitHub: `hiendt2907/new_pg_cluster_clone`
   - Branch: `master`
   - Root Directory: `pg-1/`, `pg-2/`, etc.

3. **Set Environment Variables** (from `.env` files)

4. **Create Volumes**
   - **PostgreSQL nodes** (pg-1, pg-2, pg-3, pg-4):
     - Mount Path: `/var/lib/postgresql/data`
   - **ProxySQL instances** (proxysql, proxysql-2):
     - Mount Path: `/var/lib/proxysql`
     - Purpose: Persist configuration after restart
   - **Witness**: No volume needed (no data storage)

5. **Deploy** (theo sequence trên)

---

## ⚙️ Cấu hình chi tiết

### Environment Variables

#### Shared Variables (Railway Environment Level)
Set via `./railway-setup-shared-vars.sh`:

**⚠️ SECURITY: Generate strong passwords before deployment!**

```bash
# Generate secure passwords (example)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REPMGR_PASSWORD=$(openssl rand -base64 32)

# Or use your own strong passwords
POSTGRES_PASSWORD=YOUR_SECURE_PASSWORD   # PostgreSQL superuser password
REPMGR_PASSWORD=YOUR_SECURE_PASSWORD     # repmgr user password
PRIMARY_HINT=pg-1                        # Hint for initial primary
```

**Note**: All `.env` files use Railway reference variables `${{POSTGRES_PASSWORD}}` and `${{REPMGR_PASSWORD}}`, so passwords are managed centrally and not committed to Git.

#### PostgreSQL Nodes (Service-specific)

**pg-1/.env**:
```bash
NODE_NAME=pg-1
NODE_ID=1
PEERS=pg-2.railway.internal,pg-3.railway.internal
```

**pg-2/.env**:
```bash
NODE_NAME=pg-2
NODE_ID=2
PEERS=pg-1.railway.internal,pg-3.railway.internal
```

**pg-3/.env**:
```bash
NODE_NAME=pg-3
NODE_ID=3
PEERS=pg-1.railway.internal,pg-2.railway.internal
```

**pg-4/.env**:
```bash
NODE_NAME=pg-4
NODE_ID=4
PEERS=pg-1.railway.internal,pg-2.railway.internal
```

**witness/.env**:
```bash
NODE_NAME=witness
NODE_ID=99
IS_WITNESS=true
PRIMARY_HOST=pg-1.railway.internal
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal
```

#### ProxySQL Instances

**proxysql/.env** (and proxysql-2/.env):
```bash
PROXYSQL_ADMIN_USER=admin
PROXYSQL_ADMIN_PASSWORD=YOUR_SECURE_PASSWORD
PG_NODES=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
MONITOR_INTERVAL=5
```

### ProxySQL Configuration (High Performance)

From `proxysql/entrypoint.sh`:

```bash
pgsql_variables={
    threads=32                          # 32 worker threads (vs default 4)
    max_connections=30000               # 30k concurrent connections
    default_query_delay=0               # No artificial delay
    default_query_timeout=36000000      # 10h timeout
    poll_timeout=20000                  # 20s poll timeout (fast failover)
    interfaces="0.0.0.0:5432"          # Listen on standard PostgreSQL port
    multiplexing=true                   # Enable connection multiplexing
    monitor_username="${REPMGR_USER}"   # Use repmgr for monitoring
    monitor_password="${REPMGR_PASSWORD}"
    monitor_connect_interval=60000      # Check backends every 60s
}

pgsql_users=(
    {
        username="postgres"
        password="${POSTGRES_PASSWORD}"
        default_hostgroup=1
        max_connections=5000
        active=1
    }
    {
        username="repmgr"
        password="${REPMGR_PASSWORD}"
        default_hostgroup=1
        max_connections=100
        active=1
    }
)

pgsql_query_rules=(
    {
        rule_id=1
        match_pattern="^SELECT.*FOR UPDATE"
        destination_hostgroup=1    # Primary only
        apply=1
    }
    {
        rule_id=2
        match_pattern="^(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)"
        destination_hostgroup=1    # Primary only
        apply=1
    }
    {
        rule_id=3
        match_pattern="^SELECT"
        destination_hostgroup=2    # Standbys (round-robin)
        apply=1
    }
)

pgsql_replication_hostgroups=(
    {
        writer_hostgroup=1
        reader_hostgroup=2
        check_type="read_only"
    }
)
```

---

## 💻 Kết nối từ Client

### Multi-Host Connection String (Recommended)

**Format**:
```
postgresql://user:password@host1:port1,host2:port2/database?params
```

**Example**:
```bash
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?target_session_attrs=any&connect_timeout=2
```

### Connection Examples by Language

#### Python (psycopg2)
```python
import psycopg2
from psycopg2 import pool

# Multi-host connection pool
connection_pool = pool.ThreadedConnectionPool(
    minconn=100,
    maxconn=5000,
    host="proxysql-production.railway.app,proxysql-2-production.railway.app",
    port=5432,
    database="postgres",
    user="postgres",
    password="YOUR_SECURE_PASSWORD",
    target_session_attrs="any",
    connect_timeout=2
)

# Get connection
conn = connection_pool.getconn()
cursor = conn.cursor()
cursor.execute("SELECT * FROM trades")
connection_pool.putconn(conn)
```

#### Node.js (pg)
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'proxysql-production.railway.app,proxysql-2-production.railway.app',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: 'YOUR_SECURE_PASSWORD',
  max: 5000,
  connectionTimeoutMillis: 2000
});

const result = await pool.query('SELECT * FROM trades');
```

#### Go (pgx)
```go
import "github.com/jackc/pgx/v5/pgxpool"

connString := "postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?pool_max_conns=5000"

pool, err := pgxpool.New(context.Background(), connString)
defer pool.Close()
```

#### Java (JDBC + HikariCP)
```java
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:postgresql://proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres");
config.setUsername("postgres");
config.setPassword("YOUR_SECURE_PASSWORD");
config.setMaximumPoolSize(5000);

HikariDataSource dataSource = new HikariDataSource(config);
```

📘 **More examples**: See [CLIENT_CONNECTION_EXAMPLES.md](CLIENT_CONNECTION_EXAMPLES.md)

---

## 🔍 Monitoring & Troubleshooting

### Check Cluster Status

#### SSH into pg-1
```bash
railway ssh --service pg-1
```

#### Inside container - Check repmgr cluster
```bash
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Expected output**:
```
 ID | Name    | Role    | Status    | Upstream | Location | Priority | Timeline
----+---------+---------+-----------+----------+----------+----------+----------
 1  | pg-1    | primary | * running |          | default  | 199      | 1
 2  | pg-2    | standby |   running | pg-1     | default  | 198      | 1
 3  | pg-3    | standby |   running | pg-1     | default  | 197      | 1
 4  | pg-4    | standby |   running | pg-1     | default  | 196      | 1
 99 | witness | witness | * running | pg-1     | default  | 0        | n/a
```

### Check ProxySQL Status

#### Connect to ProxySQL admin interface
```bash
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql-production.railway.app -p 6132 -U admin -d proxysql
```

#### Check backend servers
```sql
SELECT hostgroup_id, hostname, port, status, Queries, Latency_us 
FROM stats_pgsql_connection_pool 
ORDER BY hostgroup_id, Queries DESC;
```

**Expected output**:
```
 hostgroup_id |          hostname           | port | status  | Queries | Latency_us
--------------+-----------------------------+------+---------+---------+------------
            1 | pg-1.railway.internal       | 5432 | ONLINE  |   15234 |        120
            2 | pg-2.railway.internal       | 5432 | ONLINE  |    8521 |        115
            2 | pg-3.railway.internal       | 5432 | ONLINE  |    8498 |        118
            2 | pg-4.railway.internal       | 5432 | ONLINE  |    8476 |        122
```

### Check Railway Logs

```bash
# View logs for specific service
railway logs --service pg-1 --follow
railway logs --service proxysql --follow

# View logs for all services (multiple terminals)
railway logs --service pg-1 &
railway logs --service pg-2 &
railway logs --service proxysql &
```

### Common Issues & Solutions

#### Issue: Services không start được

**Symptoms**:
```
railway logs --service pg-1
Error: failed to create container
```

**Solutions**:
```bash
# 1. Check volume permissions
# Volume MUST mount to /var/lib/postgresql/data (not /data)

# 2. Check environment variables
railway variables list --service pg-1

# 3. Check Railway resource limits
railway status
```

#### Issue: Cluster không hình thành

**Symptoms**:
```bash
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
# Shows only pg-1 or errors
```

**Solutions**:
```bash
# 1. Check deployment order
# pg-1 MUST be deployed first, then witness, then others

# 2. Check PEERS configuration
railway variables list --service pg-2
# PEERS should be: pg-1.railway.internal,pg-3.railway.internal

# 3. Check logs for connection errors
railway logs --service pg-2 | grep "connection"

# 4. SSH into standby and check repmgr config
railway ssh --service pg-2
cat /etc/repmgr/repmgr.conf
```

#### Issue: ProxySQL không discover nodes

**Symptoms**:
```sql
SELECT * FROM stats_pgsql_connection_pool;
-- Empty or missing nodes
```

**Solutions**:
```bash
# 1. Check ProxySQL can connect to PostgreSQL nodes
railway ssh --service proxysql
psql -h pg-1.railway.internal -U postgres -d postgres

# 2. Check monitor credentials
railway variables list --service proxysql | grep REPMGR

# 3. Manually add servers (temporary)
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql.railway.app -p 6132 -U admin -d proxysql
INSERT INTO pgsql_servers (hostgroup_id, hostname, port) VALUES (1, 'pg-1.railway.internal', 5432);
LOAD PGSQL SERVERS TO RUNTIME;
```

#### Issue: Replication lag

**Symptoms**:
```sql
-- On primary
SELECT * FROM pg_stat_replication;
-- Large replay_lag values
```

**Solutions**:
```bash
# 1. Check network latency between Railway regions
# 2. Increase wal_sender settings (if needed)
# 3. Monitor disk I/O on standbys
```

### Performance Monitoring

#### PostgreSQL Metrics
```sql
-- Replication lag
SELECT client_addr, state, sync_state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Active connections
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';

-- Database size
SELECT pg_size_pretty(pg_database_size('postgres'));
```

#### ProxySQL Metrics
```sql
-- Connection pool stats
SELECT hostgroup_id, srv_host, status, ConnUsed, ConnFree, Queries, Latency_us
FROM stats_pgsql_connection_pool;

-- Query rules statistics
SELECT rule_id, hits FROM stats_pgsql_query_rules ORDER BY hits DESC;

-- Global variables
SELECT * FROM global_variables WHERE variable_name LIKE '%connection%';
```

---

## 📜 Scripts Documentation

### Deployment Scripts

#### 1. railway-setup-shared-vars.sh

**Purpose**: Generate and set shared passwords for entire cluster

**Usage**:
```bash
./railway-setup-shared-vars.sh
```

**Features**:
- Auto-generates 32-char secure passwords (OpenSSL)
- Sets Railway environment variables (environment-level scope)
- Passwords shared across all nodes via `${{VARIABLE_NAME}}` references

**Generated Variables**:
- `POSTGRES_PASSWORD` - PostgreSQL superuser password
- `REPMGR_PASSWORD` - repmgr replication user password
- `PRIMARY_HINT` - Bootstrap primary node (default: pg-1)

#### 2. railway-deploy.sh

**Purpose**: Interactive deployment with cluster info logging

**Usage**:
```bash
./railway-deploy.sh
# Choose proxy option:
#   1) No proxy
#   2) ProxySQL 3.0 BETA (2 instances for HA) ← Recommended
#   3) pgpool-II
```

**Features**:
- Prompts for proxy choice
- Deploys in correct sequence (pg-1 → witness → standbys → proxy)
- Creates volumes automatically
- **NEW**: Generates `cluster-info.txt` with connection info after deployment

**Deployment Sequence**:
```bash
# 1. Deploy primary first
pg-1 → wait 30s

# 2. Deploy witness
witness → wait 10s

# 3. Deploy standbys in parallel
pg-2, pg-3, pg-4 → wait for completion

# 4. Deploy proxy (if selected)
proxysql, proxysql-2 → parallel deployment

# 5. Generate cluster-info.txt
- Cluster credentials
- Connection strings
- ProxySQL endpoints
- Monitoring commands
```

#### 3. railway-auto-deploy.sh

**Purpose**: Automated deployment without prompts

**Usage**:
```bash
./railway-auto-deploy.sh
```

**Features**:
- No manual interaction required
- Full cleanup option
- Same deployment logic as railway-deploy.sh

### Scaling Scripts

#### 4. railway-add-node.sh ⭐ NEW

**Purpose**: Add new PostgreSQL node to cluster

**Usage**:
```bash
./railway-add-node.sh 5     # Add pg-5
./railway-add-node.sh 6     # Add pg-6
```

**Features**:
- ✅ Copy folder from pg-4 template
- ✅ Auto-generate .env with NODE_NAME, NODE_ID
- ✅ Create Railway service + volume
- ✅ Deploy new node
- ✅ Update ProxySQL configuration (both instances)
- ✅ Redeploy ProxySQL to discover new node

**Key Functions**:

```bash
# Validate node number (must be >= 5)
if [ "$NODE_NUM" -lt 5 ]; then
    log_error "Node number must be >= 5 (pg-1 to pg-4 already exist)"
    exit 1
fi

# Copy template
cp -r "$PROJECT_DIR/pg-4" "$NODE_DIR"

# Generate .env
cat > "$NODE_DIR/.env" <<EOF
NODE_NAME=$NODE_NAME
NODE_ID=$NODE_NUM
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal
POSTGRES_PASSWORD=\${{POSTGRES_PASSWORD}}
REPMGR_PASSWORD=\${{REPMGR_PASSWORD}}
PRIMARY_HINT=\${{PRIMARY_HINT}}
EOF

# Update ProxySQL
for proxy in "proxysql" "proxysql-2"; do
    NEW_NODES="${CURRENT_NODES},${NODE_NAME}.railway.internal"
    sed -i "s|^: \"\${PG_NODES:=.*}|: \"\${PG_NODES:=$NEW_NODES}\"|" "$proxy/entrypoint.sh"
    railway service "$proxy"
    railway up --detach
done
```

#### 5. railway-remove-node.sh ⭐ NEW

**Purpose**: Remove PostgreSQL node from cluster

**Usage**:
```bash
./railway-remove-node.sh 5     # Remove pg-5
./railway-remove-node.sh 6     # Remove pg-6
```

**Features**:
- ✅ Protected: Cannot remove core nodes (pg-1 to pg-4)
- ✅ Unregister from repmgr cluster
- ✅ Delete Railway service (including volume data)
- ✅ Remove from ProxySQL configuration
- ✅ Redeploy ProxySQL instances
- ✅ Delete local directory

**Safety Checks**:
```bash
# Prevent removing core nodes
if [ "$NODE_NUM" -le 4 ]; then
    log_error "Cannot remove core nodes (pg-1 to pg-4)"
    log_error "These are essential for cluster quorum"
    exit 1
fi

# Confirmation prompt
read -p "Are you sure? Type 'yes' to continue: " confirmation
if [ "$confirmation" != "yes" ]; then
    log_info "Operation cancelled"
    exit 0
fi
```

### Utility Scripts

#### 6. railway-list-services.sh

**Purpose**: List all Railway services in project
    wait
    sleep 60
    
    # 4. Deploy ProxySQL (if selected)
    if [ "$proxy_choice" == "2" ]; then
        create_service "proxysql" "proxysql" &
        create_service "proxysql-2" "proxysql-2" &
        wait
    fi
}
```

### 2. railway-auto-deploy.sh (6.0KB)

**Purpose**: Automated deployment without manual prompts

**Usage**:
```bash
./railway-auto-deploy.sh
# Choose option 1: Delete old + deploy new
```

**Features**:
- Non-interactive deployment
- Automated cleanup and redeployment
- Same deployment sequence as railway-deploy.sh

### 3. railway-setup-shared-vars.sh

**Purpose**: Set Railway environment-level shared variables

**Usage**:
```bash
./railway-setup-shared-vars.sh
```

**Auto-generates** (if not provided):
- `POSTGRES_PASSWORD` (32-char secure password via OpenSSL)
- `REPMGR_PASSWORD` (32-char secure password via OpenSSL)
- `PRIMARY_HINT=pg-1`

**Manual override**:
```bash
POSTGRES_PASSWORD=YourPassword REPMGR_PASSWORD=YourPassword ./railway-setup-shared-vars.sh
```

### 4. railway-add-node.sh

**Purpose**: Add new PostgreSQL node to cluster (horizontal scaling)

**Usage**:
```bash
# Add pg-5
./railway-add-node.sh 5

# Add pg-6
./railway-add-node.sh 6
```

**What it does**:
1. Creates `pg-N/` folder from `pg-4/` template
2. Configures `.env` with NODE_NAME and NODE_ID
3. Creates Railway service
4. Sets environment variables
5. Adds volume for PostgreSQL data
6. Deploys to Railway
7. **Updates ProxySQL without restart** (LOAD TO RUNTIME, SAVE TO DISK)

**Timeline**: ~1-2 minutes total

See `SCALING_GUIDE.md` for details.

---

## 🎓 Advanced Topics

### Scaling: Thêm PostgreSQL Node mới

#### Automated with Script (Recommended)

```bash
# Thêm node thứ 5 (pg-5)
./railway-add-node.sh 5

# Thêm node thứ 6 (pg-6)
./railway-add-node.sh 6

# Script tự động:
# ✅ Copy folder từ pg-4 template
# ✅ Cập nhật .env với NODE_NAME, NODE_ID
# ✅ Tạo Railway service và add volume
# ✅ Deploy service mới
# ✅ Cập nhật ProxySQL configuration
# ✅ Redeploy ProxySQL instances
```

#### Thủ công (Manual)

```bash
# 1. Copy template và tạo folder mới
cp -r pg-4 pg-5

# 2. Update .env file
cd pg-5
cat > .env << 'EOF'
NODE_NAME=pg-5
NODE_ID=5
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal
POSTGRES_PASSWORD=${{POSTGRES_PASSWORD}}
REPMGR_PASSWORD=${{REPMGR_PASSWORD}}
PRIMARY_HINT=${{PRIMARY_HINT}}
EOF

# 3. Deploy service
cd ..
railway add --service pg-5
cd pg-5
railway service pg-5
railway variables --set "NODE_NAME=pg-5" --skip-deploys
railway variables --set "NODE_ID=5" --skip-deploys
echo "/var/lib/postgresql" | railway volume add
railway up --detach

# 4. Update ProxySQL (edit proxysql/entrypoint.sh)
# Thay đổi dòng:
# : "${PG_NODES:=pg-1,...,pg-4.railway.internal}"
# Thành:
# : "${PG_NODES:=pg-1,...,pg-4.railway.internal,pg-5.railway.internal}"

# 5. Redeploy ProxySQL
cd ../proxysql
railway service proxysql
railway up --detach

cd ../proxysql-2
railway service proxysql-2
railway up --detach

# 6. Verify cluster
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
# Should show pg-5 as standby
```

### Scaling: Xóa PostgreSQL Node

```bash
# Xóa node pg-5 (chỉ xóa được node >= 5, core nodes pg-1 đến pg-4 bị protected)
./railway-remove-node.sh 5

# Script tự động:
# ✅ Unregister node từ repmgr cluster
# ✅ Xóa Railway service (kèm volume)
# ✅ Remove khỏi ProxySQL configuration
# ✅ Redeploy ProxySQL instances
# ✅ Xóa local directory
```

### Manual Failover Testing

```bash
# 1. SSH into current primary (e.g., pg-1)
railway ssh --service pg-1

# 2. Stop PostgreSQL
gosu postgres pg_ctl -D /var/lib/postgresql/data stop -m fast

# 3. Watch repmgr logs on standbys
railway logs --service pg-2 --follow

# Expected:
# - pg-2 detects pg-1 failure (within 10s)
# - Witness votes for promotion
# - pg-2 promotes itself to primary
# - pg-3, pg-4 re-point to pg-2
```

### Backup and Restore

#### Using Railway Volume Snapshots
```bash
# Railway automatically takes daily snapshots of volumes
# Restore via Dashboard → Service → Volumes → Restore Snapshot
```

#### Manual Backup (pg_dump)
```bash
# SSH into primary
railway ssh --service pg-1

# Backup database
gosu postgres pg_dump -Fc postgres > /tmp/backup_$(date +%Y%m%d).dump

# Copy from container to local
railway ssh --service pg-1 -- cat /tmp/backup_20251027.dump > backup_local.dump
```

#### Manual Restore
```bash
# Upload to container
cat backup_local.dump | railway ssh --service pg-1 -- "cat > /tmp/restore.dump"

# Restore
railway ssh --service pg-1
gosu postgres pg_restore -d postgres /tmp/restore.dump
```

### Security Hardening

> **🔒 PASSWORD POLICY**
> - **All example passwords in this documentation use placeholder `YOUR_SECURE_PASSWORD`**
> - **Real passwords are auto-generated (32-character random) via `railway-setup-shared-vars.sh`**
> - **All .env files use Railway reference variables (`${{POSTGRES_PASSWORD}}`), so passwords are NEVER committed to Git**
> - **Never use example passwords in production - they are for syntax demonstration only**

#### 1. Auto-Generated Passwords (Recommended)
```bash
# Run Railway setup script to auto-generate secure passwords
./railway-setup-shared-vars.sh

# This will:
# 1. Generate random 32-character passwords using OpenSSL
# 2. Set Railway shared variables automatically
# 3. Display generated passwords (save them securely!)
```

#### 2. Manual Password Generation (Alternative)
```bash
# Generate secure passwords manually
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REPMGR_PASSWORD=$(openssl rand -base64 32)

# Update Railway shared variables
railway variables set \
  POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  REPMGR_PASSWORD=$REPMGR_PASSWORD
```

#### 3. Restrict pg_hba.conf
```bash
# Edit pg-*/entrypoint.sh
# Replace:
host all all ::/0 md5
# With:
host all all <your-ip-range> md5
```

#### 3. Enable SSL/TLS (Optional)
```bash
# Generate certificates
openssl req -new -x509 -days 365 -nodes -text -out server.crt -keyout server.key -subj "/CN=pg-cluster"

# Upload to Railway services
# Configure PostgreSQL to use SSL
```

### Monitoring with Prometheus + Grafana

#### 1. Export PostgreSQL Metrics
```bash
# Add postgres_exporter to each PostgreSQL service
# Dockerfile addition:
RUN apt-get install -y prometheus-postgres-exporter

# Expose port 9187 for metrics
```

#### 2. Export ProxySQL Metrics
```bash
# ProxySQL has built-in stats tables
# Query via admin interface and export to Prometheus format
```

#### 3. Deploy Grafana Dashboard
```bash
# Use Railway template for Grafana
# Import dashboard: https://grafana.com/grafana/dashboards/9628
```

---

## 📚 Additional Resources

### Documentation
- 📖 [RAILWAY_SETUP.md](RAILWAY_SETUP.md) - Detailed Railway setup
- 📖 [RAILWAY_DEPLOYMENT.md](RAILWAY_DEPLOYMENT.md) - Step-by-step deployment
- 📖 [PROXYSQL_HA_ENDPOINT.md](PROXYSQL_HA_ENDPOINT.md) - Endpoint strategy
- 📖 [CLIENT_CONNECTION_EXAMPLES.md](CLIENT_CONNECTION_EXAMPLES.md) - Client code examples

### External Links
- [Railway Documentation](https://docs.railway.app)
- [PostgreSQL 17 Documentation](https://www.postgresql.org/docs/17/)
- [repmgr Documentation](https://repmgr.org/docs/current/)
- [ProxySQL Documentation](https://proxysql.com/documentation/)

### Support
- GitHub Issues: https://github.com/hiendt2907/new_pg_cluster_clone/issues
- Railway Community: https://railway.app/discord

---

## 📝 License

This project is provided as-is for educational and production use.

---

## 🙏 Credits

- **PostgreSQL**: The World's Most Advanced Open Source Relational Database
- **repmgr**: Replication Manager for PostgreSQL clusters
- **ProxySQL**: High-performance proxy for PostgreSQL
- **Railway**: Modern platform for deploying applications

---

## 📊 Status

- ✅ **Production Ready**: Tested on Railway Pro Plan
- ✅ **High Performance**: 60k connections, low latency
- ⚠️ **ProxySQL BETA**: PostgreSQL support is still in BETA (v3.0.2)

---

**Last Updated**: October 27, 2025
**Version**: 2.0.0
**Maintained by**: hiendt1@outlook.com.vn
