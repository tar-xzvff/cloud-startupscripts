#!/bin/bash
#
# @sacloud-name "Nextcloud"
# @sacloud-once
# @sacloud-desc-begin
# このスクリプトは Nextcloud をセットアップします
# (CentOS7.X でのみ動作します)
# サーバ作成後はブラウザより「http://サーバのIPアドレス/nextcloud/」でアクセスすることができます
# @sacloud-desc-end
# @sacloud-require-archive distro-centos distro-ver-7
# @sacloud-text required shellarg maxlen=100 nc_username "管理者ユーザ名"
# @sacloud-password required shellarg maxlen=100 nc_password "管理者パスワード"
# @sacloud-checkbox libreoffice_online_enabled "LibreOffice Onlineを有効にする"

_motd() {
	LOG=$(ls /root/.sacloud-api/notes/*log)
	case $1 in
	start)
		echo -e "\n#-- Startup-script is \\033[0;32mrunning\\033[0;39m. --#\n\nPlease check the log file: ${LOG}\n" > /etc/motd
	;;
	fail)
		echo -e "\n#-- Startup-script \\033[0;31mfailed\\033[0;39m. --#\n\nPlease check the log file: ${LOG}\n" > /etc/motd
		exit 1
	;;
	end)
		cp -f /dev/null /etc/motd
	;;
	esac
}

_motd start
set -ex
trap '_motd fail' ERR

LIBREOFFICE_ONLINE_ENABLED=@@@libreoffice_online_enabled@@@
GLOBAL_IP=`curl inet-ip.info`

# 必要パッケージのインストール
yum update -y
yum install -y epel-release
rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-7.rpm
yum install -y httpd php72-php php72-php-{gd,mbstring,mysqlnd,ldap,posix,xml,zip,intl,mcrypt,smbclient,ftp,imap,gmp,apcu,redis,memcached,imagick}

sed -i 's/^;date.timezone =/date.timezone = Asia\/Tokyo/' /etc/opt/remi/php72/php.ini

cd /var/www/html
git clone https://github.com/nextcloud/server.git nextcloud
cd nextcloud
VERSION=$(git tag | egrep -iv "rc|beta" | sed 's/^v//' | sort -n | tail -1)
git checkout v${VERSION}
git submodule update --init
chown -R apache. /var/www/html/nextcloud/

# apacheの設定
cat > /etc/httpd/conf.d/nextcloud.conf <<'_EOF_'
<Directory "/var/www/html/nextcloud">
  Require all granted
  Options FollowSymlinks MultiViews
  AllowOverride All
</Directory>
_EOF_

systemctl enable httpd
systemctl start httpd

# Nextcloudの自動インストール
sudo -u apache php72 /var/www/html/nextcloud/occ maintenance:install --admin-user @@@nc_username@@@ --admin-pass @@@nc_password@@@
# 信頼できるドメインの設定 0はlocalhostであるため1にグローバルIPを設定する
sudo -u apache php72 /var/www/html/nextcloud/occ config:system:set trusted_domains 1 --value=${GLOBAL_IP}

# LibreOffice Onlineを有効にする
if [[ -n "$LIBREOFFICE_ONLINE_ENABLED" ]]; then
# dockerとdocker-composeのインストール
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager -y --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# LibreOffice Onlineを展開
cd ~/
git clone https://github.com/smehrbrodt/nextcloud-libreoffice-online.git
cd nextcloud-libreoffice-online/libreoffice-online/
cat << EOF > /root/nextcloud-libreoffice-online/libreoffice-online/.env
NEXTCLOUD_DOMAIN=${GLOBAL_IP}
LO_ONLINE_USERNAME=@@@nc_username@@@
LO_ONLINE_PASSWORD=@@@nc_password@@@
LO_ONLINE_EXTRA_PARAMS=--o:ssl.enable=false
EOF

docker-compose up -d

# Collabora Onlineのインストール設定
sudo -u apache php72 /var/www/html/nextcloud/occ app:install richdocuments
# LibreOffice Onlineのアドレスを指定
sudo -u apache php72 /var/www/html/nextcloud/occ config:app:set richdocuments wopi_url --value=http:\/\/${GLOBAL_IP}:9980
# SSLを使わないため証明書の検証を無効にする
sudo -u apache php72 /var/www/html/nextcloud/occ config:app:set richdocuments disable_certificate_verification --value=yes
sudo -u apache php72 /var/www/html/nextcloud/occ app:enable richdocuments

# Firewall の設定
firewall-cmd --permanent --add-port=9980/tcp
fi


# Firewall の設定
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --reload

shutdown -r 1

_motd end
