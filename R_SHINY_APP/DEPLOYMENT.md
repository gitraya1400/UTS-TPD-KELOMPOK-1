# Deployment Guide - Livestock Intelligence Dashboard

## Local Development

### Quick Start

```bash
# 1. Clone/navigate to project
cd R_SHINY_APP

# 2. Install dependencies (first time only)
Rscript install_packages.R

# 3. Configure environment
cp .env.example .env
# Edit .env with your database credentials

# 4. Launch dashboard
Rscript -e "shiny::runApp()"

# Dashboard available at: http://localhost:3838
```

### Development Mode Features
- Hot reload on file changes (Ctrl+Shift+F5)
- Full error messages and stack traces
- Console output visible
- Debug statements print to console

---

## Server Deployment (Linux/Ubuntu)

### Prerequisites
```bash
# Install R
sudo apt-get update
sudo apt-get install r-base r-base-dev

# Install system dependencies for spatial packages
sudo apt-get install libgdal-dev libproj-dev libgeos-dev

# Install PostgreSQL client (to test DB connection)
sudo apt-get install postgresql-client
```

### Step 1: Setup User & Directory

```bash
# Create dedicated shiny user
sudo useradd -m -s /bin/bash shiny

# Create app directory
sudo mkdir -p /var/www/livestock-intelligence
sudo chown shiny:shiny /var/www/livestock-intelligence

# Clone/copy application
sudo -u shiny cp -r R_SHINY_APP/* /var/www/livestock-intelligence/
```

### Step 2: Install R Packages (as shiny user)

```bash
sudo -u shiny Rscript /var/www/livestock-intelligence/install_packages.R
```

### Step 3: Configure Environment

```bash
# Create .env file
sudo -u shiny cat > /var/www/livestock-intelligence/.env << EOF
DB_HOST=your.database.server
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=your_db_user
DB_PASSWORD=your_secure_password
SHINY_PORT=3838
SHINY_HOST=0.0.0.0
EOF

# Secure permissions
sudo chmod 600 /var/www/livestock-intelligence/.env
```

### Step 4: Install & Configure Shiny Server

```bash
# Install Shiny Server
cd /tmp
wget https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-latest-amd64.deb
sudo gdebi shiny-server-latest-amd64.deb

# Configure Shiny Server
sudo tee /etc/shiny-server/shiny-server.conf > /dev/null << EOF
# Instruct Shiny Server to run applications as the shiny user
run_as shiny;

# Define a server that listens on port 3838
server {
  listen 3838;

  # Define a location at the base URL
  location / {
    # Host the directory of Shiny Apps stored in this directory
    site_dir /var/www/livestock-intelligence;

    # Logging options
    access_log /var/log/shiny-server/access.log;

    # Use application defaults
  }
}
EOF

# Restart Shiny Server
sudo systemctl restart shiny-server
```

### Step 5: Configure Nginx as Reverse Proxy (Optional but Recommended)

```bash
# Install Nginx
sudo apt-get install nginx

# Configure Nginx
sudo tee /etc/nginx/sites-available/livestock-intelligence > /dev/null << 'EOF'
server {
    listen 80;
    server_name livestock-intelligence.example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name livestock-intelligence.example.com;

    # SSL certificates (use Let's Encrypt certbot)
    ssl_certificate /etc/letsencrypt/live/livestock-intelligence.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/livestock-intelligence.example.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # Proxy to Shiny Server
    location / {
        proxy_pass http://127.0.0.1:3838;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/livestock-intelligence /etc/nginx/sites-enabled/

# Test Nginx config
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

### Step 6: Setup SSL Certificate (Let's Encrypt)

```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot certonly --standalone -d livestock-intelligence.example.com

# Auto-renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### Step 7: Setup Log Rotation

```bash
# Create logrotate config
sudo tee /etc/logrotate.d/livestock-intelligence > /dev/null << EOF
/var/log/shiny-server/*.log {
    daily
    rotate 14
    missingok
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload shiny-server > /dev/null 2>&1 || true
    endscript
}
EOF
```

### Step 8: Monitor & Systemd Service (Optional)

```bash
# Create systemd service file
sudo tee /etc/systemd/system/livestock-intelligence.service > /dev/null << EOF
[Unit]
Description=Livestock Intelligence Shiny Dashboard
After=network.target postgresql.service

[Service]
Type=simple
User=shiny
WorkingDirectory=/var/www/livestock-intelligence
ExecStart=/usr/bin/Rscript -e "shiny::runApp(port=3838,host='0.0.0.0')"
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable livestock-intelligence
sudo systemctl start livestock-intelligence

# Check status
sudo systemctl status livestock-intelligence
```

---

## Docker Deployment

### Dockerfile

```dockerfile
FROM rocker/shiny:latest

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /srv/shiny-server/livestock-intelligence

# Copy application files
COPY . .

# Install R packages
RUN Rscript install_packages.R

# Set environment variables
ENV DB_HOST=postgres
ENV DB_PORT=5432
ENV DB_NAME=datawarehouse_db
ENV DB_USER=postgres
ENV DB_PASSWORD=

# Expose port
EXPOSE 3838

# Run Shiny app
CMD ["R", "-e", "shiny::runApp(port=3838, host='0.0.0.0')"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  shiny:
    build: .
    ports:
      - "3838:3838"
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: datawarehouse_db
      DB_USER: postgres
      DB_PASSWORD: secure_password
    depends_on:
      - postgres
    volumes:
      - ./data:/srv/shiny-server/livestock-intelligence/data
    networks:
      - livestock

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: datawarehouse_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./DATA/DWH/dwh_schema_final.sql:/docker-entrypoint-initdb.d/01-schema.sql
      - ./DATA/DWH/dwh_data_final.sql:/docker-entrypoint-initdb.d/02-data.sql
    networks:
      - livestock

volumes:
  postgres_data:

networks:
  livestock:
    driver: bridge
```

