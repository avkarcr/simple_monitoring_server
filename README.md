# Simple Monitoring Server

Этот проект создан для простой установки и настройки Prometheus и Grafana на отдельном сервере для мониторинга (нужен новый, чистый сервер).
Скрипты в репозитории помогут вам пошагово установить и настроить Prometheus, Grafana (на сервер для мониторинга), а также Node Exporter на каждый сервер, который вы хотите мониторить.

## Начало работы

### Предварительные требования
- **Сервер для мониторинга с ОС Ubuntu 20/22** для установки Grafana и Prometheus.
- **Сервер, который вы хотите мониторить с ОС Ubuntu 20/22** для установки Node Exporter.

### Файлы в репозитории

1. **`install_grafana_prometheus.sh`**: Устанавливает и настраивает Grafana и Prometheus на сервер для мониторинга.
2. **`add_remove_node_exporter.sh`**: Добавляет и удаляет из файлов конфигурации Prometheus IP-адреса серверов, которые мы хотим мониторить, с установленным на них Node Exporter.
3. **`install_node_exporter.sh`**: Устанавливает Node Exporter на каждый сервер, который мы хотим мониторить.

### Установка

1. **Видеоинструкция**
  Наглядная инструкция по установке и настройке скриптов представлена в [плейлисте на YouTube](https://youtu.be/FIa2ohM3WXY?si=BfSI23gwLn7zmJtY). В этом плейлисте содержатся пошаговые инструкции и комментарии к каждому этапу установки.
  Если будут вопросы, то можете оставлять комментарии под видео.


2. **Скачайте скрипты на сервер для мониторинга**
  ```bash
  wget https://github.com/avkarcr/simple_monitoring_server/raw/main/install_grafana_prometheus.sh
  wget https://github.com/avkarcr/simple_monitoring_server/raw/main/add_remove_node_exporter.sh
  ```   

3. **Установите Grafana и Prometheus**
  Запустите скрипт для установки и настройки Grafana и Prometheus. Следуйте инструкциямЕ, которые будут на экране:
  ```bash
  chmod +x install_grafana_prometheus.sh add_remove_node_exporter.sh
  ./install_grafana_prometheus.sh
  ```   

4. **Настройте Grafana по видеоинструкции**
  Ссылка плейлист указана выше. Вам нужно первое видео, которое отмечено, как "ПРАКТИКА".

5. **Установите Node Exporter на те серверы, которые вы хотите мониторить**
  На каждом сервере, который вы хотите мониторить запутите следующий скрипт:
  ```bash
  wget https://github.com/avkarcr/simple_monitoring_server/raw/main/install_node_exporter.sh
  chmod +x install_node_exporter.sh
  ./install_node_exporter.sh
  ```   

6. **Изменение списка серверов, которые надо мониторить**
  Если вам понадится удалить или добавить новый сервер, просто повторно запустите скрипт и следуйте инструкциям на экране.
  ```bash
  ./add_remove_node_exporter.sh
  ```

7. **Бонус. Как мониторить работу программы, которая работает на сервере?**
  Тут Node Exporter не поможет, надо использовать другие инструменты.
  Если сервер работает хорошо и ошибок не видно, но вот нода, запущенная на сервере иногда отваливается. Как получить уведомление об этом в ваш телеграм?

**Раздел пока в разработке. Ждет ваших звездочек на [репозитории гитхаба](https://github.com/avkarcr/simple_monitoring_server) и лайков на [YouTube](https://youtu.be/FIa2ohM3WXY?si=BfSI23gwLn7zmJtY), чтобы я понял, что этот раздел нужен.**
