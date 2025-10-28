# 📊 Dashboard Setup Guide - Có Data Thực

## ⚠️ VẤN ĐỀ HIỆN TẠI

### 1. No Data trong PostgreSQL Dashboards
- **Nguyên nhân**: PostgreSQL cluster chưa được start
- **Hiện tại**: Chỉ có monitoring stack, không có database để monitor

### 2. PostgreSQL Exporter Lỗi Parse Password
- **Lỗi**: `invalid port ":2GuPThHOVaVXTXJ9Dr6ka"`
- **Nguyên nhân**: Password có ký tự `/` gây lỗi URL parsing
- **Password hiện tại**: `2GuPThHOVaVXTXJ9Dr6ka/C1gX64cDiOMqE5EyacyiE=`

---

## ✅ GIẢI PHÁP - 3 BƯỚC

### Bước 1: Fix Password trong `.env`

```bash
cd /root/pg_ha_cluster_production/monitoring

# Generate password không có ký tự đặc biệt
NEW_PG_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

# Update .env file
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${NEW_PG_PASSWORD}/" .env

echo "✅ New password: ${NEW_PG_PASSWORD}"
```

### Bước 2: Start PostgreSQL Cluster

```bash
cd /root/pg_ha_cluster_production

# Option A: Nếu có docker-compose.yml
docker compose up -d

# Option B: Hoặc từ /root/new_pg_cluster_clone
cd /root/new_pg_cluster_clone
docker compose up -d

# Chờ cluster khởi động
sleep 30

# Verify
docker ps --filter "name=pg-"
```

### Bước 3: Kết Nối Monitoring Stack với PostgreSQL Cluster

Có 2 cách:

#### **Cách 1: Same Docker Network (Khuyến nghị)**

```bash
cd /root/pg_ha_cluster_production/monitoring

# Thêm monitoring containers vào pg network
docker network connect new_pg_cluster_clone_default grafana
docker network connect new_pg_cluster_clone_default prometheus
docker network connect new_pg_cluster_clone_default postgres_exporter_pg1
docker network connect new_pg_cluster_clone_default postgres_exporter_pg2
docker network connect new_pg_cluster_clone_default postgres_exporter_pg3
docker network connect new_pg_cluster_clone_default postgres_exporter_pg4

# Restart exporters để reconnect
docker compose restart postgres_exporter_pg1 postgres_exporter_pg2 \
                         postgres_exporter_pg3 postgres_exporter_pg4
```

#### **Cách 2: Update docker-compose.yml (Permanent)**

Edit `/root/pg_ha_cluster_production/monitoring/docker-compose.yml`:

```yaml
networks:
  monitoring:
    driver: bridge
  pg_cluster:
    external: true
    name: new_pg_cluster_clone_default  # Tên network của PG cluster
```

Sau đó:
```bash
docker compose down
docker compose up -d
```

---

## 📈 KẾT QUẢ SAU KHI FIX

### Dashboards sẽ có data:

1. **PostgreSQL Database (ID: 9628)**
   - Query performance
   - Database size
   - Connection stats
   - Replication lag

2. **Node Exporter (ID: 1860)**
   - CPU usage
   - Memory usage
   - Disk I/O
   - Network traffic

3. **cAdvisor (ID: 14282)**
   - Container metrics
   - Resource usage per container

4. **PostgreSQL Query Latency & Tracing** (Custom)
   - Query latency distribution (p50, p95, p99)
   - Slow queries
   - Transaction duration

5. **Tempo Service Map** (Custom)
   - Service dependency graph
   - Request flow
   - Latency heatmap

---

## 🧪 TEST DATA GENERATION

### Generate PostgreSQL Load

```bash
# Tạo test database và load
docker exec -it pg-1 psql -U postgres << 'SQL'
CREATE DATABASE test_db;
\c test_db

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert test data
INSERT INTO users (name, email)
SELECT 
    'User ' || i,
    'user' || i || '@example.com'
FROM generate_series(1, 10000) i;

-- Create index
CREATE INDEX idx_users_email ON users(email);

-- Run queries to generate metrics
SELECT COUNT(*) FROM users;
SELECT * FROM users WHERE email LIKE '%@example.com' LIMIT 100;
SELECT pg_sleep(0.5);  -- Simulate slow query
SQL
```

### Generate Continuous Load

```bash
# Run benchmark
docker exec -it pg-1 bash -c "
pgbench -i -s 10 postgres
pgbench -c 10 -j 2 -t 1000 postgres
"
```

---

## 🔍 VERIFY METRICS

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check if postgres exporters có data
curl -s http://localhost:9187/metrics | grep pg_up

# Check Grafana datasources
curl -s -u admin:5QBgYw9LRxZterRN1d3MRUNvUKnAltaHo9LH5c5F6Uc= \
     http://localhost:3000/api/datasources | jq '.[] | {name, type, url}'
```

---

## 📊 DASHBOARD URLs

```
Grafana:     http://localhost:3000
Username:    admin
Password:    5QBgYw9LRxZterRN1d3MRUNvUKnAltaHo9LH5c5F6Uc=

Dashboards:
1. PostgreSQL Database
   http://localhost:3000/d/000000039

2. Node Exporter
   http://localhost:3000/d/rYdddlPWk

3. cAdvisor
   http://localhost:3000/d/cadvisor

4. PostgreSQL Latency (Custom)
   http://localhost:3000/d/d39902f0-4678-4890-bae4-c056b754ea98

5. Tempo Service Map (Custom)
   http://localhost:3000/d/c8489f64-56d7-4bae-abf7-fa07ecbe0c2b
```

---

## 🎯 QUICK FIX SCRIPT

```bash
#!/bin/bash
cd /root/pg_ha_cluster_production/monitoring

echo "🔧 Fixing monitoring setup..."

# 1. Fix password
NEW_PW=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${NEW_PW}/" .env

# 2. Start PG cluster
cd /root/new_pg_cluster_clone
docker compose up -d
sleep 30

# 3. Connect networks
cd /root/pg_ha_cluster_production/monitoring
for container in grafana prometheus postgres_exporter_pg{1..4}; do
    docker network connect new_pg_cluster_clone_default $container 2>/dev/null
done

# 4. Restart exporters
docker compose restart postgres_exporter_pg1 postgres_exporter_pg2 \
                       postgres_exporter_pg3 postgres_exporter_pg4

echo "✅ Done! Check dashboards in 30 seconds"
echo "🌐 http://localhost:3000"
```

