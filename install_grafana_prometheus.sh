#!/bin/bash

# Скрипт был протестирован на этих версиях.
# При наличии релиза с новой версией (кроме патча), получим предупреждение
GRAFANA_VER=11.3.0
PROMETHEUS_VER=2.55.0

if [[ $EUID -ne 0 ]]; then
   echo "Формат запуска скрипта: sudo ./setup_monitoring.sh"
   exit 1
fi

if which "grafana-server" &> /dev/null || which "prometheus" &> /dev/null; then
  echo "Скриптом нельзя пользоваться, если на сервере уже установлены либо Grafana, либо Prometheus."
  exit 1
fi

version=$(lsb_release -r | awk '{print $2}' | cut -d. -f1)
if [ "$version" -ne 22 ] && [ "$version" -ne 20 ]; then
    echo "Скрипт работает только под Ubuntu 20.x и 22.x. Завершаем работу."
    exit 1
fi

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
  old_version_found=false
  if (( latest_major > script_major )); then
    old_version_found=true
    echo -e "\033[0;33mПредупреждение: Версия $app_name (${latest_major}.${latest_minor}.${latest_patch}) выше, чем версия, под которую написан скрипт (${script_version}).\033[0m"
    echo "Рекомендуется связаться с разработчиком (можно оставить комментарий к инструкции на ютубе). А можете продолжить, но скрипт не тестировался на этой версии..."
    read -p "Продолжить? (y/n): " choice
    if ! [[ "$choice" =~ ^[Yy]$ ]]; then
      echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
      exit 0
    fi
  fi
  eval "$variable_name=${latest_major}.${latest_minor}.${latest_patch}"
}

reboot_countdown() {
  local seconds=$1
  while [ $seconds -gt 0 ]; do
    echo -ne "Система перезагрузится через \033[0;33m${seconds}\033[0m секунд...Enter - перезагрузка\r"
    read -t 1 -n 1 input
    if [ $? -eq 0 ]; then
      echo -e "\nПерезагрузка системы...\n"
      shutdown -r now
      exit 0
    fi
    ((seconds--))
  done
  echo -e "\nПерезагрузка системы...\n"
  sudo shutdown -r now
}

run_sed() {
    local search_pattern="$1"
    local file="$2"
    local grep_pattern=$(echo "$search_pattern" | sed 's/^\/\^\[\[\:space\:]]\*//' | sed 's/\/d$//')
    if grep -q "${grep_pattern}" "$file"; then
        sed -i "$search_pattern" "$file"
    else
        error_flag=true
    fi
}

echo -ne "\nАнализируем актуальные версии Grafana & Prometheus..."
compare_version $PROMETHEUS_VER "Prometheus" "https://github.com/prometheus/prometheus/releases" PROMETHEUS_VER
compare_version $GRAFANA_VER "Grafana" "https://github.com/grafana/grafana/releases" GRAFANA_VER
if [ "$old_version_found" = true ]; then
    echo -e "\033[0;32m  [ OK ]\033[0m\n"
fi

echo -e "\n############################################################################\n"
echo "Этот скрипт установит на сервер системы мониторинга: Grafana & Prometheus"
echo "Grafana: $GRAFANA_VER"
echo "Prometheus: $PROMETHEUS_VER"
echo
echo "Если в процессе установки появится вопрос \"Which services should be restarted?\", то просто нажмите Enter."
echo
echo -e "\n############################################################################\n"

echo -e "Проверяются доступные обновления пакетов системы... Ожидайте..."
update_output=$(sudo apt update 2>&1)
if echo "$update_output" | grep -q "packages can be upgraded"; then
  echo -e "\033[0;31mПакеты Ubuntu не обновлены.\033[0m\n"
  echo "Для работы скрипта нужно выполнить обновление системы."
  read -p "Продолжить? (y/n): " choice
  if ! [[ "$choice" =~ ^[Yy]$ ]]; then
    echo -e "Скрипт завершает работу. Изменения в систему не вносились.\n"
    exit 0
  fi
  apt upgrade -y
  echo -e "\n\033[0;32mСистема обновлена!\033[0m\n"
  if [ -f /var/run/reboot-required ]; then
    echo -e "\n\033[0;33mТребуется перезагрузка.\033[0m\n"
    echo -e "\n\033[1;31mПосле перезагрузки ЗАПУСТИТЕ СКРИПТ ЕЩЕ РАЗ.\033[0m\n"
    reboot_countdown 20
  fi
fi

