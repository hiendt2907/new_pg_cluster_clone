# LGTM+ Monitoring Stack - Setup Complete! 🎉

## ✅ What Has Been Created

### Core Stack (LGTM+)
```
✅ Grafana 10.2.3      - Unified visualization platform
✅ Loki 2.9.3          - Log aggregation (30 days retention)
✅ Tempo 2.3.1         - Distributed tracing (48h retention)
✅ Mimir 2.11.0        - Long-term metrics storage (90 days)
✅ Prometheus 2.48.1   - Metrics collection (15 days retention)
✅ Alertmanager 0.26.0 - Alert routing & notification
✅ Promtail 2.9.3      - Log shipper
```

### Exporters
```
✅ postgres_exporter (×4)  - PostgreSQL metrics for pg-1 to pg-4
✅ mysqld_exporter         - ProxySQL metrics
✅ node_exporter           - System metrics (CPU, RAM, Disk)
✅ cAdvisor                - Container metrics
```

### Configuration Files
```
monitoring/
├── docker-compose.yml                          # Main orchestration file
├── .env.example                                # Environment template
├── start.sh                                    # Quick start script ⭐
├── stop.sh                                     # Stop script
├── status.sh                                   # Status checker
├── README.md                                   # Complete documentation
└── config/
    ├── prometheus.yml                          # Prometheus config
    ├── mimir.yaml                              # Mimir config
    ├── loki.yaml                               # Loki config
    ├── tempo.yaml                              # Tempo config
    ├── promtail.yaml                           # Promtail config
    ├── alertmanager.yml                        # Alertmanager config
    ├── postgres-exporter-queries.yaml          # Custom PG metrics
    ├── alerts/
    │   ├── postgresql.yml                      # PostgreSQL alerts (16 rules)
    │   ├── proxysql.yml                        # ProxySQL alerts (8 rules)
    │   └── node.yml                            # System alerts (14 rules)
    └── grafana/
        └── provisioning/
            ├── datasources/datasources.yml     # Auto-configure datasources
            └── dashboards/dashboards.yml       # Dashboard provisioning
```

## 🚀 Quick Start (3 Steps)

### Step 1: Navigate to monitoring directory
```bash
cd /root/pg_ha_cluster_production/monitoring
```

### Step 2: Run quick start script
```bash
./start.sh
```

This will:
- ✅ Generate secure passwords (.env file)
- ✅ Create necessary directories
- ✅ Pull Docker images
- ✅ Start all services
- ✅ Display access URLs and credentials

### Step 3: Access Grafana
```bash
# Open browser to:
http://localhost:3000

# Login with:
# Username: admin
# Password: (shown in start.sh output or check .env file)
```

## 📊 What You Get

### 1. Metrics Collection (Prometheus → Mimir)
- **PostgreSQL**: 50+ metrics per node
  - Connections, transactions, cache hit ratio
  - Replication lag (seconds & bytes)
  - Table bloat, index usage
  - Slow queries, locks, blocking queries
  
- **ProxySQL**: Connection pooling, query routing, backend health
- **System**: CPU, RAM, Disk, Network, I/O
- **Containers**: Per-container resource usage

**Retention**: 
- Prometheus: 15 days (recent/fast queries)
- Mimir: 90 days (long-term storage)

### 2. Log Aggregation (Loki)
- **PostgreSQL logs**: Errors, slow queries, connections, DDL
- **ProxySQL logs**: Query routing, backend errors
- **System logs**: Syslog, auth.log
- **Container logs**: All Docker logs with labels

**Retention**: 30 days

### 3. Distributed Tracing (Tempo)
- Query execution paths
- Service dependencies (via service graphs)
- RED metrics from traces (Rate, Errors, Duration)

**Retention**: 48 hours

### 4. Alerting (Alertmanager)
**38 Pre-configured Alert Rules:**

**Critical (16 alerts):**
- PostgreSQL down
- No replicas connected
- Max connections reached
- Replication lag >60s
- Disk >95% full
- ProxySQL down
- No backend servers
- Node down

**Warning (22 alerts):**
- High connection usage (>80%)
- Replication lag >10s
- Slow queries (>30s)
- Cache hit ratio <80%
- High deadlock rate
- Table bloat
- High CPU/memory (>80%)
- Disk >80% full

