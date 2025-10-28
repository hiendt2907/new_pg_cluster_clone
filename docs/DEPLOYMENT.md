# PostgreSQL HA Cluster - Deployment Guide

Quick deployment guide for PostgreSQL 17.6 HA Cluster with Pgpool-II.

---

## 🎯 Target Platforms

- ✅ **Docker Compose** - Development, Testing, Demo
- ✅ **Docker Swarm** - Production (Single/Multi-host)
- 🔜 **Kubernetes** - Enterprise (Coming soon)

---

## 🚀 Docker Compose Deployment

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- 4GB+ RAM
- 20GB+ disk space

### Quick Start

```bash
# Clone repository
git clone <repository-url>
cd pg_ha_cluster_production

# Start cluster
docker-compose up -d

# Wait for initialization
sleep 60

# Verify
docker-compose ps
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"
```

### Verify Cluster

```bash
# Expected output from SHOW POOL_NODES:
# node_id | hostname | status | role    
#---------|----------|--------|--------
# 0       | pg-1     | up     | primary 
# 1       | pg-2     | up     | standby 
# 2       | pg-3     | up     | standby 
# 3       | pg-4     | up     | standby 
```

### Access Services

```bash
# PostgreSQL via Pgpool-1
psql -h localhost -p 15432 -U app_readwrite -d postgres

# Grafana
open http://localhost:3001
# Username: admin, Password: admin

# Prometheus
open http://localhost:9090
```

---

## 🐳 Docker Swarm Deployment

### Initialize Swarm

```bash
# On manager node
docker swarm init

# Get join token for workers
docker swarm join-token worker
```

### Deploy Stack

```bash
# Deploy cluster
docker stack deploy -c docker-compose.yml pgcluster

# Verify services
docker stack services pgcluster

# View logs
docker service logs pgcluster_pgpool-1
```

### Scale Services

```bash
# Scale pgpool instances
docker service scale pgcluster_pgpool-1=3

# Note: PostgreSQL nodes should NOT be scaled via docker service scale
# Use manual repmgr registration instead
```

### Update Services

```bash
# Update image
docker service update --image postgres:17.6 pgcluster_pg-1

# Update env variable
docker service update --env-add NEW_VAR=value pgcluster_pgpool-1
```

### Remove Stack

```bash
docker stack rm pgcluster
```

---

## ☸️ Kubernetes Deployment (Coming Soon)

### Planned Components

- **StatefulSets** for PostgreSQL nodes
- **Deployment** for Pgpool-II
- **Services** for load balancing
- **PersistentVolumeClaims** for data
- **ConfigMaps** for configuration
- **Secrets** for passwords

### Example (Preview)

```yaml
# postgres-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 4
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:17.6
        # ... configuration ...
```

---

## 🔧 Configuration

### Environment Variables

Default passwords (⚠️ **CHANGE IN PRODUCTION**):

```bash
POSTGRES_PASSWORD=postgrespass
REPMGR_PASSWORD=repmgrpass
APP_READWRITE_PASSWORD=appreadwritepass
APP_READONLY_PASSWORD=appreadonlypass
```

### Modify Configuration

#### Change Passwords

Edit `docker-compose.yml`:

```yaml
environment:
  - POSTGRES_PASSWORD=<your-secure-password>
  - REPMGR_PASSWORD=<your-secure-password>
  # ... other passwords ...
```

#### Adjust Resources

```yaml
services:
  pg-1:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

#### Customize Pgpool

Edit `pgpool/pgpool.conf`:

```conf
# Increase connection pool
num_init_children = 64
max_pool = 8

# Adjust timeouts
health_check_timeout = 30
```

---

## 📊 Monitoring

### Access Grafana

```bash
# URL: http://localhost:3001
# Username: admin
# Password: admin
```

### Pre-configured Dashboards

- PostgreSQL Overview
- Replication Status
- Pgpool Metrics
- Infrastructure Metrics

### Custom Alerts

Edit `monitoring/config/alertmanager.yml`:

```yaml
receivers:
  - name: 'email'
    email_configs:
      - to: 'your-email@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
