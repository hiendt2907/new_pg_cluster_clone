# Hướng dẫn Deploy PostgreSQL HA Cluster lên Railway

## Yêu cầu
- Railway Pro plan (để có nhiều services và volumes)
- Railway CLI đã login: `railway login`
- Project đã được tạo: `railway init`

## Bước 1: Truy cập Dashboard
```bash
railway open
```

## Bước 2: Tạo 5 Services

### Tạo Service pg-1 (Primary)
1. Click "New Service" → "Empty Service"
2. Đặt tên: `pg-1`
3. Settings → Source:
   - Connect to GitHub: `hiendt2907/new_pg_cluster_clone`
   - Branch: `master`
4. Settings → Build:
   - Builder: Dockerfile
   - Dockerfile Path: `Dockerfile`
5. Settings → Deploy:
   - Custom Start Command: `bash /usr/local/bin/entrypoint.sh`

### Variables cho pg-1:
```
NODE_NAME=pg-1
NODE_ID=1
POSTGRES_PASSWORD=YourSecurePassword123!
REPMGR_PASSWORD=RepmgrSecurePass456!
PEERS=pg-2.railway.internal,pg-3.railway.internal
PRIMARY_HINT=pg-1
```

### Volume cho pg-1:
- Mount Path: `/var/lib/postgresql`

---

### Tạo Service pg-2 (Standby)
1. Lặp lại như pg-1, đặt tên: `pg-2`

### Variables cho pg-2:
```
NODE_NAME=pg-2
NODE_ID=2
POSTGRES_PASSWORD=YourSecurePassword123!
REPMGR_PASSWORD=RepmgrSecurePass456!
PEERS=pg-1.railway.internal,pg-3.railway.internal
PRIMARY_HINT=pg-1
```

### Volume cho pg-2:
- Mount Path: `/var/lib/postgresql`

---

### Tạo Service pg-3 (Standby)
1. Lặp lại như pg-1, đặt tên: `pg-3`

### Variables cho pg-3:
```
NODE_NAME=pg-3
NODE_ID=3
POSTGRES_PASSWORD=YourSecurePassword123!
REPMGR_PASSWORD=RepmgrSecurePass456!
PEERS=pg-1.railway.internal,pg-2.railway.internal
PRIMARY_HINT=pg-1
```

### Volume cho pg-3:
- Mount Path: `/var/lib/postgresql`

---

### Tạo Service pg-4 (Standby)
1. Lặp lại như pg-1, đặt tên: `pg-4`

### Variables cho pg-4:
```
NODE_NAME=pg-4
NODE_ID=4
POSTGRES_PASSWORD=YourSecurePassword123!
REPMGR_PASSWORD=RepmgrSecurePass456!
PEERS=pg-1.railway.internal,pg-2.railway.internal
PRIMARY_HINT=pg-1
```

### Volume cho pg-4:
- Mount Path: `/var/lib/postgresql`

---

### Tạo Service witness
1. Lặp lại như pg-1, đặt tên: `witness`

### Variables cho witness:
```
NODE_NAME=witness
NODE_ID=99
IS_WITNESS=true
REPMGR_PASSWORD=RepmgrSecurePass456!
PRIMARY_HOST=pg-1.railway.internal
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal
```

**Không cần volume cho witness**

---

## Bước 3: Thứ tự Deploy

**Quan trọng**: Deploy theo thứ tự này:

1. Deploy `pg-1` trước (primary node)
2. Đợi pg-1 chạy ổn định (~2-3 phút)
3. Deploy `witness`
4. Deploy `pg-2`, `pg-3`, `pg-4` cùng lúc

## Bước 4: Kiểm tra Logs

### Xem logs của pg-1:
```bash
railway logs --service pg-1
```

### Xem logs của pg-2:
```bash
railway logs --service pg-2
```

### Kiểm tra cluster status (SSH vào pg-1):
```bash
railway ssh --service pg-1
# Trong container:
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

## Bước 5: Expose Port (Nếu cần kết nối từ bên ngoài)

Cho service `pg-1`:
1. Settings → Networking
2. Tạo Public Domain hoặc TCP Proxy
3. Port: 5432

## Lưu ý quan trọng

### 1. Private Networking
Railway tự động tạo private network giữa các services trong cùng project. 
Các service có thể gọi nhau qua: `<service-name>.railway.internal`

### 2. Volumes
- Railway tự động backup volumes
- Volumes persist khi redeploy
- Mount vào `/var/lib/postgresql` để tránh permission issues

### 3. Resource Limits (Pro Plan)
- Mỗi service: 8GB RAM, 8 vCPU
- 5 services × ~500MB RAM ≈ 2.5GB total
- Volumes: Unlimited storage (tính phí theo GB/month)

### 4. Cost Estimate
- Pro plan: $20/month
- Compute: ~$5-10/month cho 5 services (tùy usage)
- Storage: ~$0.25/GB/month
- Total: ~$30-40/month

## Troubleshooting

### Lỗi: "Device or resource busy"
- Chờ 30s sau khi deploy trước khi redeploy
- Hoặc restart service

### Lỗi: "Password authentication failed"
- Kiểm tra `REPMGR_PASSWORD` phải giống nhau trên tất cả services
- Kiểm tra `POSTGRES_PASSWORD` phải giống nhau

### Lỗi: "Could not find primary"
- Đảm bảo pg-1 đã deploy và chạy trước
- Kiểm tra `PRIMARY_HINT=pg-1` trong env vars
- Kiểm tra PEERS có đúng domain `.railway.internal`

### Nodes không kết nối được với nhau
- Kiểm tra Private Networking đã được enable
- Kiểm tra service names match với PEERS config
- Format đúng: `pg-2.railway.internal,pg-3.railway.internal`

## Giám sát

### Xem tất cả logs:
```bash
# Terminal 1
railway logs --service pg-1 --follow

# Terminal 2
railway logs --service pg-2 --follow

# Terminal 3
railway logs --service pg-3 --follow
```

### Health check:
```bash
railway ssh --service pg-1
gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```
