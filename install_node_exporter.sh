#!/bin/bash

# Скрипт был протестирован на этой версии.
# При наличии релиза с новой версией (кроме патча), получим предупреждение
NODE_EXPORTER_VER="1.8.2"

if [[ $EUID -ne 0 ]]; then
  echo "Скрипт необходимо запускать с правами суперпользователя"
  exit 1
fi

version=$(lsb_release -r | awk '{print $2}' | cut -d. -f1)
if [ "$version" -ne 22 ] && [ "$version" -ne 20 ]; then
    echo "Скрипт работает только под Ubuntu 20.x и 22.x. Завершаем работу."
    exit 1
fi

if [ "$#" -eq 1 ]; then
  ip_monitoring="$1"
  if ! [[ $ip_monitoring =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo -e "\nОшибка: неверный формат IP-адреса $ip_monitoring.\n"
      exit 1
  fi
fi

setup_firewall() {
  local ip_mon="$1"
  if ! [[ $ip_mon =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo -e "\nОшибка: неверный формат IP-адреса $ip_monitoring.\n"
      echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
      exit 1
  fi
  apt install iptables netfilter-persistent -y > /dev/null 2>&1
  iptables -A INPUT -s $ip_monitoring -p tcp --dport 9100 -j ACCEPT
  iptables -A INPUT -p tcp --dport 9100 -j DROP
  echo -e "\nПрименены настройки Firewall.\n"
}

compare_version() {
  local script_version="$1"
  local app_name="$2"
  local url="$3"
  local variable_name="$4"
  script_major=$(echo "$script_version" | cut -d '.' -f 1)
  script_minor=$(echo "$script_version" | cut -d '.' -f 2)
  latest_version=$(curl -s "$url" | grep -Eo '/tag/v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z]+[0-9.]*)?' | grep -vE '\-(alpha|beta|rc)[0-9.]*' | head -n 1 | sed -E 's/.*\/tag\/v([0-9]+)\.([0-9]+)\.([0-9]+).*/\1 \2 \3/')
  latest_major=$(echo $latest_version | cut -d ' ' -f 1)
  latest_minor=$(echo $latest_version | cut -d ' ' -f 2)
  latest_patch=$(echo $latest_version | cut -d ' ' -f 3)
  if (( latest_major > script_major )) || \
     (( latest_major == script_major && latest_minor > script_minor )); then
    echo -e "\033[0;33mПредупреждение: Версия $app_name (${latest_major}.${latest_minor}.${latest_patch}) выше, чем версия, под которую написан скрипт (${script_version}).\033[0m"
    echo "Свяжитесь с разрботчиком (TG: Karaev_Alexey, тема: 'Simple monitoring scripts') или продолжайте на свой страх и риск."
    read -p "Продолжить? (y/n): " choice
    if ! [[ "$choice" =~ ^[Yy]$ ]]; then
      echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
      exit 0
    fi
  fi
  eval "$variable_name=${latest_major}.${latest_minor}.${latest_patch}"
}

if which "node_exporter" &> /dev/null; then
  echo -e "\nNode Exporter уже установлен на сервере."
  if iptables -L | grep -q 9100; then
    echo "Firewall тоже настроен."
    echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
    exit 0
  fi
  if [ ! -z "${ip_monitoring+x}" ]; then
    setup_firewall $ip_monitoring
    exit 0
  fi
  read -p "Настроить Firewall? Вам понадобится IP-адрес вашего сервера с Prometheus (y/n): " choice
  if ! [[ "$choice" =~ ^[Yy]$ ]]; then
    echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
    exit 0
  fi
  read -p "Введите IP-адрес вашего сервера для мониторинга: " ip_monitoring
  setup_firewall $ip_monitoring
  exit 0
fi

echo -ne "\nАнализируем актуальную версию Node Exporter..."
compare_version $NODE_EXPORTER_VER "Node Exporter" "https://github.com/prometheus/node_exporter/releases" NODE_EXPORTER_VER
if ! [[ "$choice" =~ ^[YyNn]$ ]]; then
  echo -e "\033[0;32m  [ OK ]\033[0m\n"
fi

mkdir -p /tmp/node_exporter
cd /tmp/node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz > /dev/null 2>&1
tar xvfz node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz > /dev/null 2>&1
cd node_exporter-${NODE_EXPORTER_VER}.linux-amd64
mv node_exporter /usr/bin/
cd ~
rm -rf /tmp/node_exporter*

useradd -rs /bin/false node_exporter > /dev/null 2>&1
chown node_exporter:node_exporter /usr/bin/node_exporter

cat <<EOF> /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Restart=on-failure
ExecStart=/usr/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start node_exporter > /dev/null 2>&1
systemctl enable node_exporter > /dev/null 2>&1

if [ ! -z "${ip_monitoring+x}" ]; then
  setup_firewall $ip_monitoring
fi

if systemctl is-active --quiet node_exporter; then
  echo -e "\033[0;32mNode Exporter is active!\033[0m"
else
  echo -e "\033[0;31mNode Exporter is NOT active!\033[0m"
fi

echo -e "Скрипт завершил работу!\n"
