#!/usr/bin/env python3
"""
Generate test traces to Tempo for latency visualization
"""
import time
import random
import requests
import json
from datetime import datetime

TEMPO_URL = "http://localhost:4318/v1/traces"  # OTLP HTTP endpoint

def generate_trace():
    """Generate a sample trace with spans"""
    trace_id = f"{random.randint(0, 2**128-1):032x}"
    span_id_counter = random.randint(0, 2**64-1)
    
    # Root span - application request
    root_span_id = f"{span_id_counter:016x}"
    span_id_counter += 1
    
    # Database query span
    db_span_id = f"{span_id_counter:016x}"
    span_id_counter += 1
    
    # Cache check span
    cache_span_id = f"{span_id_counter:016x}"
    
    now_ns = int(time.time() * 1_000_000_000)
    
    # Simulate different latencies
    root_duration_ms = random.randint(50, 500)
    db_duration_ms = random.randint(10, root_duration_ms - 20)
    cache_duration_ms = random.randint(1, 10)
    
    trace = {
        "resourceSpans": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": "postgresql-app"}},
                    {"key": "deployment.environment", "value": {"stringValue": "production"}},
                    {"key": "cluster", "value": {"stringValue": "pg_ha_cluster"}}
                ]
            },
            "scopeSpans": [{
                "spans": [
                    # Root span
                    {
                        "traceId": trace_id,
                        "spanId": root_span_id,
                        "name": "HTTP GET /api/users",
                        "kind": 1,  # SERVER
                        "startTimeUnixNano": str(now_ns),
                        "endTimeUnixNano": str(now_ns + root_duration_ms * 1_000_000),
                        "attributes": [
                            {"key": "http.method", "value": {"stringValue": "GET"}},
                            {"key": "http.url", "value": {"stringValue": "/api/users"}},
                            {"key": "http.status_code", "value": {"intValue": str(200)}},
                        ],
                        "status": {"code": 0}
                    },
                    # Database span
                    {
                        "traceId": trace_id,
                        "spanId": db_span_id,
                        "parentSpanId": root_span_id,
                        "name": "SELECT users",
                        "kind": 3,  # CLIENT
                        "startTimeUnixNano": str(now_ns + 5_000_000),
                        "endTimeUnixNano": str(now_ns + 5_000_000 + db_duration_ms * 1_000_000),
                        "attributes": [
                            {"key": "db.system", "value": {"stringValue": "postgresql"}},
                            {"key": "db.name", "value": {"stringValue": "app_db"}},
                            {"key": "db.statement", "value": {"stringValue": "SELECT * FROM users WHERE active = true LIMIT 100"}},
                            {"key": "db.operation", "value": {"stringValue": "SELECT"}},
                            {"key": "peer.service", "value": {"stringValue": "postgresql"}},
                        ],
                        "status": {"code": 0}
                    },
                    # Cache span
                    {
                        "traceId": trace_id,
                        "spanId": cache_span_id,
                        "parentSpanId": root_span_id,
                        "name": "REDIS GET user:cache",
                        "kind": 3,  # CLIENT
                        "startTimeUnixNano": str(now_ns + 2_000_000),
                        "endTimeUnixNano": str(now_ns + 2_000_000 + cache_duration_ms * 1_000_000),
                        "attributes": [
                            {"key": "db.system", "value": {"stringValue": "redis"}},
                            {"key": "db.operation", "value": {"stringValue": "GET"}},
                            {"key": "cache.hit", "value": {"boolValue": random.choice([True, False])}},
                        ],
                        "status": {"code": 0}
                    }
                ]
            }]
        }]
    }
    
    return trace

def send_trace(trace):
    """Send trace to Tempo"""
    try:
        response = requests.post(
            TEMPO_URL,
            headers={"Content-Type": "application/json"},
            data=json.dumps(trace),
            timeout=5
        )
        return response.status_code == 200
    except Exception as e:
        print(f"Error sending trace: {e}")
        return False

def main():
    print("🔍 Generating test traces for Tempo...")
    print(f"Target: {TEMPO_URL}")
    print()
    
    success_count = 0
    total = 50  # Generate 50 traces
    
    for i in range(total):
        trace = generate_trace()
        if send_trace(trace):
            success_count += 1
            print(f"✅ Trace {i+1}/{total} sent successfully")
        else:
            print(f"❌ Trace {i+1}/{total} failed")
        
        # Random delay between traces
        time.sleep(random.uniform(0.1, 0.5))
    
    print()
    print(f"📊 Summary: {success_count}/{total} traces sent successfully")
    print()
    print("🌐 View traces in Grafana:")
    print("   Dashboard: Tempo Service Map & Latency Flow")
    print("   URL: http://localhost:3000/d/c8489f64-56d7-4bae-abf7-fa07ecbe0c2b")

if __name__ == "__main__":
    main()