**Notification Channels:**
- Email (SMTP)
- Slack
- PagerDuty (optional)
- Webhook

## 🎯 Use Cases

### 1. Cluster Health Monitoring
```
Grafana Dashboard → PostgreSQL Overview
- See all 4 nodes + witness status
- Replication topology
- Primary/standby roles
- Current connections (per node)
```

### 2. Performance Troubleshooting
```
Grafana → PostgreSQL Performance Dashboard
- Top 20 slow queries
- Lock contention
- Cache miss ratio
- Index usage
- Query latency (P50, P95, P99)
```

### 3. Incident Investigation
```
Grafana → Explore (Loki)
{job="postgresql", instance="pg-2"} |= "ERROR" |= "replication"
→ Shows all replication errors on pg-2
```

### 4. Capacity Planning
```
Prometheus Query:
predict_linear(pg_database_size_bytes[1h], 24*3600)
→ Predicts DB size 24h from now
```

### 5. Alerting Setup
```
Alertmanager → Silence
- Silence alerts during maintenance
- Route critical alerts to PagerDuty
- Send warnings to Slack #db-alerts
```

## 📈 Recommended Dashboards to Import

### 1. PostgreSQL Database (ID: 9628)
```
Grafana → Dashboards → Import → ID: 9628
```
- Most popular PostgreSQL dashboard
- 25K+ downloads
- Pre-configured panels

### 2. Node Exporter Full (ID: 1860)
```
Grafana → Dashboards → Import → ID: 1860
```
- Complete system metrics
- CPU, RAM, Disk, Network
- 1M+ downloads

### 3. ProxySQL Dashboard (ID: 12859)
```
Grafana → Dashboards → Import → ID: 12859
```
- Connection pool metrics
- Query routing stats
- Backend health

### 4. Loki Logs Dashboard (ID: 13639)
```
Grafana → Dashboards → Import → ID: 13639
```
- Log volume over time
- Error rate trends
- Top log sources

## 🔧 Configuration Examples

### Connect to Existing PostgreSQL Cluster

Edit `docker-compose.yml`:
```yaml
networks:
  pg_cluster:
    external: true  # Change from 'driver: bridge'
```

### Change Retention Periods

**Prometheus (shorter retention = less disk)**:
```yaml
# docker-compose.yml
prometheus:
  command:
    - '--storage.tsdb.retention.time=7d'  # Default: 15d
    - '--storage.tsdb.retention.size=2GB' # Default: 5GB
```

**Loki (longer retention for compliance)**:
```yaml
# config/loki.yaml
limits_config:
  retention_period: 90d  # Default: 30d
```

**Mimir (adjust for storage)**:
```yaml
# config/mimir.yaml
blocks_storage:
  tsdb:
    retention_period: 180d  # Default: 90d
```

### Add Email Alerts

Edit `.env`:
```bash
SMTP_HOST=smtp.gmail.com:587
SMTP_FROM=alerts@yourcompany.com
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password  # Generate at https://myaccount.google.com/apppasswords
```

Edit `config/alertmanager.yml`:
```yaml
receivers:
  - name: 'critical'
    email_configs:
      - to: 'dba-team@company.com,oncall@company.com'
```

Reload Alertmanager:
```bash
docker-compose restart alertmanager
```

### Add Slack Alerts

1. Create Slack Incoming Webhook at https://api.slack.com/messaging/webhooks
2. Edit `.env`:
```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
```

3. Edit `config/alertmanager.yml`:
```yaml
receivers:
  - name: 'critical'
    slack_configs:
      - channel: '#alerts-critical'
        webhook_url: '${SLACK_WEBHOOK_URL}'
        title: '🚨 {{ .GroupLabels.alertname }}'
```

## 🛠️ Common Tasks

### Check Service Status
```bash
./status.sh
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f grafana
docker-compose logs -f prometheus

# Last 100 lines
docker-compose logs --tail=100 postgres_exporter_pg1
```

### Restart Service
```bash
docker-compose restart prometheus
docker-compose restart grafana
```

### Access Service Shell
```bash
# Grafana container
docker exec -it grafana sh

# Prometheus container
docker exec -it prometheus sh

# Run PromQL query from CLI
docker exec prometheus promtool query instant \
  http://localhost:9090 'up{job="postgresql"}'
```

