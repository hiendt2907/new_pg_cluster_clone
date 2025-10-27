FROM postgres:17

# Install pgpool-II
RUN apt-get update && apt-get install -y \
    pgpool2 \
    postgresql-17-pgpool2 \
    curl \
    jq \
    python3 \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/monitor.sh

EXPOSE 5432 9999

ENTRYPOINT ["/entrypoint.sh"]
