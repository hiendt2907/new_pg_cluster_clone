# PostgreSQL High Availability Cluster with Pgpool-II

Production-ready PostgreSQL 17.6 HA cluster with streaming replication, automatic failover, and read/write splitting using **Pgpool-II**.

**Perfect for**: Development, Demo, Docker/Docker Swarm, Kubernetes deployments

---

## 🚀 Quick Start

```bash
# 1. Generate secure passwords
./scripts/generate-passwords.sh

# 2. Start cluster
docker-compose up -d

# 3. View credentials
./scripts/show-credentials.sh
```

**Read the full guide**: [QUICK_START.md](QUICK_START.md) or [START_HERE.md](START_HERE.md)

---

## 🎯 Features

- ✅ **4 PostgreSQL nodes** (1 PRIMARY + 3 STANDBYs + 1 Witness)
- ✅ **2 Pgpool-II instances** for HA and load balancing  
- ✅ **Auto-detect PRIMARY/STANDBY** via sr_check
- ✅ **Read/Write splitting** (DML→PRIMARY, SELECT→STANDBYs)
- ✅ **Connection pooling** (512 connections capacity)
- ✅ **SCRAM-SHA-256 authentication**
- ✅ **Monitoring stack** (Grafana, Prometheus, Loki, Tempo)
- ✅ **Automatic failover** (repmgr)

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [QUICK_START.md](QUICK_START.md) | 5-minute deployment guide |
| [docs/PGPOOL_DEPLOYMENT.md](docs/PGPOOL_DEPLOYMENT.md) | Pgpool-II detailed configuration |
| [docs/SCALING_GUIDE.md](docs/SCALING_GUIDE.md) | Add/remove nodes |
| [docs/SECURITY.md](docs/SECURITY.md) | Security best practices |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Docker/Swarm/K8s deployment |
| [.env-explanation.md](.env-explanation.md) | Why certain configs are where they are |

---

## 🔐 Credentials & Security

All passwords are **auto-generated** when you run:
```bash
./scripts/generate-passwords.sh
```

- ✅ **24-character random passwords**
- ✅ **Secure for production**
- ✅ **Stored in .env** (in .gitignore)
- ✅ **Never committed to Git**

To view your credentials:
```bash
./scripts/show-credentials.sh
```

This displays:
- All user passwords
- Connection strings for Node.js, Python, psql
- Monitoring URLs
- Quick commands

---

## 📊 Endpoints

After running `show-credentials.sh`, connect to:

- **Pgpool-1**: `localhost:15432`
- **Pgpool-2**: `localhost:15433` (backup)
- **Grafana**: `http://localhost:3001` (admin/admin - **change on first login!**)
- **Prometheus**: `http://localhost:9090`

---

## 💻 Usage Example

```javascript
const { Pool } = require('pg');

// Get password from .env or show-credentials.sh
const pool = new Pool({
  host: 'localhost',
  port: 15432,
  user: 'app_readwrite',
  password: process.env.APP_READWRITE_PASSWORD,  // From .env
  database: 'postgres',
});

// Writes → PRIMARY
await pool.query('INSERT INTO orders VALUES ($1, $2)', [1, 100]);

// Reads → STANDBYs (load-balanced)
await pool.query('SELECT * FROM orders');
```

**Tip:** Run `./scripts/show-credentials.sh` for copy-paste ready connection examples!

---

## 🛠️ Common Commands

```bash
# View cluster status
docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# View pgpool status
docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c "SHOW POOL_NODES;"

# View logs
docker-compose logs -f pgpool-1

# Restart
docker-compose restart
```

---

## 🧪 Run Tests

```bash
cd test-app
npm install

# Update test files with passwords from .env first
node test-simple.js           # Simple cluster test (recommended)
node test-insert-routing.js   # Verify INSERT → PRIMARY routing
```

See [test-app/README.md](test-app/README.md) for details.

---

## 📈 Architecture

```
Applications
     │
     ├─── Pgpool-1 (:15432) ──┐
     │                        ├─── pg-1 (PRIMARY, weight=0)
     └─── Pgpool-2 (:15433) ──┤
                              ├─── pg-2 (STANDBY, weight=1)
                              ├─── pg-3 (STANDBY, weight=1)
                              └─── pg-4 (STANDBY, weight=1)
```

---

## 🚀 Deploy Options

### Docker Compose (Dev/Demo)
```bash
./scripts/generate-passwords.sh  # First time only
docker-compose up -d
```

### Docker Swarm (Production)
```bash
./scripts/generate-passwords.sh  # First time only
docker stack deploy -c docker-compose.yml pgcluster
```

### Kubernetes
See k8s manifests in future releases.

---

## 🔗 Links

- [PostgreSQL 17](https://www.postgresql.org/docs/17/)
- [Pgpool-II](https://www.pgpool.net/docs/latest/en/html/)
- [Repmgr](https://repmgr.org/docs/current/)

---

**Status**: ✅ Production Ready  
**Version**: 2.0.0  
**PostgreSQL**: 17.6  
**Pgpool-II**: 4.3.5
