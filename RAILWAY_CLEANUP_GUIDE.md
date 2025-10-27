# Hướng dẫn Cleanup Services trên Railway

## Cách 1: Qua Dashboard (Recommended)

1. Mở Railway Dashboard:
   ```bash
   railway open
   ```

2. Với mỗi service (pg-1, pg-2, pg-3, pg-4, witness):
   - Click vào service
   - Settings → Danger Zone → Delete Service
   - Confirm deletion

## Cách 2: Qua CLI (từng service)

```bash
# Delete pg-1
railway service pg-1
railway service delete
# Confirm with 'y'

# Delete pg-2
railway service pg-2
railway service delete  
# Confirm with 'y'

# Tương tự cho pg-3, pg-4, witness
```

## Volumes

Volumes sẽ **TỰ ĐỘNG BỊ XÓA** khi service bị xóa.

## Sau khi cleanup

Deploy lại toàn bộ:
```bash
./railway-deploy.sh
```

---

**Note**: Railway CLI không hỗ trợ delete batch services hoặc `--yes` flag, 
nên phải xóa từng service một và confirm manual.
