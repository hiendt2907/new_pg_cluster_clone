# PostgreSQL HA Cluster - Test Suite

Simple tests to verify cluster functionality.

## 🚀 Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Get passwords from .env
cd ..
./scripts/show-credentials.sh

# 3. Update test files with your APP_READWRITE_PASSWORD

# 4. Run tests
cd test-app
node test-simple.js           # Simple cluster test
node test-insert-routing.js   # INSERT routing verification
```

## 📋 Available Tests

### 1. test-simple.js ⭐ **Recommended**
**Simple end-to-end cluster test**

Tests:
- ✅ Connection to Pgpool
- ✅ Table creation
- ✅ INSERT (routes to PRIMARY)
- ✅ SELECT (routes to STANDBYs)
- ✅ Transactions
- ✅ Data integrity

**Usage:**
```bash
node test-simple.js
```

### 2. test-insert-routing.js
**INSERT routing verification**

Tests:
- ✅ Verifies INSERT queries go to PRIMARY
- ✅ Checks read/write splitting

**Usage:**
```bash
node test-insert-routing.js
```

## ⚙️ Configuration

Update password in test files:

```javascript
const APP_READWRITE_PASSWORD = 'YOUR_PASSWORD_FROM_ENV';
```

Get your password:
```bash
../scripts/show-credentials.sh
```

Or check `.env` file.

## 🧪 Expected Output

```
╔══════════════════════════════════════════════════════════════╗
║         PostgreSQL HA Cluster - Simple Test                 ║
╚══════════════════════════════════════════════════════════════╝

📊 Test 1: Connection to Pgpool...
✅ Connected successfully!

📊 Test 2: Create test table...
✅ Table created/verified

📊 Test 3: INSERT query (should route to PRIMARY)...
✅ INSERT successful!

📊 Test 4: SELECT query (should route to STANDBYs)...
✅ SELECT successful!

📊 Test 5: Transaction test...
✅ Transaction committed successfully!

📊 Test 6: Final verification...
✅ Verification successful!

╔══════════════════════════════════════════════════════════════╗
║                    ✅ ALL TESTS PASSED!                      ║
╚══════════════════════════════════════════════════════════════╝
```

## 🐛 Troubleshooting

If tests fail:

1. **Check cluster is running:**
   ```bash
   docker-compose ps
   ```

2. **Verify passwords:**
   ```bash
   ../scripts/show-credentials.sh
   ```

3. **Check pgpool logs:**
   ```bash
   docker logs pgpool-1
   ```

4. **Check PostgreSQL logs:**
   ```bash
   docker logs pg-1
   ```
