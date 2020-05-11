#!/bin/bash

set -x

apt-get update -y

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get install docker-ce docker-ce-cli containerd.io -y

apt-get update

apt-get install -y python3-venv

python3 -m venv /opt/jupyterhub/

/opt/jupyterhub/bin/python3 -m pip install wheel
/opt/jupyterhub/bin/python3 -m pip install jupyterhub jupyterlab
/opt/jupyterhub/bin/python3 -m pip install ipywidgets

apt install -y nodejs npm

npm install -g configurable-http-proxy


mkdir -p /opt/jupyterhub/etc/jupyterhub/
cd /opt/jupyterhub/etc/jupyterhub/

/opt/jupyterhub/bin/jupyterhub --generate-config
echo "c.Spawner.default_url = '/lab'" >> /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py
echo "c.JupyterHub.bind_url = 'http://:8000/jupyter'" >> /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py

mkdir -p /opt/jupyterhub/etc/systemd

cat << '_EOF_' > /opt/jupyterhub/etc/systemd/jupyterhub.service
Description=JupyterHub
After=syslog.target network.target

[Service]
User=root
Environment="PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/opt/jupyterhub/bin"
ExecStart=/opt/jupyterhub/bin/jupyterhub -f /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py

[Install]
WantedBy=multi-user.target
_EOF_


ln -s /opt/jupyterhub/etc/systemd/jupyterhub.service /etc/systemd/system/jupyterhub.service
systemctl daemon-reload
systemctl enable jupyterhub.service
systemctl start jupyterhub.service

systemctl status jupyterhub.service

# 2. Conda environments¶
# TODO  : DockerSpawnerを使うので一旦飛ばす

# 3. Setting up a reverse proxy
cat << _EOF_ > /etc/apt/sources.list.d/nginx.list
deb http://nginx.org/packages/ubuntu/ `lsb_release -cs` nginx
deb-src http://nginx.org/packages/ubuntu/ `lsb_release -cs` nginx
_EOF_

wget -P /tmp/ https://nginx.org/keys/nginx_signing.key
apt-key add /tmp/nginx_signing.key
apt-get update
apt-get install -y nginx

cat << '_EOF_' > /etc/nginx/conf.d/jupyterhub.conf
# If Upgrade is empty, Connection = close
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen       80;
    server_name  localhost;

    rewrite ^/signup$ http://$server_name/jupyter/signup permanent;
    rewrite ^/login$ http://$server_name/jupyter/ permanent;

    #charset koi8-r;
    #access_log  /var/log/nginx/host.access.log  main;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    location /jupyter/ {
        # NOTE important to also set base url of jupyterhub to /jupyter in its config
        proxy_pass http://127.0.0.1:8000;

        proxy_redirect   off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # websocket headers
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }

    # proxy the PHP scripts to Apache listening on 127.0.0.1:80
    #
    #location ~ \.php$ {
    #    proxy_pass   http://127.0.0.1;
    #}

    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
    #
    #location ~ \.php$ {
    #    root           html;
    #    fastcgi_pass   127.0.0.1:9000;
    #    fastcgi_index  index.php;
    #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
    #    include        fastcgi_params;
    #}

    # deny access to .htaccess files, if Apache's document root
    # concurs with nginx's one
    #
    #location ~ /\.ht {
    #    deny  all;
    #}
}
_EOF_

PUBLIC_IP=`dig +short myip.opendns.com @resolver1.opendns.com`
sed -ie "s/server_name  localhost;/server_name  $PUBLIC_IP;/g" /etc/nginx/conf.d/jupyterhub.conf

systemctl enable nginx.service
systemctl restart nginx.service

/opt/jupyterhub/bin/python3 -m pip install dockerspawner
git clone https://github.com/jupyterhub/nativeauthenticator.git /tmp/nativeauthenticator
/opt/jupyterhub/bin/python3 -m pip install -e /tmp/nativeauthenticator/
echo "c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'" >> /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py
echo "c.Authenticator.admin_users = {'admin'}" >> /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py

cat << '_EOF_' >> /opt/jupyterhub/etc/jupyterhub/jupyterhub_config.py
c.JupyterHub.spawner_class = 'dockerspawner.DockerSpawner'

notebook_dir = '/home/jovyan/work'
c.DockerSpawner.notebook_dir = notebook_dir
c.DockerSpawner.volumes = { 'jupyterhub-user-{username}': notebook_dir }
c.JupyterHub.hub_ip = '0.0.0.0'
c.DockerSpawner.image = 'jupyterhub/singleuser:1.2'

def pre_spawn_hook(spawner):
    username = spawner.user.name
    try:
        import pwd
        pwd.getpwnam(username)
    except KeyError:
        import subprocess
        subprocess.check_call(['useradd', '-ms', '/bin/bash', username])

c.Spawner.pre_spawn_hook = pre_spawn_hook
_EOF_

systemctl restart jupyterhub.service
# インストールはこれでokのはずだが、sing upとsing inが成功しないなぞ
# base pathが微妙っぽいのでnginxの設定直す

#以下のエラーが起きる
#500 : Internal Server Error
#Error in Authenticator.pre_spawn_start: KeyError "getpwnam(): name not found: 'admin'"
#
#You can try restarting your server from the home page.
#pwdはunixのあれ
#username ubuntuはとおる、やっぱりpamがまだ有効になってる

# FIXME : HTTPでアクセスするときのpathが適切でない
# FIXME : Authenticatorの設定がおかしい
# TODO  : DockerSpawnerの設定をする
# TODO  : DockerSpawnerとストレージの設定をする
