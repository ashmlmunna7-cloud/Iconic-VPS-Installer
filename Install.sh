#!/bin/bash

# ============================================
# AstraCloud Pterodactyl Panel Installer
# Made with ❤️ by Iconic
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to display ASCII logo
show_logo() {
    clear
    echo -e "${CYAN}"
    echo "    ╔══════════════════════════════════════════════════════════╗"
    echo "    ║                                                          ║"
    echo "    ║     █████╗ ███████╗████████╗██████╗  █████╗               ║"
    echo "    ║    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗              ║"
    echo "    ║    ███████║███████╗   ██║   ██████╔╝███████║              ║"
    echo "    ║    ██╔══██║╚════██║   ██║   ██╔══██╗██╔══██║              ║"
    echo "    ║    ██║  ██║███████║   ██║   ██║  ██║██║  ██║              ║"
    echo "    ║    ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝              ║"
    echo "    ║                                                          ║"
    echo "    ║           Pterodactyl Panel + Wings Installer            ║"
    echo "    ║                   Made with ❤️ by Iconic                   ║"
    echo "    ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to print colored output
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_success() {
    echo -e "${PURPLE}[✓]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Show logo
show_logo

# Configuration variables
print_info "Please enter your configuration:"
read -p "Enter your domain/FQDN [$(hostname -f)]: " FQDN_INPUT
FQDN=${FQDN_INPUT:-$(hostname -f)}
read -p "Enter your email for SSL [$FQDN]: " EMAIL_INPUT
EMAIL=${EMAIL_INPUT:-"admin@${FQDN}"}
read -p "Enter your timezone [UTC]: " TIMEZONE_INPUT
TIMEZONE=${TIMEZONE_INPUT:-"UTC"}

# Generate random passwords
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
MYSQL_PTERO_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
PTERO_USER_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

print_status "Starting installation for: $FQDN"
print_status "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
print_status "MySQL Pterodactyl Password: $MYSQL_PTERO_PASSWORD"
print_status "Pterodactyl Admin Password: $PTERO_USER_PASSWORD"

# Save passwords to file
echo "=== AstraCloud Installation Credentials ===" > /root/astracloud_credentials.txt
echo "Installation Date: $(date)" >> /root/astracloud_credentials.txt
echo "Domain: $FQDN" >> /root/astracloud_credentials.txt
echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD" >> /root/astracloud_credentials.txt
echo "MySQL Pterodactyl Password: $MYSQL_PTERO_PASSWORD" >> /root/astracloud_credentials.txt
echo "Pterodactyl Admin Password: $PTERO_USER_PASSWORD" >> /root/astracloud_credentials.txt
echo "Email: $EMAIL" >> /root/astracloud_credentials.txt
chmod 600 /root/astracloud_credentials.txt
print_warning "Credentials saved to: /root/astracloud_credentials.txt"

# System Update
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install dependencies
print_status "Installing dependencies..."
apt install -y curl wget gnupg2 software-properties-common apt-transport-https \
    ca-certificates lsb-release git unzip zip nginx mysql-server redis-server \
    certbot python3-certbot-nginx tar

# Install PHP 8.2
print_status "Installing PHP 8.2..."
apt install -y lsb-release ca-certificates apt-transport-https software-properties-common
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.2 php8.2-cli php8.2-common php8.2-mysql php8.2-zip php8.2-gd \
    php8.2-mbstring php8.2-curl php8.2-xml php8.2-bcmath php8.2-fpm php8.2-redis

# Configure PHP
print_status "Configuring PHP..."
sed -i 's/^memory_limit = .*/memory_limit = 256M/' /etc/php/8.2/fpm/php.ini
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
systemctl restart php8.2-fpm

# Install Composer
print_status "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# Configure MySQL
print_status "Configuring MySQL..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';"
mysql -e "CREATE DATABASE panel;"
mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PTERO_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"

# Download Pterodactyl Panel
print_status "Downloading Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Install Panel dependencies
print_status "Installing Panel dependencies..."
cp .env.example .env
composer install --no-dev --optimize-autoloader

# Generate application key
print_status "Generating application key..."
php artisan key:generate --force

# Configure environment
print_status "Configuring environment..."
php artisan p:environment:setup \
    --author="admin@${FQDN}" \
    --url="https://${FQDN}" \
    --timezone="${TIMEZONE}" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="" \
    --redis-port="6379"

php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${MYSQL_PTERO_PASSWORD}"

# Run migrations
print_status "Running database migrations..."
php artisan migrate --seed --force

# Create admin user
print_status "Creating admin user..."
php artisan p:user:make \
    --email="${EMAIL}" \
    --username="admin" \
    --name-first="Admin" \
    --name-last="User" \
    --password="${PTERO_USER_PASSWORD}" \
    --admin=1

# Set permissions
print_status "Setting permissions..."
chown -R www-data:www-data /var/www/pterodactyl/*
chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

# Create queue worker
print_status "Creating queue worker..."
cat > /etc/systemd/system/pteroq.service << 'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq.service

# Configure Nginx
print_status "Configuring Nginx..."
cat > /etc/nginx/sites-available/pterodactyl << 'EOF'
server {
    listen 80;
    server_name FQDN_PLACEHOLDER;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name FQDN_PLACEHOLDER;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    ssl_certificate     /etc/letsencrypt/live/FQDN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/FQDN_PLACEHOLDER/privkey.pem;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sed -i "s/FQDN_PLACEHOLDER/${FQDN}/g" /etc/nginx/sites-available/pterodactyl
ln -sf /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
rm -f /etc/nginx/sites-enabled/default

# Install SSL certificate
print_status "Installing SSL certificate..."
certbot --nginx -d ${FQDN} --non-interactive --agree-tos --email ${EMAIL}

# Install Docker
print_status "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Install Wings
print_status "Installing Pterodactyl Wings..."
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -L -o wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

# Create Wings service
cat > /etc/systemd/system/wings.service << 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/etc/pterodactyl/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now wings

# Install Blueprint
print_status "Installing Blueprint..."
cd /var/www/pterodactyl
curl -Lo blueprint.sh https://blueprint.zip/install.sh
chmod +x blueprint.sh
bash blueprint.sh --auto --yes

# Install additional Blueprint extensions
print_status "Installing Blueprint extensions..."
php artisan blueprint:install
php artisan blueprint:extensions:install

# Configure firewall
print_status "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8080/tcp
ufw --force enable

# Restart services
print_status "Restarting services..."
systemctl restart nginx
systemctl restart php8.2-fpm
systemctl restart redis-server
systemctl restart wings
systemctl restart pteroq

# Final message
show_logo
print_success "=========================================="
print_success "Installation Complete!"
print_success "=========================================="
print_success "Panel URL: https://${FQDN}"
print_success "Admin Email: ${EMAIL}"
print_success "Admin Password: ${PTERO_USER_PASSWORD}"
print_success ""
print_success "Credentials saved to: /root/astracloud_credentials.txt"
print_success ""
print_warning "Please save these credentials securely!"
print_success "=========================================="
print_success "Made with ❤️ by Iconic"
print_success "AstraCloud - Your Trusted Hosting Solution"
print_success "=========================================="

# Optional: Send email with credentials
print_status "Would you like to send credentials to your email? (y/n)"
read -p "> " SEND_EMAIL
if [[ $SEND_EMAIL == "y" ]]; then
    mail -s "AstraCloud Installation Credentials" ${EMAIL} < /root/astracloud_credentials.txt
    print_success "Credentials sent to ${EMAIL}"
fi

# Restart prompt
print_status "Installation complete! System will restart in 10 seconds..."
sleep 10
reboot
