# ProxySQL HA Endpoint Strategy for Railway

## Problem
Railway không support keepalived (VIP) vì:
- Container networking không cho phép L2/L3 network manipulation
- Không có multicast support
- Mỗi service có riêng internal DNS

## Solution: Railway TCP Proxy với Public Domain

### Architecture
```
Client Application
        ↓
Railway Public Domain (TCP Proxy)
        ↓
proxysql (active) ← Railway auto-failover → proxysql-2 (standby)
        ↓
pg-1 (primary), pg-2/3/4 (standbys) + witness
```

### Setup Steps

#### 1. Deploy ProxySQL HA
```bash
./railway-deploy.sh
# Choose option 2: ProxySQL 3.0 BETA (2 instances)
```

#### 2. Expose Primary ProxySQL Public Domain
```bash
# Via Railway CLI
cd proxysql
railway service proxysql
railway domain

# Or via Railway Dashboard:
# Go to proxysql service → Settings → Networking → Generate Domain
```

#### 3. Configure Custom TCP Port (5432)
Railway Dashboard:
1. Go to `proxysql` service
2. Settings → Networking
3. Add TCP Proxy: Port 5432
4. Copy public endpoint: `proxysql-production.railway.app:5432`

#### 4. Client Connection
```bash
# Primary endpoint (proxysql)
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432/postgres

# Fallback endpoint (proxysql-2) - if primary fails
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-2-production.railway.app:5432/postgres
```

### Client-Side Failover (Recommended for Trading)

#### Option 1: PostgreSQL Native Connection String
```bash
# Multi-host connection string with automatic failover
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?target_session_attrs=read-write
```

#### Option 2: Application-Level HAProxy/DNS Round-Robin
Deploy your own HAProxy/Nginx TCP proxy that round-robins between:
- `proxysql-production.railway.app:5432`
- `proxysql-2-production.railway.app:5432`

#### Option 3: PgBouncer Layer (Extra Layer)
```
Client → PgBouncer (your infra) → ProxySQL-1/2 (Railway)
```

### Production Setup for Trading System

**Recommended Architecture:**
```
Trading App (your infra)
       ↓
   HAProxy/Nginx (TCP mode, your infra)
       ↓
   ├─→ proxysql.railway.app:5432  (50% traffic)
   └─→ proxysql-2.railway.app:5432 (50% traffic)
       ↓
   PostgreSQL Cluster (Railway)
```

**HAProxy Config Example:**
```haproxy
frontend postgres_frontend
    bind *:5432
    mode tcp
    option tcplog
    default_backend postgres_backend

backend postgres_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server proxysql1 proxysql-production.railway.app:5432 check
    server proxysql2 proxysql-2-production.railway.app:5432 check backup
```

### Monitoring & Health Checks

```bash
# Check ProxySQL health
curl -s https://proxysql-production.railway.app:6132/health || \
  PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql-production.railway.app -p 6132 -U admin -d proxysql -c "SELECT 1;"

# Check backend pool
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql-production.railway.app -p 6132 -U admin -d proxysql \
  -c "SELECT hostgroup_id,hostname,status,Queries,Latency_us FROM stats_pgsql_connection_pool;"
```

### Single Endpoint via DNS (Simplest for POC)

**Use Railway's Primary Service:**
- Only expose `proxysql` publicly (port 5432)
- `proxysql-2` runs as hot-standby (internal only)
- If `proxysql` fails, Railway auto-restarts it
- Manual failover: promote `proxysql-2` by exposing its domain

**For Production Trading:**
- Deploy HAProxy/Nginx on your infrastructure
- Health-check both ProxySQL instances
- Automatic failover between them
- Single stable endpoint for your trading app

### Notes
- Railway doesn't support VIP/keepalived (container limitation)
- Best practice: Client-side connection pooling + multi-host failover
- For low-latency trading: Deploy HAProxy closer to your app
- ProxySQL handles PostgreSQL cluster failover automatically