### Backup Grafana Dashboards
```bash
# Export all dashboards
docker exec grafana grafana-cli admin export-dashboards \
  /tmp/dashboards

docker cp grafana:/tmp/dashboards ./backups/
```

### Reset Grafana Password
```bash
docker exec -it grafana grafana-cli admin reset-admin-password NEW_PASSWORD
```

## 📊 Key Metrics to Watch

### PostgreSQL Health
```promql
# All nodes up?
pg_up == 1

# Replication lag OK?
pg_replication_lag < 10

# Connections not saturated?
sum(pg_stat_activity_count) / sum(pg_settings_max_connections) < 0.8

# Cache hit ratio good?
pg_cache_hit_ratio > 0.95
```

### ProxySQL Health
```promql
# ProxySQL up?
up{job="proxysql"} == 1

# Backend servers online?
mysql_global_status_proxysql_backend_servers_online > 0

# Connection pool not saturated?
mysql_global_status_client_connections_connected < 24000
```

### System Health
```promql
# CPU OK?
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) < 80

# Memory OK?
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 < 80

# Disk OK?
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 < 80
```

## 🔒 Security Checklist

- [ ] Change default Grafana password (done automatically by start.sh)
- [ ] Update SMTP credentials in .env
- [ ] Update Slack webhook URL in .env
- [ ] Don't expose ports publicly (use reverse proxy with SSL)
- [ ] Enable Grafana HTTPS (via Nginx/Caddy)
- [ ] Restrict Prometheus/Alertmanager access (firewall or auth)
- [ ] Rotate credentials periodically
- [ ] Review alert rules for your environment

## 🆘 Troubleshooting

### Issue: Prometheus targets down
```bash
# Check network connectivity
docker exec prometheus wget -O- http://postgres_exporter_pg1:9187/metrics

# Check exporter logs
docker-compose logs postgres_exporter_pg1

# Verify database credentials
docker exec postgres_exporter_pg1 env | grep DATA_SOURCE_NAME
```

### Issue: No data in Grafana
```bash
# Test Prometheus datasource
curl http://localhost:9090/api/v1/query?query=up

# Check Grafana datasources
curl -u admin:PASSWORD http://localhost:3000/api/datasources

# Verify time range in Grafana (top-right corner)
```

### Issue: Loki queries slow
```bash
# Check Loki index size
docker exec loki du -sh /loki/index

# Reduce retention or add more resources
# Edit config/loki.yaml → retention_period: 7d
docker-compose restart loki
```

### Issue: High disk usage
```bash
# Check volume sizes
docker system df -v

# Prune old data
docker volume prune  # ⚠️ CAREFUL - deletes unused volumes

# Reduce retention periods (see Configuration Examples above)
```

## 📚 Next Steps

1. **Import Dashboards** (see Recommended Dashboards section)
2. **Configure Alerts** (edit config/alertmanager.yml)
3. **Test Alerts** (see README.md → Test Alerts)
4. **Set Up SSL** (Nginx reverse proxy for Grafana)
5. **Add Custom Metrics** (edit config/postgres-exporter-queries.yaml)
6. **Create Custom Dashboards** (Grafana → Create → Dashboard)
7. **Set Up Log Rotation** (configure Docker log driver)
8. **Schedule Backups** (Grafana dashboards, Prometheus snapshots)

## 🎓 Learning Resources

- **Grafana Fundamentals**: https://grafana.com/tutorials/grafana-fundamentals/
- **PromQL Tutorial**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **LogQL Guide**: https://grafana.com/docs/loki/latest/logql/
- **TraceQL Reference**: https://grafana.com/docs/tempo/latest/traceql/
- **PostgreSQL Monitoring**: https://www.postgresql.org/docs/current/monitoring.html

## 🤝 Support

- **Documentation**: `./README.md`
- **Status Check**: `./status.sh`
- **Logs**: `docker-compose logs -f [service]`
- **GitHub Issues**: (create issue in repository)
- **Community**: Grafana Community Forums

---

**🎉 You're all set! Happy monitoring! 📊**

**Quick Commands:**
```bash
./start.sh    # Start monitoring stack
./status.sh   # Check service status
./stop.sh     # Stop all services
```

**Access Grafana:**
```bash
http://localhost:3000
Username: admin
Password: (check .env file)
```
