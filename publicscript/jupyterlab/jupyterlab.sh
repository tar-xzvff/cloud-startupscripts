#!/bin/bash

# @sacloud-name "JupyterLab"
# @sacloud-once
#
# @sacloud-require-archive distro-centos distro-ver-7
# @sacloud-require-archive distro-centos distro-ver-8
#
# @sacloud-desc-begin
# pyenv, MinicondaまたはAnaconda,JupyterLabをインストールするスクリプトです。
# このスクリプトは CentOS 7.X, 8.X でのみ動作します。
# サーバ作成後、Webブラウザで以下のURL（サーバのIPアドレスと設定したポート）にアクセスしてください。
# Webブラウザは Google Chrome の利用を推奨します。
#   http://サーバのIPアドレス:設定したポート/
# アクセスした後、設定したJupyterLabのパスワードでログインしてください。
# このスクリプトは完了までに20分程度時間がかかります (推奨プラン 2コア / 4GB選択時)
# @sacloud-desc-end
# @sacloud-password required JP "Jupyterのログインパスワード設定"
# @sacloud-text required default=49152 integer min=49152 max=65534 JPORT "port番号変更(49152以上、65534以下を指定してください)"
# @sacloud-radios-begin default=miniconda3-4.7.12 PYTHON "インストールするPython環境"
#     miniconda3-4.7.12 "miniconda3-4.7.12"
#     anaconda3-2019.10 "anaconda3-2019.10"
# @sacloud-radios-end
# @sacloud-tag @simplemode @logo-alphabet-j @require-core>=2 @require-memory-gib>=4

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
trap '_motd fail' ERR

set -x

# コントロールパネルの入力値を変数へ代入
password=@@@JP@@@
port=@@@JPORT@@@
python_distribution=@@@PYTHON@@@
user="jupyter"
home="/home/$user"

# ユーザーの作成
if ! cat /etc/passwd | awk -F : '{ print $1 }' | egrep ^$user$; then
    adduser $user
fi

echo "[1/5] Pythonのインストールに必要なライブラリをインストール中"
yum clean all
yum update -y || _motd fail
# 推奨ビルド環境のパッケージをインストール https://github.com/pyenv/pyenv/wiki#suggested-build-environment
yum -y install git gcc zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel || _motd fail
echo "[1/5] Pythonのインストールに必要なライブラリをインストールしました"

echo "[2/5] pyenvをインストール中..."
git clone https://github.com/yyuu/pyenv $home/.pyenv || _motd fail
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> $home/.bash_profile
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> $home/.bash_profile
echo 'eval "$(pyenv init --path)"' >> $home/.bash_profile
echo -e 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' >> $home/.bash_profile
chown -R $user:$user $home/.pyenv
echo "[2/5] pyenvをインストールしました"

if [ ${python_distribution} = "anaconda3-2019.10" ]; then
echo "[3/5] Anaconda,chainerのインストール中..."
#Anaconda3系
# anacondaのインストールは時間がかかるためtimeoutを設定する (15分)
timeout 900 su -l $user -c "yes | pyenv install anaconda3-2019.10" || _motd fail
su -l $user -c "pyenv global anaconda3-2019.10"
su -l $user -c "pyenv rehash"
su -l $user -c "yes | conda create --name py3.7 python=3.7 anaconda" || _motd fail
cat << EOF > /tmp/ana3.sh
source /home/$user/.pyenv/versions/anaconda3-2019.10/bin/activate py3.7
conda install -c conda-forge jupyterlab ipykernel
jupyter kernelspec install-self --user
pip install chainer
EOF
chmod 755 /tmp/ana3.sh
su -l $user -c "/bin/bash /tmp/ana3.sh" || _motd fail

elif [ ${python_distribution} = "miniconda3-4.7.12" ]; then
echo "[3/5] Miniconda,chainerのインストール中..."
#Miniconda3系
su -l $user -c "yes | pyenv install miniconda3-4.7.12" || _motd fail
su -l $user -c "pyenv global miniconda3-4.7.12"
su -l $user -c "pyenv rehash"
#Anacondaリポジトリ(defaults)を参照しないようにする
su -l $user -c "conda config --remove channels defaults"
su -l $user -c "conda config --append channels conda-forge"

su -l $user -c "yes | conda create --name py3.7 python=3.7" || _motd fail
cat << EOF > /tmp/miniconda3.sh
source /home/$user/.pyenv/versions/miniconda3-4.7.12/bin/activate py3.7
conda install jupyterlab ipykernel
jupyter kernelspec install-self --user
pip install chainer
EOF
chmod 755 /tmp/miniconda3.sh
su -l $user -c "/bin/bash /tmp/miniconda3.sh" || _motd fail

else
echo 'error' && exit 1 || _motd fail
fi

echo "[4/5] 設定ポートの解放中..."
firewall-cmd --add-port=$port/tcp --zone=public --permanent
firewall-cmd --reload
echo "[4/5] 設定ポートを解放しました"

echo "[5/5] Jupyterの実行中..."
if [ ${python_distribution} = "miniconda3-4.7.12" ]; then
su -l $user -c "pyenv global miniconda3-4.7.12/envs/py3.7"
fi
su -l $user -c "jupyter notebook --generate-config"
hashedp=`su -l $user -c "python -c 'from notebook.auth import passwd; print(passwd(\"${password}\",\"sha256\"))'"`
echo "c.NotebookApp.password = '$hashedp'" >> $home/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.port = $port" >> $home/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.open_browser = False" >> $home/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.ip = '*'" >> $home/.jupyter/jupyter_notebook_config.py
echo "c.InlineBackend.rc = {
    'font.family': 'meiryo',
}"
echo "c.NotebookApp.notebook_dir = '$home'" >> $home/.jupyter/jupyter_notebook_config.py

cat << EOF > /etc/systemd/system/jupyter.service
[Unit]
Description = jupyter daemon

[Service]
ExecStart = /home/$user/.pyenv/shims/jupyter lab --ip=0.0.0.0
Restart = always
Type = simple
User = $user

[Install]
WantedBy = multi-user.target
EOF

systemctl enable jupyter
systemctl start jupyter
echo "[5/5] Jupyterの実行しました"
echo "スタートアップスクリプトの処理が完了しました"

_motd end
