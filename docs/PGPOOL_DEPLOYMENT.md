# Pgpool-II Deployment Guide# Pgpool-II Deployment Guide



Chi tiết về triển khai, cấu hình và vận hành pgpool-II trong PostgreSQL HA cluster.## Overview



## 📋 Mục lụcĐã thay thế **ProxySQL** bằng **Pgpool-II** để có read/write splitting production-ready. Cấu hình bao gồm 2 instance pgpool với watchdog cho HA.



- [Giới thiệu](#giới-thiệu)## Kiến trúc

- [Kiến trúc](#kiến-trúc)

- [Cài đặt](#cài-đặt)```

- [Cấu hình](#cấu-hình)┌─────────────────────────────────────────────────────────────┐

- [Authentication](#authentication)│                      Application Layer                      │

- [Read/Write Splitting](#readwrite-splitting)├──────────────────────┬──────────────────────────────────────┤

- [Connection Pooling](#connection-pooling)│   pgpool-1:15432     │         pgpool-2:15433               │

- [High Availability](#high-availability)│   (Priority: 1)      │         (Priority: 2)                │

- [Monitoring](#monitoring)└──────────┬───────────┴────────────┬─────────────────────────┘

- [Troubleshooting](#troubleshooting)           │    Watchdog Heartbeat  │

           │    (Port 9694)         │

## Giới thiệu           ├────────────────────────┤

           │                        │

### Pgpool-II là gì?┌──────────▼────────────────────────▼────────────────────────┐

│              PostgreSQL Cluster (4 nodes)                  │

Pgpool-II là middleware nằm giữa PostgreSQL server và clients, cung cấp:├────────────┬──────────────┬──────────────┬─────────────────┤

│  pg-1      │   pg-2       │   pg-3       │   pg-4          │

- **Connection Pooling**: Tái sử dụng connections, giảm overhead│  Primary   │   Standby    │   Standby    │   Standby       │

- **Load Balancing**: Phân tải queries đến multiple nodes│  weight=0  │   weight=1   │   weight=1   │   weight=1      │

- **Automatic Failover**: Phát hiện và xử lý node failures│  (writes)  │   (reads)    │   (reads)    │   (reads)       │

- **Query Routing**: Intelligent routing based on query type└────────────┴──────────────┴──────────────┴─────────────────┘

```

### Tại sao chọn Pgpool-II?

## Tính năng chính

✅ **Ưu điểm**:

- Native PostgreSQL protocol support### 1. Read/Write Splitting

- Mature, production-proven (20+ years)- **Write queries** (INSERT/UPDATE/DELETE/BEGIN) → **pg-1 (Primary)**

- Advanced query analysis và routing- **Read queries** (SELECT) → **pg-2/3/4 (Standbys)** với load balancing

- Built-in connection pooling- Backend weight configuration:

- SCRAM-SHA-256 authentication support  - `pg-1`: weight=0 (writes only)

- Active development và community  - `pg-2/3/4`: weight=1 (reads distributed equally)



❌ **Nhược điểm so với ProxySQL**:### 2. High Availability (Watchdog)

- Phức tạp hơn trong configuration- 2 pgpool instances với watchdog enabled

- Ít dashboard/UI tools- Automatic failover nếu một pgpool instance down

- Cần setup pool_passwd file- Heartbeat monitoring (port 9694)

- Priority-based leader election (pgpool-1 priority=1, pgpool-2 priority=2)

## Kiến trúc

### 3. Connection Pooling

### Deployment Model- Max connections: 100 per pgpool instance

- Statement-level load balancing

```- Automatic health check mỗi 10 giây

Applications

     │## Files đã tạo/cập nhật

     ├─── pgpool-1 (port 15432)

     │         │### New Configuration Files

     │         ├─── pg-1 (PRIMARY, weight=0)

     │         ├─── pg-2 (STANDBY, weight=1)1. **`pgpool/pgpool.conf`** - Main configuration

     │         ├─── pg-3 (STANDBY, weight=1)   - 4 backend nodes (pg-1/2/3/4)

     │         └─── pg-4 (STANDBY, weight=1)   - Load balancing enabled with backend weights

     │   - Watchdog configuration for HA

     └─── pgpool-2 (port 15433)   - Health check và streaming replication check

               │

               └─── (same backends)2. **`pgpool/pool_hba.conf`** - Authentication rules

```   - SCRAM-SHA-256 authentication

   - Docker network access (172.0.0.0/8)

### Component Roles

3. **`pgpool/pcp.conf`** - PCP (Pgpool Control Protocol)

**Pgpool-1 (Primary)**:   - Admin user: `admin`

- Port: 15432 (external) → 5432 (internal)   - Password: `adminpass`

- PCP Port: 9898   - MD5 hash: `e8a48653851e28c69d0506508fb27fc5`

- Role: Main load balancer

4. **`pgpool/entrypoint.sh`** - Startup script (updated)

**Pgpool-2 (Backup)**:   - Dynamic watchdog configuration

- Port: 15433 (external) → 5432 (internal)   - Auto-generate `pool_passwd` file

- PCP Port: 9899   - Create pgpool user in PostgreSQL

- Role: Backup for HA   - Test backend connections

   - Start pgpool with proper configuration

**Backend Nodes**:

- pg-1: PRIMARY, backend_id=0, weight=05. **`pgpool/Dockerfile`** - Container image (updated)

- pg-2: STANDBY, backend_id=1, weight=1   - Based on Debian Bookworm

- pg-3: STANDBY, backend_id=2, weight=1   - Installs pgpool2 and PostgreSQL client

- pg-4: STANDBY, backend_id=3, weight=1   - Exposes ports: 5432, 9898, 9000, 9694



## Cài đặt### Updated Files



### Docker Deployment1. **`docker-compose.yml`**

   - ❌ Removed: `proxysql` and `proxysql-2` services

#### 1. Dockerfile   - ✅ Added: `pgpool-1` and `pgpool-2` services

   - ❌ Removed: `proxysql_data` and `proxysql2_data` volumes

```dockerfile

FROM debian:bookworm-slim### Test Files



RUN apt-get update && apt-get install -y \1. **`test-pgpool-routing.js`** - Comprehensive test suite

    pgpool2 \   - Test read/write routing

    postgresql-client-15 \   - Load balancing verification

    curl \   - Watchdog HA testing

    && rm -rf /var/lib/apt/lists/*   - Distribution analysis



COPY pgpool.conf /etc/pgpool2/pgpool.conf## Deployment Steps

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh### 1. Build and Start Services



EXPOSE 5432 9898 9000 9694```bash

cd /root/pg_ha_cluster_production

CMD ["/entrypoint.sh"]

```# Stop old ProxySQL services (if running)

docker-compose stop proxysql proxysql-2

#### 2. Docker Compose Servicedocker-compose rm -f proxysql proxysql-2



```yaml# Build pgpool images

pgpool-1:docker-compose build pgpool-1 pgpool-2

  build: ./pgpool

  container_name: pgpool-1# Start pgpool services

  hostname: pgpool-1docker-compose up -d pgpool-1 pgpool-2

  environment:

    - PGPOOL_NODE_ID=0# Check logs

    - POSTGRES_PASSWORD=postgrespassdocker-compose logs -f pgpool-1

    - REPMGR_PASSWORD=repmgrpassdocker-compose logs -f pgpool-2

    - APP_READWRITE_PASSWORD=appreadwritepass```

    - APP_READONLY_PASSWORD=appreadonlypass

  ports:### 2. Verify Pgpool Status

    - "15432:5432"

    - "9898:9898"```bash

  networks:# Check if pgpool is running

    pg_cluster_network:docker ps | grep pgpool

      ipv4_address: 172.20.0.20

  depends_on:# Check pgpool logs

    - pg-1docker logs pgpool-1

    - pg-2docker logs pgpool-2

    - pg-3

    - pg-4# Verify ports are open

```netstat -tlnp | grep -E '15432|15433|19898|19899'

```

#### 3. Entrypoint Script

### 3. Test Connection

```bash

#!/bin/bash```bash

set -e# Test connection to pgpool-1

PGPASSWORD=readwrite456 psql -h localhost -p 15432 -U app_readwrite -d postgres -c "SELECT version();"

# Tạo pgpool_node_id

echo "${PGPOOL_NODE_ID:-0}" > /var/log/pgpool/pgpool_node_id# Test connection to pgpool-2

PGPASSWORD=readwrite456 psql -h localhost -p 15433 -U app_readwrite -d postgres -c "SELECT version();"

# Generate pool_passwd (plain text format)

cat > /etc/pgpool2/pool_passwd << EOF# Check pgpool backend status

postgres:${POSTGRES_PASSWORD}PGPASSWORD=adminpass pcp_node_info -h localhost -p 19898 -U admin -n 0

repmgr:${REPMGR_PASSWORD}PGPASSWORD=adminpass pcp_node_info -h localhost -p 19898 -U admin -n 1

app_readwrite:${APP_READWRITE_PASSWORD}PGPASSWORD=adminpass pcp_node_info -h localhost -p 19898 -U admin -n 2

app_readonly:${APP_READONLY_PASSWORD}PGPASSWORD=adminpass pcp_node_info -h localhost -p 19898 -U admin -n 3

EOF```



# Set passwords in config### 4. Run Routing Tests

sed -i "s/sr_check_password = ''/sr_check_password = '${REPMGR_PASSWORD}'/" /etc/pgpool2/pgpool.conf

sed -i "s/health_check_password = ''/health_check_password = '${REPMGR_PASSWORD}'/" /etc/pgpool2/pgpool.conf```bash

cd /root/pg_ha_cluster_production

# Start pgpool

exec pgpool -n -f /etc/pgpool2/pgpool.conf -F /etc/pgpool2/pcp.conf# Run pgpool routing test suite

```node test-pgpool-routing.js

```

## Cấu hình

Expected output:

### Core Settings- ✓ Write queries routed to pg-1 (Primary)

- ✓ Read queries distributed to pg-2/3/4 (Standbys)

#### pgpool.conf- ✓ Both pgpool instances operational

- ✓ Load balancing working correctly

**Backend Configuration**:

```conf### 5. Update Application Connection

# Backend 0 - PRIMARY

backend_hostname0 = 'pg-1'Cập nhật application connection strings:

backend_port0 = 5432

backend_weight0 = 0**Before (ProxySQL):**

backend_data_directory0 = '/var/lib/postgresql/data'```

backend_flag0 = 'ALLOW_TO_FAILOVER'host: localhost

port: 15432  # proxysql

# Backend 1 - STANDBYuser: app_readwrite

backend_hostname1 = 'pg-2'password: appreadwritepass

backend_port1 = 5432```

backend_weight1 = 1

backend_data_directory1 = '/var/lib/postgresql/data'**After (Pgpool-II):**

backend_flag1 = 'ALLOW_TO_FAILOVER'```

host: localhost

# Backend 2 - STANDBYport: 15432  # pgpool-1 (or 15433 for pgpool-2)

backend_hostname2 = 'pg-3'user: app_readwrite

backend_port2 = 5432password: readwrite456  # Updated password

backend_weight2 = 1```

backend_data_directory2 = '/var/lib/postgresql/data'

backend_flag2 = 'ALLOW_TO_FAILOVER'## Environment Variables



# Backend 3 - STANDBY### Pgpool-1

backend_hostname3 = 'pg-4'```env

backend_port3 = 5432PGPOOL_NODE_ID=1

backend_weight3 = 1PGPOOL_HOSTNAME=pgpool-1

backend_data_directory3 = '/var/lib/postgresql/data'OTHER_PGPOOL_HOSTNAME=pgpool-2

backend_flag3 = 'ALLOW_TO_FAILOVER'OTHER_PGPOOL_PORT=5432

```POSTGRES_PASSWORD=postgrespass

REPMGR_PASSWORD=repmgrpass

**Clustering Mode**:APP_READONLY_PASSWORD=readonly123

```confAPP_READWRITE_PASSWORD=readwrite456

backend_clustering_mode = 'streaming_replication'```

```

### Pgpool-2

**Load Balancing**:```env

```confPGPOOL_NODE_ID=2

load_balance_mode = onPGPOOL_HOSTNAME=pgpool-2

statement_level_load_balance = onOTHER_PGPOOL_HOSTNAME=pgpool-1

disable_load_balance_on_write = 'transaction'OTHER_PGPOOL_PORT=5432

```POSTGRES_PASSWORD=postgrespass

REPMGR_PASSWORD=repmgrpass

**Streaming Replication Check**:APP_READONLY_PASSWORD=readonly123

```confAPP_READWRITE_PASSWORD=readwrite456

sr_check_period = 5```

sr_check_user = 'repmgr'

sr_check_password = 'repmgrpass'## Port Mapping

sr_check_database = 'postgres'

```| Service   | Container Port | Host Port | Description |

|-----------|----------------|-----------|-------------|

**Health Check**:| pgpool-1  | 5432           | 15432     | PostgreSQL protocol |

```conf| pgpool-1  | 9898           | 19898     | PCP (Control) |

health_check_period = 10| pgpool-1  | 9000           | -         | Watchdog |

health_check_timeout = 20| pgpool-1  | 9694           | -         | Heartbeat |

health_check_user = 'repmgr'| pgpool-2  | 5432           | 15433     | PostgreSQL protocol |

health_check_password = 'repmgrpass'| pgpool-2  | 9898           | 19899     | PCP (Control) |

health_check_database = 'postgres'| pgpool-2  | 9000           | -         | Watchdog |

health_check_max_retries = 3| pgpool-2  | 9694           | -         | Heartbeat |

health_check_retry_delay = 1

```## PCP (Pgpool Control Protocol) Commands



**Connection Settings**:Check backend status:

```conf```bash

listen_addresses = '*'# Show all backends

port = 5432PGPASSWORD=adminpass pcp_node_info -h localhost -p 19898 -U admin -w

socket_dir = '/var/run/pgpool'

pcp_listen_addresses = '*'# Show pgpool processes

pcp_port = 9898PGPASSWORD=adminpass pcp_proc_info -h localhost -p 19898 -U admin -w

```

# Show pool status

**Connection Pooling**:PGPASSWORD=adminpass pcp_pool_status -h localhost -p 19898 -U admin -w

```conf

num_init_children = 32# Show watchdog info

max_pool = 4PGPASSWORD=adminpass pcp_watchdog_info -h localhost -p 19898 -U admin -w

child_life_time = 300```

child_max_connections = 0

connection_life_time = 0## Load Balancing Algorithm

client_idle_limit = 0

```Pgpool-II uses weighted round-robin for load balancing:



**Logging**:- **backend_weight0 = 0** (pg-1): Never receives read queries (writes only)

```conf- **backend_weight1 = 1** (pg-2): 33.3% of read queries

log_destination = 'stderr'- **backend_weight2 = 1** (pg-3): 33.3% of read queries

log_line_prefix = '%t: pid %p: '- **backend_weight3 = 1** (pg-4): 33.4% of read queries

log_connections = on

log_hostname = onRead distribution: **pg-2:pg-3:pg-4 = 1:1:1**

log_statement = off

log_per_node_statement = off## Query Routing Rules

```

### Routed to PRIMARY (pg-1)

## Authentication- `BEGIN`, `START TRANSACTION`, `COMMIT`, `ROLLBACK`

- `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`

### SCRAM-SHA-256 Setup- `CREATE`, `ALTER`, `DROP`

- `SELECT ... FOR UPDATE`

#### 1. PostgreSQL Configuration- `LOCK TABLE`

- Queries inside explicit transactions

```sql

-- Tất cả users phải có SCRAM password### Routed to STANDBYS (pg-2/3/4)

ALTER USER postgres WITH PASSWORD 'postgrespass';- `SELECT` queries (outside transactions)

ALTER USER repmgr WITH PASSWORD 'repmgrpass';- Read-only functions

ALTER USER app_readwrite WITH PASSWORD 'appreadwritepass';- Load balanced based on backend weights

ALTER USER app_readonly WITH PASSWORD 'appreadonlypass';

```## Watchdog Failover



```confIf **pgpool-1** fails:

# postgresql.conf1. Watchdog detects pgpool-1 is down

password_encryption = scram-sha-2562. **pgpool-2** automatically takes over

3. Applications can failover to port **15433**

# pg_hba.conf4. When pgpool-1 recovers, it rejoins the cluster

host all all 0.0.0.0/0 scram-sha-256

```Priority: **pgpool-1 (1) > pgpool-2 (2)** - lower number = higher priority



#### 2. Pgpool pool_passwd## Monitoring



**Format**: Plain text (username:password)### Pgpool Logs

```bash

```bash# Follow logs

# /etc/pgpool2/pool_passwddocker logs -f pgpool-1

postgres:postgrespassdocker logs -f pgpool-2

repmgr:repmgrpass

app_readwrite:appreadwritepass# Check last 100 lines

app_readonly:appreadonlypassdocker logs --tail 100 pgpool-1

``````



**Permissions**:### Health Check

```bash```bash

chmod 600 /etc/pgpool2/pool_passwd# From container

chown postgres:postgres /etc/pgpool2/pool_passwddocker exec pgpool-1 pgpool -f /etc/pgpool-II/pgpool.conf show pool_status

```

# Check if backends are alive

#### 3. Pgpool Configurationdocker exec pgpool-1 pgpool -f /etc/pgpool-II/pgpool.conf show pool_nodes

```

```conf

enable_pool_hba = off## Troubleshooting

allow_clear_text_frontend_auth = on

```### Issue: Cannot connect to pgpool

```bash

### Why Plain Text pool_passwd?# Check if pgpool is running

docker ps | grep pgpool

- Pgpool cần plain password để authenticate với PostgreSQL backend

- File được bảo vệ bởi filesystem permissions (600)# Check logs for errors

- Alternative: pg_enc format (phức tạp hơn, cần AES key)docker logs pgpool-1 | grep -i error



## Read/Write Splitting# Verify PostgreSQL backends are reachable

docker exec pgpool-1 psql -h pg-1 -U repmgr -d postgres -c "SELECT 1"

### Query Routing Rules```



#### Automatic Routing to PRIMARY### Issue: Queries not load balanced

```bash

✅ **Luôn đi PRIMARY**:# Check backend weights

- `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`docker exec pgpool-1 cat /etc/pgpool-II/pgpool.conf | grep backend_weight

- `CREATE`, `ALTER`, `DROP`

- `COPY FROM`# Verify load_balance_mode is ON

- Queries inside transactions (`BEGIN...COMMIT`)docker exec pgpool-1 cat /etc/pgpool-II/pgpool.conf | grep load_balance_mode

- `SELECT ... FOR UPDATE/SHARE````

- Temporary tables

- Functions that modify data### Issue: Watchdog not working

```bash

#### Load-balanced to STANDBYs# Check watchdog status

PGPASSWORD=adminpass pcp_watchdog_info -h localhost -p 19898 -U admin

✅ **Load-balanced**:

- Simple `SELECT` queries# Check heartbeat connectivity

- Read-only functionsdocker exec pgpool-1 ping -c 3 pgpool-2

- `COPY TO`docker exec pgpool-2 ping -c 3 pgpool-1

- Non-DML statements```



### Configuration### Issue: Authentication failed

```bash

```conf# Regenerate pool_passwd

# Statement-level load balancingdocker exec -it pgpool-1 bash

statement_level_load_balance = oncd /etc/pgpool-II

echo "username:md5$(echo -n 'passwordusername' | md5sum | awk '{print $1}')" >> pool_passwd

# Disable load balance khi inside transactionchmod 600 pool_passwd

disable_load_balance_on_write = 'transaction'```



# Backend weights (0 = no reads)## Comparison: ProxySQL vs Pgpool-II

backend_weight0 = 0  # PRIMARY

backend_weight1 = 1  # STANDBY| Feature | ProxySQL (Beta) | Pgpool-II |

backend_weight2 = 1  # STANDBY|---------|----------------|-----------|

backend_weight3 = 1  # STANDBY| PostgreSQL Support | ⚠️ Beta (limited) | ✅ Production-ready |

```| Read/Write Split | ✅ Query rules | ✅ Smart routing |

| Load Balancing | ✅ Manual rules | ✅ Weighted round-robin |

### Testing Routing| FOR UPDATE | ❌ Not supported | ✅ Supported |

| Complex JOINs | ❌ Limited | ✅ Full support |

```javascript| Multi-statement | ❌ Parse errors | ✅ Supported |

const { Pool } = require('pg');| Connection Pool | ✅ Yes | ✅ Yes |

| Failover | Manual | ✅ Automatic (watchdog) |

const pool = new Pool({| Maturity | ⚠️ New/Beta | ✅ 20+ years |

  host: 'localhost',

  port: 15432,## Next Steps

  user: 'app_readwrite',

  password: 'appreadwritepass',1. ✅ Build and deploy pgpool services

  database: 'postgres',2. ✅ Test routing with `test-pgpool-routing.js`

});3. ✅ Verify watchdog HA between pgpool-1 and pgpool-2

4. ⏳ Update application to use new passwords

// Test 1: Standalone INSERT → PRIMARY5. ⏳ Run trading system tests (`trading-simple-test.js`)

const r1 = await pool.query(`6. ⏳ Monitor pgpool performance and metrics

  INSERT INTO test (data) VALUES ('test') 7. ⏳ Set up alerting for pgpool failures

  RETURNING *, inet_server_addr()

`);## References

console.log(r1.rows[0].inet_server_addr); // Should be PRIMARY IP

- Pgpool-II Documentation: https://www.pgpool.net/docs/latest/en/html/

// Test 2: Transaction write → PRIMARY- Load Balancing: https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html

const client = await pool.connect();- Watchdog: https://www.pgpool.net/docs/latest/en/html/tutorial-watchdog.html

try {- PCP Commands: https://www.pgpool.net/docs/latest/en/html/pcp-commands.html

  await client.query('BEGIN');
  const r2 = await client.query('INSERT INTO test (data) VALUES ($1) RETURNING *', ['tx']);
  await client.query('COMMIT');
} finally {
  client.release();
}

// Test 3: Read → STANDBY (load-balanced)
const r3 = await pool.query('SELECT *, inet_server_addr() FROM test');
console.log(r3.rows[0].inet_server_addr); // Should be STANDBY IP
```

## Connection Pooling

### Pool Configuration

```conf
# Number of pre-forked processes
num_init_children = 32

# Max cached connections per child
max_pool = 4

# Child process lifetime
child_life_time = 300
child_max_connections = 0

# Connection lifetime
connection_life_time = 0
client_idle_limit = 0
```

### Pool Calculation

**Total backend connections**:
```
max_connections = num_init_children * max_pool * num_backends
                = 32 * 4 * 4
                = 512 connections
```

**PostgreSQL max_connections should be**:
```
max_connections >= 512 + reserved (10)
                >= 522
```

### Pool Modes

**Session Pooling** (default):
- Connection assigned for entire client session
- Safe for all applications
- Lower concurrency

**Transaction Pooling**:
- Connection returned after transaction
- Higher concurrency
- Can break session-level features (temp tables, prepared statements)

## High Availability

### Auto-detect PRIMARY/STANDBY

**SR Check**:
```conf
sr_check_period = 5
sr_check_user = 'repmgr'
sr_check_password = 'repmgrpass'
```

**Mechanism**:
1. Pgpool executes `SELECT pg_is_in_recovery()` every 5 seconds
2. Returns `false` → PRIMARY (backend_status = up, role = primary)
3. Returns `true` → STANDBY (backend_status = up, role = standby)

### Health Check

```conf
health_check_period = 10
health_check_timeout = 20
health_check_user = 'repmgr'
health_check_max_retries = 3
health_check_retry_delay = 1
```

**Failure Detection**:
1. Pgpool connects to backend every 10 seconds
2. Timeout after 20 seconds
3. Retry 3 times with 1 second delay
4. Mark backend DOWN if all retries fail

### Failover (Future)

**Automatic Failover Configuration**:
```conf
failover_command = '/etc/pgpool2/failover.sh %d %h %p %D %m %H %M %P %r %R %N %S'
follow_primary_command = '/etc/pgpool2/follow_primary.sh %d %h %p %D %m %H %M %P %r %R'
```

**Watchdog (Future)**:
```conf
use_watchdog = on
wd_hostname = 'pgpool-1'
wd_port = 9000

# Pgpool-1
wd_priority = 1

# Pgpool-2
wd_priority = 2
```

## Monitoring

### Show Pool Status

```bash
# Via psql
psql -h localhost -p 15432 -U postgres -c "SHOW POOL_NODES;"

# Expected output:
# node_id | hostname | port | status | pg_status | role    | select_cnt | load_balance_node
# 0       | pg-1     | 5432 | up     | up        | primary | 0          | false
# 1       | pg-2     | 5432 | up     | up        | standby | 150        | true
```

### PCP Commands

```bash
# Show pool status
pcp_node_info -h localhost -p 9898 -U postgres -w

# Show pool processes
pcp_proc_info -h localhost -p 9898 -U postgres -w

# Reload config
pcp_reload_config -h localhost -p 9898 -U postgres -w

# Attach/detach node
pcp_attach_node -h localhost -p 9898 -U postgres -w -n 1
pcp_detach_node -h localhost -p 9898 -U postgres -w -n 1
```

## Troubleshooting

### Issue: Cannot detect PRIMARY

**Symptoms**:
```
WARNING: failed to detect primary node
```

**Diagnosis**:
```bash
# Check sr_check logs
docker logs pgpool-1 | grep sr_check

# Test repmgr user
docker exec pg-1 psql -U repmgr -c "SELECT pg_is_in_recovery();"

# Check backend connectivity
docker exec pgpool-1 psql -h pg-1 -U repmgr -c "SELECT 1"
```

**Solution**:
```bash
# Ensure repmgr user has login privilege
docker exec pg-1 psql -U postgres -c "ALTER USER repmgr WITH LOGIN;"

# Reload pgpool config
docker exec pgpool-1 pcp_reload_config -h localhost -p 9898 -U postgres -w
```

### Issue: Authentication failed

**Symptoms**:
```
ERROR: password authentication failed for user "app_readwrite"
```

**Solution**:
```bash
# Recreate pool_passwd
docker exec pgpool-1 bash -c 'cat > /etc/pgpool2/pool_passwd << EOF
postgres:postgrespass
repmgr:repmgrpass
app_readwrite:appreadwritepass
app_readonly:appreadonlypass
EOF'

# Set permissions
docker exec pgpool-1 chmod 600 /etc/pgpool2/pool_passwd

# Restart pgpool
docker restart pgpool-1
```

### Issue: Queries not load-balanced

**Symptoms**:
- All queries go to PRIMARY
- `select_cnt` on STANDBYs = 0

**Solution**:
```conf
# pgpool.conf
load_balance_mode = on
statement_level_load_balance = on

# Set weights
backend_weight0 = 0  # PRIMARY (no reads)
backend_weight1 = 1  # STANDBY
backend_weight2 = 1  # STANDBY
backend_weight3 = 1  # STANDBY

# Reload
docker exec pgpool-1 pcp_reload_config -h localhost -p 9898 -U postgres -w
```

## Best Practices

### Application Development

✅ **DO**:
- Use transactions for multi-statement operations
- Use `SELECT ... FOR UPDATE` for row locking
- Set `statement_timeout` to prevent long-running queries
- Use connection pooling on application side (e.g., pg.Pool)

❌ **DON'T**:
- Don't rely on session variables across queries
- Don't use temporary tables with load balancing
- Don't assume reads are immediately consistent
- Don't use prepared statements with statement-level load balancing

### Configuration

✅ **DO**:
- Set PRIMARY weight = 0
- Enable `statement_level_load_balance`
- Use `disable_load_balance_on_write = 'transaction'`
- Set appropriate `num_init_children` based on load

❌ **DON'T**:
- Don't use `backend_flag = 'ALWAYS_PRIMARY'` (breaks auto-detect)
- Don't disable health_check
- Don't set `child_life_time` too low (causes connection churn)

## Reference

### Configuration Files

- `/etc/pgpool2/pgpool.conf`: Main configuration
- `/etc/pgpool2/pcp.conf`: PCP user passwords
- `/etc/pgpool2/pool_passwd`: Backend authentication
- `/etc/pgpool2/pool_hba.conf`: Client authentication (if enabled)

### Important Ports

- 5432: Pgpool listening port
- 9898/9899: PCP ports
- 9000: Watchdog port (future)
- 9694: Prometheus exporter (future)

### Useful Commands

```bash
# Show version
pgpool --version

# Test config
pgpool -n -f /etc/pgpool2/pgpool.conf -C

# Reload config (no downtime)
pgpool reload

# Graceful shutdown
pgpool -m fast stop
```

---

**Last Updated**: 2025-10-28
**Pgpool Version**: 4.3.5 (tamahomeboshi)
**PostgreSQL Version**: 17.6
