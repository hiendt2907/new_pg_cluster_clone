# Client Connection Examples - ProxySQL HA

> **🔒 SECURITY NOTE**
> - **All passwords shown as `YOUR_SECURE_PASSWORD` are PLACEHOLDERS only**
> - **Real passwords are auto-generated (32-character random) and stored in Railway environment variables**
> - **Replace `YOUR_SECURE_PASSWORD` with actual password from `railway variables --service proxysql`**
> - **Never commit real passwords to Git**

## PostgreSQL Multi-Host Connection String (Recommended)

### Python (psycopg2/psycopg3)
```python
import psycopg2

# Multi-host connection với automatic failover
conn = psycopg2.connect(
    host="proxysql-production.railway.app,proxysql-2-production.railway.app",
    port=5432,
    database="postgres",
    user="postgres",
    password="YOUR_SECURE_PASSWORD",
    target_session_attrs="read-write",  # Auto-select writable host
    connect_timeout=3,
    options="-c statement_timeout=5000"  # 5s timeout for trading
)

# Connection pooling cho trading (high performance)
from psycopg2 import pool

connection_pool = pool.ThreadedConnectionPool(
    minconn=100,
    maxconn=5000,
    host="proxysql-production.railway.app,proxysql-2-production.railway.app",
    port=5432,
    database="postgres",
    user="postgres",
    password="YOUR_SECURE_PASSWORD",
    target_session_attrs="any",  # Accept any host (both ProxySQL handle routing)
    connect_timeout=2
)
```

### Node.js (node-postgres / pg)
```javascript
const { Pool } = require('pg');

// Multi-host connection pool
const pool = new Pool({
  host: 'proxysql-production.railway.app,proxysql-2-production.railway.app',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: 'YOUR_SECURE_PASSWORD',
  max: 5000,                    // Match ProxySQL max_connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
  statement_timeout: 5000       // 5s for trading queries
});

// Alternative: Multiple pools with manual failover
const pool1 = new Pool({
  host: 'proxysql-production.railway.app',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: 'YOUR_SECURE_PASSWORD',
  max: 2500
});

const pool2 = new Pool({
  host: 'proxysql-2-production.railway.app',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: 'YOUR_SECURE_PASSWORD',
  max: 2500
});

// Round-robin or failover logic
let currentPool = pool1;

async function query(sql, params) {
  try {
    return await currentPool.query(sql, params);
  } catch (err) {
    console.error('Primary pool failed, switching to backup:', err.message);
    currentPool = (currentPool === pool1) ? pool2 : pool1;
    return await currentPool.query(sql, params);
  }
}
```

### Go (lib/pq or pgx)
```go
package main

import (
    "context"
    "fmt"
    "github.com/jackc/pgx/v5/pgxpool"
)

func main() {
    // Multi-host connection string
    connString := "postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?pool_max_conns=5000&pool_min_conns=100&pool_max_conn_lifetime=1h&target_session_attrs=any"

    pool, err := pgxpool.New(context.Background(), connString)
    if err != nil {
        panic(err)
    }
    defer pool.Close()

    // Test connection
    var result int
    err = pool.QueryRow(context.Background(), "SELECT 1").Scan(&result)
    if err != nil {
        panic(err)
    }
    fmt.Println("Connected successfully:", result)
}
```

### Java (JDBC)
```java
import java.sql.*;
import org.postgresql.ds.PGPoolingDataSource;

public class TradingDBConnection {
    public static void main(String[] args) {
        String jdbcUrl = "jdbc:postgresql://proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres" +
                         "?user=postgres" +
                         "&password=YOUR_SECURE_PASSWORD" +
                         "&targetServerType=any" +  // Accept any host
                         "&connectTimeout=2" +
                         "&socketTimeout=5" +
                         "&tcpKeepAlive=true";

        try (Connection conn = DriverManager.getConnection(jdbcUrl)) {
            System.out.println("Connected to: " + conn.getMetaData().getURL());
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}

// With HikariCP connection pool
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:postgresql://proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres");
config.setUsername("postgres");
config.setPassword("YOUR_SECURE_PASSWORD");
config.setMaximumPoolSize(5000);
config.setMinimumIdle(100);
config.setConnectionTimeout(2000);
config.setIdleTimeout(300000);
config.addDataSourceProperty("targetServerType", "any");

HikariDataSource dataSource = new HikariDataSource(config);
```

### Ruby (pg gem)
```ruby
require 'pg'

# Multi-host connection
conn = PG.connect(
  host: 'proxysql-production.railway.app,proxysql-2-production.railway.app',
  port: 5432,
  dbname: 'postgres',
  user: 'postgres',
  password: 'YOUR_SECURE_PASSWORD',
  connect_timeout: 2,
  target_session_attrs: 'any'
)

# Connection pool (with connection_pool gem)
require 'connection_pool'

DB_POOL = ConnectionPool.new(size: 100, timeout: 5) do
  PG.connect(
    host: 'proxysql-production.railway.app,proxysql-2-production.railway.app',
    port: 5432,
    dbname: 'postgres',
    user: 'postgres',
    password: 'YOUR_SECURE_PASSWORD'
  )
end

DB_POOL.with { |conn| conn.exec('SELECT NOW()') }
```

