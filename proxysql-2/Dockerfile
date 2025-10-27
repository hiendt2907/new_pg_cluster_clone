FROM proxysql/proxysql:3.0.2

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    postgresql-client \
    python3 \
    python3-pip \
    jq \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/monitor.sh

# ProxySQL 3.0 PostgreSQL ports: 6132 (admin), 5432 (postgres traffic - trading optimized)
EXPOSE 6132 5432

ENTRYPOINT ["/entrypoint.sh"]