### Run Docker

```bash
# Build and start containers
docker-compose up -d

# View logs
docker-compose logs -f shiny

# Stop containers
docker-compose down
```

---

## Cloud Deployment (AWS EC2)

### AWS EC2 Setup

```bash
# 1. Launch EC2 instance
# - AMI: Ubuntu 22.04 LTS
# - Instance Type: t3.medium (2 vCPU, 4GB RAM)
# - Storage: 50GB (gp3)
# - Security Group: Allow SSH (22), HTTP (80), HTTPS (443)

# 2. SSH into instance
ssh -i your-key.pem ubuntu@your-instance-ip

# 3. Update system
sudo apt-get update
sudo apt-get upgrade -y

# 4. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu

# 5. Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 6. Clone repository
git clone https://github.com/your-repo/livestock-intelligence.git
cd livestock-intelligence/R_SHINY_APP

# 7. Configure environment
cp .env.example .env
# Edit .env with production credentials

# 8. Start application
docker-compose up -d

# 9. Setup SSL (Let's Encrypt)
sudo apt-get install certbot
sudo certbot certonly --standalone -d your-domain.com
```

### RDS Database Configuration

```bash
# In AWS Console:
# 1. Create RDS PostgreSQL instance
# 2. Configure security group to allow connections from EC2
# 3. Update .env with RDS endpoint

# Test connection from EC2:
psql -h your-rds-endpoint.rds.amazonaws.com -U postgres -d datawarehouse_db
```

---

## Performance Optimization

### Database Optimization

```sql
-- Create materialized views for common queries
CREATE MATERIALIZED VIEW mv_top_risk_provinces AS
SELECT 
  p.prov_key,
  p.nama_provinsi,
  AVG(f.supply_risk_index) as avg_risk
FROM fact_supply_resilience f
JOIN dim_prov p ON f.prov_key = p.prov_key
GROUP BY p.prov_key, p.nama_provinsi;

-- Refresh periodically (e.g., daily)
REFRESH MATERIALIZED VIEW mv_top_risk_provinces;

-- Query from view (faster)
SELECT * FROM mv_top_risk_provinces ORDER BY avg_risk DESC LIMIT 5;
```

### Connection Pooling (pgBouncer)

```bash
# Install pgBouncer
sudo apt-get install pgbouncer

# Configure
sudo tee /etc/pgbouncer/pgbouncer.ini > /dev/null << EOF
[databases]
datawarehouse_db = host=localhost port=5432 dbname=datawarehouse_db

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
default_pool_size = 10
EOF

# Start
sudo systemctl start pgbouncer
```

### R Shiny Optimization

```r
# In global.R
# Increase session timeout
shiny::shinyOptions(cache = cachem::cache_mem())

# Preload heavy data at app startup (not per-session)
# This data is shared across all users
provinces_cache <- dbGetQuery(con, "SELECT * FROM dim_prov")
commodities_cache <- dbGetQuery(con, "SELECT * FROM dim_komoditas")
```

---

## Monitoring & Maintenance

### Health Check Endpoint

```bash
# Create health check script
curl -f http://localhost:3838/ || exit 1
```

### Monitoring with Prometheus

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
```

### Log Aggregation

```bash
# Install ELK Stack or use CloudWatch
# Forward logs to centralized logging service

# For CloudWatch:
sudo awslogs configure
sudo service awslogs start
```

---

## Troubleshooting Deployment

### Issue: Shiny Server Won't Start

```bash
# Check logs
sudo tail -f /var/log/shiny-server/access.log
sudo journalctl -u shiny-server -n 50

# Verify R packages installed
sudo -u shiny Rscript -e "library(shiny); library(sf)"

# Test app directly
sudo -u shiny Rscript -e "shiny::runApp('/var/www/livestock-intelligence', port=3838)"
```

### Issue: Database Connection Failed

```bash
# Test connection
psql -h DB_HOST -U DB_USER -d DB_NAME -c "SELECT 1"

# Check .env variables
cat /var/www/livestock-intelligence/.env

# Verify network connectivity
nc -zv DB_HOST 5432

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql.log
```

### Issue: Slow Performance

```bash
# Check server resources
top
free -h
df -h

# Analyze slow queries
sudo -u postgres psql -d datawarehouse_db -c "
  SELECT query, mean_exec_time, calls
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC LIMIT 10;
"

# Check Shiny app memory usage
ps aux | grep Rscript
```

---

## Rollback Procedure

```bash
# Keep previous version
sudo mv /var/www/livestock-intelligence /var/www/livestock-intelligence.backup

# Restore previous version
sudo mv /var/www/livestock-intelligence.v1 /var/www/livestock-intelligence

# Restart service
sudo systemctl restart shiny-server

# Verify health
curl -f http://localhost:3838/ || echo "FAILED"
```

---

## Security Checklist

- [ ] Update all OS packages: `sudo apt-get update && apt-get upgrade`
- [ ] Configure SSH key-based authentication only
- [ ] Disable root login
- [ ] Setup firewall: `sudo ufw enable`
- [ ] Configure HTTPS with SSL certificates
- [ ] Setup database credentials in secure vault (AWS Secrets Manager)
- [ ] Enable database encryption at rest
- [ ] Setup backup & disaster recovery plan
- [ ] Enable audit logging
- [ ] Regular security updates: `sudo unattended-upgrade`
- [ ] Setup DDoS protection (CloudFlare, AWS Shield)
- [ ] Database backups: `sudo -u postgres pg_dump datawarehouse_db > backup.sql`

---

**Document Version**: 1.0  
**Last Updated**: 2026-05-04