### C# (.NET - Npgsql)
```csharp
using Npgsql;

// Multi-host connection string
var connString = "Host=proxysql-production.railway.app,proxysql-2-production.railway.app;" +
                 "Port=5432;" +
                 "Database=postgres;" +
                 "Username=postgres;" +
                 "Password=YOUR_SECURE_PASSWORD;" +
                 "Target Session Attributes=any;" +
                 "Timeout=2;" +
                 "Command Timeout=5;" +
                 "MaxPoolSize=5000;" +
                 "MinPoolSize=100;";

using var conn = new NpgsqlConnection(connString);
conn.Open();
Console.WriteLine($"Connected to: {conn.Host}");
```

## 🔧 Connection String Format

### Standard Format
```bash
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?target_session_attrs=any
```

### Parameters Explained
- `host1:port1,host2:port2` - Multiple hosts, driver tries in order
- `target_session_attrs=any` - Accept any available host (both ProxySQL are identical)
- `target_session_attrs=read-write` - Only writable hosts (for primary-only apps)
- `connect_timeout=2` - Fast failover (2 seconds)
- `statement_timeout=5000` - Query timeout for trading (5s)

## 📊 Load Distribution Strategy

### Strategy 1: Client-Side Round Robin
```python
import random
from psycopg2 import pool

# Create 2 separate pools
pools = [
    pool.ThreadedConnectionPool(
        minconn=50, maxconn=2500,
        host="proxysql-production.railway.app",
        port=5432, database="postgres",
        user="postgres", password="YOUR_SECURE_PASSWORD"
    ),
    pool.ThreadedConnectionPool(
        minconn=50, maxconn=2500,
        host="proxysql-2-production.railway.app",
        port=5432, database="postgres",
        user="postgres", password="YOUR_SECURE_PASSWORD"
    )
]

def get_connection():
    """Round-robin between 2 ProxySQL instances"""
    selected_pool = random.choice(pools)
    try:
        return selected_pool.getconn()
    except Exception as e:
        # Failover to other pool
        other_pool = pools[1] if selected_pool == pools[0] else pools[0]
        print(f"Failover to backup pool: {e}")
        return other_pool.getconn()
```

### Strategy 2: Weighted Distribution
```python
# 70% to proxysql, 30% to proxysql-2
def get_weighted_connection():
    if random.random() < 0.7:
        return pools[0].getconn()  # proxysql (primary)
    else:
        return pools[1].getconn()  # proxysql-2 (backup)
```

## 🚀 Production Deployment After Railway Setup

### Step 1: Get Railway Public URLs
```bash
# Deploy ProxySQL services first
./railway-deploy.sh  # Choose option 2

# Get public URLs
railway service proxysql
railway domain
# Copy: proxysql-production-abc123.up.railway.app

railway service proxysql-2
railway domain
# Copy: proxysql-2-production-def456.up.railway.app
```

### Step 2: Update Client Connection String
```bash
# Replace with your actual Railway domains
export DB_HOSTS="proxysql-production-abc123.up.railway.app,proxysql-2-production-def456.up.railway.app"
export DB_PORT="5432"
export DB_NAME="postgres"
export DB_USER="postgres"
export DB_PASS="YOUR_SECURE_PASSWORD"

# Full connection string
export DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOSTS}:${DB_PORT}/${DB_NAME}?target_session_attrs=any&connect_timeout=2"
```

### Step 3: Test Failover
```bash
# Terminal 1: Connect via multi-host
PGPASSWORD=YOUR_SECURE_PASSWORD psql "postgresql://postgres@proxysql-production.railway.app:5432,proxysql-2-production.railway.app:5432/postgres?target_session_attrs=any"

# Terminal 2: Stop proxysql service
railway service proxysql
railway down

# Terminal 1: Connection should auto-reconnect to proxysql-2
SELECT pg_backend_pid(), inet_server_addr();
```

## ⚡ Performance Tips for Trading

1. **Connection Pooling**: Always use connection pools (min 100, max 2500 per ProxySQL)
2. **Statement Timeout**: Set to 5s for trading queries
3. **TCP KeepAlive**: Enable to detect dead connections faster
4. **Load Distribution**: 50/50 between both ProxySQL for maximum throughput
5. **Health Checks**: Periodic `SELECT 1` every 30s to detect failures early

## 📈 Monitoring

```bash
# Check which ProxySQL is handling connections
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql-production.railway.app -p 6132 -U admin -d proxysql -c \
  "SELECT hostgroup_id, srv_host, status, ConnUsed, Queries FROM stats_pgsql_connection_pool ORDER BY Queries DESC;"

PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql-2-production.railway.app -p 6132 -U admin -d proxysql -c \
  "SELECT hostgroup_id, srv_host, status, ConnUsed, Queries FROM stats_pgsql_connection_pool ORDER BY Queries DESC;"
```

## ✅ Verification Checklist

- [ ] Both ProxySQL services deployed and running
- [ ] Public domains generated for both services
- [ ] Port 5432 exposed on both services
- [ ] Client connection string includes both hosts
- [ ] Connection pooling configured (max 2500 per ProxySQL)
- [ ] Failover tested (stop one ProxySQL, client auto-reconnects)
- [ ] Load distributed evenly (check ConnUsed on both ProxySQL)