echo -ne "\nУстанавливаем необходимые утилиты..."
touch /var/log/auth.log > /dev/null
apt install iptables adduser libfontconfig1 musl tmux htop curl -y > /dev/null 2>&1
apt install fail2ban apt-transport-https software-properties-common wget -y > /dev/null 2>&1
config_file_base="/etc/fail2ban/jail.conf"
config_file="/etc/fail2ban/jail.local"
error_flag=false
if [ -f "$config_file_base" ]; then
    cp $config_file_base $config_file
    run_sed '/^[[:space:]]*findtime  = 10m/d' "$config_file"
    run_sed '/^[[:space:]]*maxretry = 5/d' "$config_file"
    run_sed '/^[[:space:]]*bantime  = 10m/d' "$config_file"
    run_sed '/^[[:space:]]*bantime\.increment =/d' "$config_file"
    run_sed '/^[[:space:]]*bantime\.rndtime =/d' "$config_file"
    run_sed '/^[[:space:]]*bantime\.factor =/d' "$config_file"
    run_sed '/^[[:space:]]*bantime\.formula =/d' "$config_file"
    if [ "$error_flag" = true ]; then
      echo -e "\r\nВерсия fail2ban не соответствует версии, под которую написан скрипт."
      echo "Используем стандартные настройки."
      echo -e "Пожалуйста, свяжитесь с разработчиком (можно оставить комментарий к инструкции на ютубе)\n"
      cp $config_file_base $config_file
    else
      sed -i '/^\[DEFAULT\]/a findtime = 30m\nmaxretry = 3\nbantime = 60m\nbantime.increment = true\nbantime.rndtime = 60\nbantime.factor = 2\nbantime.formula = ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)' "$config_file"
      systemctl restart fail2ban
    fi
else
    error_flag=true
    echo "Установка fail2ban выполнена с ошибками."
    echo -e "Пожалуйста, свяжитесь с разработчиком (можно оставить комментарий к инструкции на ютубе)"
fi
if [ "$error_flag" = false ]; then
    echo -e "\033[0;32m  [ OK ]\033[0m\n"
fi

echo -ne "Устанавливаем Grafana..."
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /dev/null | sudo tee -a /etc/apt/sources.list.d/grafana.list
apt-get update > /dev/null 2>&1
cd ~
wget https://dl.grafana.com/oss/release/grafana_${GRAFANA_VER}_amd64.deb > /dev/null 2>&1
dpkg -i grafana_${GRAFANA_VER}_amd64.deb > /dev/null 2>&1
echo "export PATH=/usr/share/grafana/bin:$PATH" >> /etc/profile
rm ~/grafana*
echo -e "\033[0;32m  [ OK ]\033[0m\n"

cat <<EOF> /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

echo -ne "Устанавливаем Prometheus..."
mkdir -p /tmp/prometheus
cd /tmp/prometheus
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VER}/prometheus-${PROMETHEUS_VER}.linux-amd64.tar.gz > /dev/null 2>&1
tar xvfz prometheus-${PROMETHEUS_VER}.linux-amd64.tar.gz > /dev/null 2>&1
cd prometheus-${PROMETHEUS_VER}.linux-amd64
mv prometheus /usr/bin/
rm -rf /tmp/prometheus*
mkdir -p /etc/prometheus/data

cat <<EOF> /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF

useradd -rs /bin/false prometheus 2>/dev/null
for path in /usr/bin/prometheus /etc/prometheus /etc/prometheus/prometheus.yml /etc/prometheus/data; do
  chown prometheus:prometheus $path
done

cat <<EOF> /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Restart=on-failure
ExecStart=/usr/bin/prometheus \
  --config.file       /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /etc/prometheus/data

[Install]
WantedBy=multi-user.target
EOF
echo -e "\033[0;32m  [ OK ]\033[0m\n"

echo -ne "Применяем настройки Firewall..."
iptables -P INPUT ACCEPT
iptables -F
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -P INPUT DROP
mkdir -p /etc/iptables/
iptables-save > /etc/iptables/rules.v4
cd /
echo "iptables-restore < /etc/iptables/rules.v4" >> /etc/profile
echo -e "\033[0;32m  [ OK ]\033[0m\n"
systemctl daemon-reload > /dev/null 2>&1
systemctl enable prometheus > /dev/null 2>&1
systemctl start prometheus > /dev/null 2>&1
systemctl enable grafana-server > /dev/null 2>&1
systemctl start grafana-server > /dev/null 2>&1
if systemctl is-active --quiet prometheus; then
  echo -e "\n\033[0;32mPrometheus is active!\033[0m"
else
  echo -e "\033[0;31mPrometheus is NOT active!\033[0m"
fi
if systemctl is-active --quiet grafana-server; then
  echo -e "\033[0;32mGrafana is active!\033[0m"
else
  echo -e "\033[0;31mGrafana is NOT active!\033[0m"
fi
echo -e "Скрипт завершил работу.\n"
