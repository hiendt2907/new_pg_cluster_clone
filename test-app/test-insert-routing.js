#!/usr/bin/env node

const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 15432,
  database: 'postgres',
  user: 'app_readwrite',
  password: 'appreadwritepass',
  max: 1,
});

async function test() {
  console.log('\n╔════════════════════════════════════════════════════╗');
  console.log('║   Pgpool-II Write Routing Verification Test       ║');
  console.log('╚════════════════════════════════════════════════════╝\n');

  const client = await pool.connect();
  
  try {
    // Test: Standalone INSERT with RETURNING backend info
    console.log('Test: Standalone INSERT with RETURNING inet_server_addr()');
    console.log('─'.repeat(60));
    
    const result = await client.query(`
      INSERT INTO test_routing (data) 
      VALUES ('test-' || NOW()::TEXT) 
      RETURNING *, inet_server_addr() as backend_ip, inet_server_port() as backend_port
    `);
    
    const row = result.rows[0];
    const backendMap = {
      '172.20.0.7': 'pg-1 (PRIMARY)',
      '172.20.0.11': 'pg-2 (STANDBY)',
      '172.20.0.12': 'pg-4 (STANDBY)',
      '172.20.0.14': 'pg-3 (STANDBY)',
    };
    
    const backendName = backendMap[row.backend_ip] || `Unknown (${row.backend_ip})`;
    
    console.log(`Inserted data: ${row.data}`);
    console.log(`Backend IP: ${row.backend_ip}`);
    console.log(`Backend Name: ${backendName}`);
    console.log(`\nResult: ${row.backend_ip === '172.20.0.7' ? '✅ Went to PRIMARY (correct!)' : '❌ Went to STANDBY (WRONG!)'}`);
    
    if (row.backend_ip !== '172.20.0.7') {
      console.log('\n⚠️  WARNING: INSERT executed on STANDBY!');
      console.log('This should NOT happen - standbys are read-only!');
      console.log('This means pgpool is NOT routing DML queries correctly!\n');
    } else {
      console.log('\n🎉 SUCCESS: Pgpool correctly routed standalone INSERT to PRIMARY!');
      console.log('Even without explicit transactions, DML queries go to PRIMARY.\n');
    }

  } finally {
    client.release();
    await pool.end();
  }
}

test().catch(err => {
  console.error('Test failed:', err);
  process.exit(1);
});