```

---

## 🔒 Security Hardening

### Production Checklist

1. **Change default passwords**
   ```bash
   # Generate strong passwords
   openssl rand -base64 32
   ```

2. **Enable SSL/TLS**
   - Generate certificates
   - Configure `postgresql.conf`
   - Update `pgpool.conf`

3. **Firewall rules**
   ```bash
   # Allow only necessary ports
   ufw allow 15432/tcp  # Pgpool
   ufw allow 3001/tcp   # Grafana
   ```

4. **Network isolation**
   - Use Docker networks
   - Restrict external access
   - VPN for admin access

5. **Audit logging**
   ```conf
   # postgresql.conf
   log_statement = 'all'
   log_connections = on
   log_disconnections = on
   ```

---

## 🧪 Testing

### Run Test Suite

```bash
cd test-app
npm install

# Test 1: Verify routing
node test-insert-routing.js

# Test 2: Full trading system
node test-trading-pgpool.js
```

### Expected Results

```
Test 1: ✅ Standalone INSERT → PRIMARY (172.20.0.7)
Test 2: ✅ 6/6 tests passed
  - Read queries → STANDBY
  - Write queries → PRIMARY
  - Transactions → PRIMARY
```

---

## 🐛 Troubleshooting

### Services Not Starting

```bash
# Check logs
docker-compose logs pg-1
docker-compose logs pgpool-1

# Check resource usage
docker stats

# Restart services
docker-compose restart
```

### Connection Refused

```bash
# Check if ports are exposed
docker-compose ps

# Verify network
docker network inspect pg_ha_cluster_production_pg_cluster_network

# Test connection
psql -h localhost -p 15432 -U postgres -c "SELECT 1"
```

### Replication Not Working

```bash
# On PRIMARY
docker exec pg-1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# On STANDBY
docker exec pg-2 psql -U postgres -c "SELECT pg_is_in_recovery();"

# Check repmgr
docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

---

## 📈 Performance Tuning

### PostgreSQL

```conf
# postgresql.conf
shared_buffers = 2GB              # 25% of RAM
effective_cache_size = 6GB        # 75% of RAM
maintenance_work_mem = 512MB
max_connections = 600
work_mem = 16MB
```

### Pgpool

```conf
# pgpool.conf
num_init_children = 64            # Based on load
max_pool = 8                      # Connections per child
child_life_time = 300             # Child process lifetime
```

---

## 🔄 Backup & Recovery

### Backup

```bash
# Backup PRIMARY database
docker exec pg-1 pg_dump -U postgres postgres > backup.sql

# Backup with compression
docker exec pg-1 pg_dump -U postgres postgres | gzip > backup.sql.gz

# Physical backup
docker exec pg-1 pg_basebackup -h localhost -U repmgr -D /backup -Fp -Xs -P
```

### Restore

```bash
# Restore from SQL dump
cat backup.sql | docker exec -i pg-1 psql -U postgres postgres

# From compressed
gunzip -c backup.sql.gz | docker exec -i pg-1 psql -U postgres postgres
```

---

## 🚦 Production Deployment Steps

### 1. Preparation

- [ ] Review security checklist
- [ ] Generate strong passwords
- [ ] Prepare SSL certificates (if needed)
- [ ] Plan network topology
- [ ] Set up monitoring alerts

### 2. Deployment

```bash
# Clone repository
git clone <repository-url>
cd pg_ha_cluster_production

# Update passwords in docker-compose.yml
vim docker-compose.yml

# Deploy
docker-compose up -d

# Verify
docker-compose ps
```

### 3. Post-Deployment

- [ ] Run test suite
- [ ] Verify replication
- [ ] Check monitoring dashboards
- [ ] Test failover
- [ ] Document connection strings
- [ ] Set up backup schedule

### 4. Handover

- [ ] Document custom configurations
- [ ] Share credentials securely
- [ ] Provide runbook
- [ ] Train operations team

---

## 📚 Additional Resources

- [QUICK_START.md](QUICK_START.md) - Quick start guide
- [PGPOOL_DEPLOYMENT.md](PGPOOL_DEPLOYMENT.md) - Pgpool configuration
- [SCALING_GUIDE.md](SCALING_GUIDE.md) - Scaling operations
- [SECURITY.md](SECURITY.md) - Security best practices

---

**Last Updated**: 2025-10-28  
**Version**: 2.0.0  
**Status**: Production Ready
