# mochawrt ☕

Лёгкая, красивая веб-панель для роутеров на OpenWrt — и, главное, для **vendor-форков OpenWrt от Xiaomi** (Qualcomm IPQ WiFi-7 и ко.), где штатный MiWiFi-интерфейс убогий, а поставить LuCI в read-only squashfs нельзя.

Тема — **[Catppuccin Mocha](https://catppuccin.com/)**. Ставится **без записи в squashfs**: файлы кладутся в writable-каталог, страница подключается к `uhttpd` через UCI. Никаких зависимостей кроме `uhttpd` (он уже есть) и busybox.

> Это панель **мониторинга и управления** (дашборд, сеть, Wi-Fi, клиенты, DNS/DPI, сервисы), а не замена всей прошивки. Дополняет [open-routerich](https://github.com/Sigmachan/open-routerich).

---

## Что умеет

- **Дашборд**: гейджи CPU/RAM, температура, аптайм, **живой график трафика** (canvas, без внешних либ).
- **Сеть**: шлюз, DNS, WAN/LAN, таблица интерфейсов (IP/MAC/состояние/RX/TX).
- **Wi-Fi**: SSID, канал, режим, число клиентов на радио.
- **Клиенты**: активные DHCP-аренды (имя/IP/MAC/срок).
- **DNS & DPI**: статус [open-routerich](https://github.com/Sigmachan/open-routerich) (youtubeUnblock / редирект / QUIC).
- **Система**: модель, SoC, профиль совместимости, прошивка, ядро; рестарт сервисов, Wi-Fi вкл/выкл, перезагрузка.

Всё на чистом busybox-`sh` + `/proc` + `ubus`/`uci` с фоллбэками — работает даже там, где нет `ubus`/`iwinfo`.

---

## Прослойка совместимости (Xiaomi и не только)

`lib/compat.sh` определяет устройство и прячет различия за единым API (термодатчик, имена Wi-Fi-интерфейсов, WAN/LAN, наличие ubus/iwinfo, vendor/immutable). Профили:

| Профиль | Устройства | Заметки |
|---|---|---|
| `xiaomi-ipq-wifi7` | IPQ5424 (RDP466), IPQ9554 / **BE7000** | vendor 18.06-форк, read-only root |
| `xiaomi-ipq` | **AX9000** (IPQ807x), AX6/AX6S (IPQ60xx) | |
| `xiaomi-filogic` | **AX3000T**, BE3600/BE5000, mt7981/7986 | |
| `xiaomi-generic` | прочие Xiaomi/Redmi/Mi, Routerich | эвристика по модели |
| `generic` | любой другой OpenWrt | SoC из `/proc/cpuinfo` |

Новое устройство добавляется одной строкой `case` в `compat.sh` — панель сразу его поддержит.

---

## Установка

На роутере по SSH (root):

```sh
wget -O - https://raw.githubusercontent.com/Sigmachan/mochawrt/main/install.sh | sh
# затем открой http://<ip-роутера>:8090/
```

Свой порт/каталог:

```sh
sh install.sh --port 8090 --dest /opt/mochawrt
```

Удаление:

```sh
sh /opt/mochawrt/uninstall.sh        # или /data/mochawrt, /root/mochawrt
```

Каталог выбирается автоматически из writable: `/opt` (Entware) → `/data` (ubifs) → `/root`. **squashfs `/` не трогается.**

> Панель крутит CGI под root **без авторизации** — держи её только в LAN (дефолтный фаервол OpenWrt блокирует WAN-порты). Хочешь наружу — ставь reverse-proxy с авторизацией.

---

## Структура

```
www/index.html            SPA (Catppuccin Mocha, vanilla JS, canvas-график)
www/cgi-bin/mochawrt       CGI JSON-API (sh): sys/cpu/net/wifi/clients/traffic/dpi/action
lib/compat.sh              прослойка совместимости устройств
install.sh / uninstall.sh  подключение к uhttpd через UCI (immutable-safe)
```

## API (для любопытных)

`GET cgi-bin/mochawrt?e=<sys|cpu|net|wifi|clients|traffic|dpi>` → JSON.
`POST cgi-bin/mochawrt?e=action` с `do=reboot|wifi_on|wifi_off|svc_restart&name=<svc>`.

---

## Кредиты

- [Catppuccin](https://github.com/catppuccin) — палитра Mocha
- [open-routerich](https://github.com/Sigmachan/open-routerich) — обход DPI (интеграция)

MIT © Sigmachan
