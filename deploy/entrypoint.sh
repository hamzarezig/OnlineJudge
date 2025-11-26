#!/bin/sh

APP=/app
DATA=/data

mkdir -p $DATA/log $DATA/config $DATA/ssl $DATA/test_case $DATA/public/upload $DATA/public/avatar $DATA/public/website

if [ ! -f "$DATA/config/secret.key" ]; then
    echo $(cat /dev/urandom | head -1 | md5sum | head -c 32) > "$DATA/config/secret.key"
fi

if [ ! -f "$DATA/public/avatar/default.png" ]; then
    cp data/public/avatar/default.png $DATA/public/avatar
fi

if [ ! -f "$DATA/public/website/favicon.ico" ]; then
    cp data/public/website/favicon.ico $DATA/public/website
fi

# Railway-specific configuration
if [ ! -z "$PORT" ]; then
    echo "Configuring for Railway PORT: $PORT"
    export FORCE_HTTPS=true
fi

# Fix: Change to correct directory before running manage.py
cd $APP

# Database setup with retries
n=0
while [ $n -lt 5 ]
do
    echo "Running migrations attempt $(($n+1))..."
    python manage.py makemigrations account contest options problem submission &&
    python manage.py migrate --no-input &&
    python manage.py inituser --username=root --password=rootroot --action=create_super_admin &&
    echo "from options.options import SysOptions; SysOptions.judge_server_token='$JUDGE_SERVER_TOKEN'" | python manage.py shell &&
    echo "from conf.models import JudgeServer; JudgeServer.objects.update(task_number=0)" | python manage.py shell &&
    echo "Migrations completed successfully!" &&
    break
    n=$(($n+1))
    echo "Failed to migrate, going to retry..."
    sleep 8
done

# Fix permissions (only if users don't exist)
if ! getent group spj > /dev/null; then
    addgroup -g 903 spj
fi

if ! id "server" > /dev/null 2>&1; then
    adduser -u 900 -S -G spj server
fi

chown -R server:spj $DATA $APP/dist
find $DATA/test_case -type d -exec chmod 710 {} \;
find $DATA/test_case -type f -exec chmod 640 {} \;

# Set default MAX_WORKER_NUM if not set
if [ -z "$MAX_WORKER_NUM" ]; then
    export MAX_WORKER_NUM=2
    echo "Setting MAX_WORKER_NUM to $MAX_WORKER_NUM"
fi

# Fix nginx configuration for Railway
if [ ! -z "$PORT" ]; then
    echo "Updating nginx to use PORT: $PORT"
    # Replace the port in nginx.conf
    sed -i "s/listen 8000 default_server;/listen $PORT default_server;/g" /app/deploy/nginx/nginx.conf
    # Also update the upstream backend if needed
    sed -i "s/server 127.0.0.1:8080;/server 127.0.0.1:$PORT;/g" /app/deploy/nginx/nginx.conf
fi

# Test nginx configuration
echo "Testing nginx configuration:"
nginx -t -c /app/deploy/nginx/nginx.conf


exec supervisord -c /app/deploy/supervisord.conf
