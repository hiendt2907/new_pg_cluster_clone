# PostgreSQL HA Cluster - Railway Deployment

## Cấu trúc Project

```
new_pg_cluster_clone/
├── pg-1/           # Primary PostgreSQL node
├── pg-2/           # Standby PostgreSQL node
├── pg-3/           # Standby PostgreSQL node
├── pg-4/           # Standby PostgreSQL node
├── witness/        # Witness node (cho quorum)
├── shared/         # Shared files (backup)
└── railway-deploy.sh  # Script tự động deploy
```

## Yêu cầu

- Railway Pro Plan (để chạy 5 services + volumes)
- Railway CLI đã cài đặt và login:
  ```bash
  curl -fsSL https://railway.app/install.sh | sh
  railway login
  ```

## Cách sử dụng

### 1. Clone và link project

```bash
git clone https://github.com/hiendt2907/new_pg_cluster_clone.git
cd new_pg_cluster_clone
railway link
```

### 2. Deploy tự động tất cả services

```bash
./railway-deploy.sh
```

Script sẽ:
1. Tạo 5 services (pg-1, pg-2, pg-3, pg-4, witness)
2. Set environment variables từ file `.env` của mỗi service
3. Tạo volumes cho pg-1..pg-4 (mount tại `/var/lib/postgresql`)
4. Deploy theo đúng thứ tự: pg-1 → witness → (pg-2, pg-3, pg-4)

### 3. Kiểm tra deployment

```bash
# Xem status
railway status

# Xem logs của pg-1
railway logs --service pg-1 --follow

# SSH vào pg-1 để check cluster
railway ssh --service pg-1

# Trong container, check cluster health
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

Kết quả mong đợi:
```
 ID | Name    | Role    | Status    | Upstream | Location | Priority | Timeline
----+---------+---------+-----------+----------+----------+----------+----------
 1  | pg-1    | primary | * running |          | default  | 199      | 1
 2  | pg-2    | standby |   running | pg-1     | default  | 198      | 1
 3  | pg-3    | standby |   running | pg-1     | default  | 197      | 1
 4  | pg-4    | standby |   running | pg-1     | default  | 196      | 1
 99 | witness | witness | * running | pg-1     | default  | 0        | n/a
```

### 4. Cleanup (xóa tất cả services)

```bash
./railway-cleanup.sh
```

## Cấu hình mỗi Service

### pg-1 (Primary)
- **NODE_NAME**: pg-1
- **NODE_ID**: 1
- **PEERS**: pg-2.railway.internal,pg-3.railway.internal
- **Volume**: /var/lib/postgresql

### pg-2, pg-3, pg-4 (Standby)
- Tương tự pg-1 nhưng với NODE_ID khác (2, 3, 4)
- PEERS khác nhau để tối ưu replication topology
- Mỗi node có volume riêng

### witness
- **NODE_NAME**: witness
- **NODE_ID**: 99
- **IS_WITNESS**: true
- **Không có volume** (chỉ chạy repmgrd để vote)

## Networking

Railway tự động tạo private network. Các service gọi nhau qua:
- `pg-1.railway.internal`
- `pg-2.railway.internal`
- `pg-3.railway.internal`
- `pg-4.railway.internal`
- `witness.railway.internal`

## Expose Public Access (Optional)

Nếu muốn connect từ bên ngoài vào pg-1:

1. Vào Railway Dashboard → Service pg-1 → Settings → Networking
2. Generate Domain hoặc TCP Proxy
3. Port: 5432

Connection string:
```
postgresql://postgres:postgrespass@<railway-domain>:5432/postgres
```

## Troubleshooting

### Services không start được
```bash
# Check logs
railway logs --service pg-1

# Common issues:
# - Volume permission: Đảm bảo mount path là /var/lib/postgresql (không phải /data)
# - Env vars: Check tất cả PEERS phải dùng .railway.internal
# - Deploy order: pg-1 phải start trước các standby
```

### Cluster không hình thành
```bash
# SSH vào pg-1
railway ssh --service pg-1

# Check PostgreSQL
gosu postgres pg_isready

# Check repmgr
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Check logs
tail -f /var/log/postgresql/*.log
```

### Redeploy một service
```bash
cd pg-2
railway service pg-2
railway up --detach
```

## Cost Estimate

- Pro Plan: $20/month (required)
- 5 services compute: ~$5-15/month (depends on usage)
- 4 volumes (10GB each): ~$10/month ($0.25/GB/month)
- **Total**: ~$35-45/month

## Performance Tips

1. **Replication lag**: Monitor với `pg_stat_replication`
2. **Failover time**: ~10-30s với repmgrd
3. **Backup**: Railway auto-backup volumes daily
4. **Scaling**: Có thể thêm pg-5, pg-6 bằng cách clone pg-4 folder và adjust env vars

## Security

⚠️ **Important**: Đổi mật khẩu mặc định trong `.env` files trước khi deploy production!

```bash
# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REPMGR_PASSWORD=$(openssl rand -base64 32)

# Update all .env files
for dir in pg-1 pg-2 pg-3 pg-4 witness; do
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" $dir/.env
    sed -i "s/REPMGR_PASSWORD=.*/REPMGR_PASSWORD=$REPMGR_PASSWORD/" $dir/.env
done
```

## Support

- Railway Docs: https://docs.railway.app
- PostgreSQL Docs: https://www.postgresql.org/docs/
- Repmgr Docs: https://repmgr.org/docs/current/
