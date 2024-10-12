#!/bin/bash

PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
JOB_NAME="prometheus"
PORT=9100

if [[ $EUID -ne 0 ]]; then
   echo -e "\nСкрипт необходимо запускать с правами суперпользователя.\n"
   exit 1
fi

if ! which "prometheus" &> /dev/null; then
  echo -e "\nPrometheus не установлен на сервере. Завершаем работу.\n"
  exit 1
fi

if [ ! -s "$PROMETHEUS_CONFIG" ]; then
    echo -e "\nОшибка! Отсутствует файл конфигурации Prometheus: ${PROMETHEUS_CONFIG}.\n"
    exit 1
fi

validate_ip() {
    local ip_list=("$@")
    for ip in "${ip_list[@]}"; do
        if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo -e "\nОшибка: неверный формат IP-адреса $ip.\n"
            exit 1
        fi
    done
}

add_ips() {
  current_targets=$(grep -Po '(?<=targets: \[)[^]]*' "$PROMETHEUS_CONFIG")
  added=0
  for node_ip in "$@"; do
      if [[ -z $node_ip ]]; then
          continue
      fi
      if echo "$current_targets" | grep -q "$node_ip"; then
          echo -e "\nАдрес $node_ip уже есть в конфигурации."
      else
          current_targets="$current_targets, \"$node_ip:$PORT\""
          echo -e "\nАдрес $node_ip добавлен."
          result=true
      fi
  done
  sed -i "s/targets: \[.*/targets: \[$current_targets\]/" "$PROMETHEUS_CONFIG"
}

remove_ips() {
    echo -e "\nТекущие IP-адреса в job=prometheus:"
    current_targets=$(grep -Po '(?<=targets: \[)[^]]*' "$PROMETHEUS_CONFIG" | tr ',' '\n' | sed 's/"//g' | grep -v "localhost:$PORT")
    if [[ -z "$current_targets" ]]; then
        echo -e "\nНет IP-адресов для удаления, кроме localhost."
        return
    fi

    i=1
    declare -A ip_map
    while read -r ip; do
      echo "$i) $ip"
      ip_map[$i]=$ip
      ((i++))
    done <<< "$current_targets"

    echo -e "\nВведите номер для удаления, 'all' для удаления всех адресов или Enter для выхода:"
    read -r ip_choice
    if [[ -z "$ip_choice" ]]; then
        echo -e "Выход без изменений.\n"
        exit 0
    fi
    if [ "$ip_choice" == "all" ]; then
        sed -i "/targets: \[/c\ \ \ \ \ \ \ \ targets: [\"localhost:9090\"]" "$PROMETHEUS_CONFIG"
        echo -e "\nВсе IP-адреса удалены (кроме localhost:9090)."
        result=true
    elif [[ ${ip_map[$ip_choice]+_} ]]; then
        ip_to_remove=${ip_map[$ip_choice]}
        sed -i "/targets: \[/s/\"$ip_to_remove\", //g" "$PROMETHEUS_CONFIG"
        sed -i "/targets: \[/s/, \"$ip_to_remove\"//g" "$PROMETHEUS_CONFIG"
        echo -e "\nАдрес $ip_to_remove удалён."
        result=true
    else
        echo -e "\nНеверный выбор."
    fi
}

print_help() {
  echo -e "\n\033[1;32m========================================================================================\033[0m"
  echo -e "\n\033[1;32mДанный скрипт предназначен для добавления/удаления IP-адреса node_exporter в Prometheus\033[0m\n"
  echo -e "\033[1;34mИспользование:\033[0m"
  echo -e "  \033[1;33mЗапуск без параметров - \033[0mКраткая справка по использованию"
  echo -e "  \033[1;33mЗапуск с параметром remove - \033[0mУдаление IP-адреса (интерактивный режим)"
  echo -e "  \033[1;33mПараметр - имя файла со списком IP - \033[0mДобавление IP-адресов"
  echo -e "  \033[1;33mПараметры - IP-адреса (через пробел) - \033[0mДобавление IP-адресов"
  echo -e "\n\033[1;34mПараметры:\033[0m"
  echo -e "  \033[1;36mfile\033[0m       - Файл со списком IP-адресов для добавления"
  echo -e "  \033[1;36mIP1 IP2...\033[0m - IP-адреса для добавления вручную"
  echo -e "\n\033[1;34mПримеры использования:\033[0m"
  echo -e "  \033[1;35m./prometheus_add_remove_exporter.sh remove\033[0m    - Интерактивное меню по удалению IP-адреса"
  echo -e "  \033[1;35m./prometheus_add_remove_exporter.sh nodes.txt\033[0m    - Добавление IP из файла nodes.txt"
  echo -e "  \033[1;35m./prometheus_add_remove_exporter.sh 1.1.1.1 2.2.2.2\033[0m - Добавление IP 1.1.1.1 и 2.2.2.2"
  echo -e "  \033[1;35m./prometheus_add_remove_exporter.sh 3.3.3.3\033[0m - Добавление IP 3.3.3.3"
  echo -e "\n\033[1;32m========================================================================================\033[0m"
}

result=false
if [ $# -eq 0 ]; then
    print_help
    exit 0
elif [[ $1 == 'remove' ]]; then
  remove_ips
else
    if [ -f "$1" ]; then
        NODES_FILE="$1"
        if [ ! -s "$NODES_FILE" ]; then
            echo "\nОшибка: файл $NODES_FILE пуст или не существует.\n"
            exit 1
        fi
        IP_LIST=($(cat "$NODES_FILE"))
    else
        IP_LIST=("$@")
    fi
    validate_ip "${IP_LIST[@]}"
    add_ips "${IP_LIST[@]}"
fi

if [ "$result" == "true" ]; then
    systemctl restart prometheus >/dev/null 2>&1
fi

echo -e "\nСкрипт завершил работу.\n"
