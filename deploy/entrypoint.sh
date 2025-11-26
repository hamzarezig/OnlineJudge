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
    # Update configurations to use Railway's port
    export FORCE_HTTPS=true  # Railway uses HTTPS
fi

cd $APP/deploy/nginx
# Simplify nginx configuration for Railway
ln -sf locations.conf https_locations.conf
ln -sf https_redirect.conf http_locations.conf

# Database setup with retries
n=0
while [ $n -lt 5 ]
do
    python manage.py makemigrations account contest options problem submission &&
    python manage.py migrate --no-input &&
    python manage.py inituser --username=root --password=rootroot --action=create_super_admin &&
    echo "from options.options import SysOptions; SysOptions.judge_server_token='$JUDGE_SERVER_TOKEN'" | python manage.py shell &&
    echo "from conf.models import JudgeServer; JudgeServer.objects.update(task_number=0)" | python manage.py shell &&
    break
    n=$(($n+1))
    echo "Failed to migrate, going to retry..."
    sleep 8
done

# Fix permissions
addgroup -g 903 spj
adduser -u 900 -S -G spj server
chown -R server:spj $DATA $APP/dist
find $DATA/test_case -type d -exec chmod 710 {} \;
find $DATA/test_case -type f -exec chmod 640 {} \;

exec supervisord -c /app/deploy/supervisord.conf
