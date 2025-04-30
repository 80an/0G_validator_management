#!/bin/bash

# === Цвета для ошибок в терминале (используется только при отладке) ===
B_RED="\e[31m"
NO_COLOR="\e[0m"

# === Загрузка переменных окружения из ~/.validator_config/env ===
ENV_FILE="$HOME/.validator_config/env"
if [ -f "$ENV_FILE" ]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo -e "${B_RED}❌ Не найден файл с переменными: $ENV_FILE${NO_COLOR}"
  exit 1
fi

# === Проверка обязательных переменных ===
if [ -z "$VALIDATOR_ADDRESS" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo -e "${B_RED}❌ Не все обязательные переменные заданы в $ENV_FILE${NO_COLOR}"
  exit 1
fi

# === Определение локального RPC-порта из config.toml ===
PROJECT_DIR=".0gchain"
RPC_PORT=$(grep -m 1 -oP '^laddr = "\K[^"]+' "$HOME/$PROJECT_DIR/config/config.toml" | cut -d ':' -f 3)
LOCAL_RPC="http://localhost:$RPC_PORT"

# === Список удалённых RPC — сначала noders, затем itrocket ===
REMOTE_RPC_1="https://og-t-rpc.noders.services"
REMOTE_RPC_2="https://og-testnet-rpc.itrocket.net"

# === Функция выбора рабочего RPC (возвращает первый, который отвечает) ===
select_working_rpc() {
  for url in "$REMOTE_RPC_1" "$REMOTE_RPC_2"; do
    if curl -s --max-time 3 "$url/status" | grep -q '"latest_block_height"'; then
      echo "$url"
      return
    fi
  done
  echo ""
}

# === Выбор рабочего удалённого RPC ===
REMOTE_RPC=$(select_working_rpc)
if [ -z "$REMOTE_RPC" ]; then
  # Если ни один RPC не отвечает — отправка сообщения и выход
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
       -d chat_id="$TELEGRAM_CHAT_ID" \
       -d parse_mode="HTML" \
       -d text="❌ Нет доступного RPC. Мониторинг не запущен." > /dev/null
  exit 1
else
  # Уведомление об использовании конкретного RPC
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
       -d chat_id="$TELEGRAM_CHAT_ID" \
       -d parse_mode="HTML" \
       -d text="📡 Используется RPC: <code>$REMOTE_RPC</code>" > /dev/null
fi

# === Универсальная функция отправки сообщений в Telegram ===
send_telegram_alert() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
       -d chat_id="$TELEGRAM_CHAT_ID" \
       -d parse_mode="HTML" \
       -d text="$message" > /dev/null
}

# === Функции получения данных о валидаторе ===
get_stake() {
  0gchaind q staking validator "$VALIDATOR_ADDRESS" --output json | jq -r '.tokens | tonumber'
}

get_missed_blocks() {
  0gchaind q slashing signing-info $(0gchaind tendermint show-validator) --output json | jq -r '.missed_blocks_counter'
}

get_jailed_status() {
  0gchaind q staking validator "$VALIDATOR_ADDRESS" --output json | jq -r '.jailed'
}

# === Получение высот из локального и удалённого RPC ===
get_local_height() {
  curl -s "$LOCAL_RPC/status" | jq -r '.result.sync_info.latest_block_height'
}

get_remote_height() {
  curl -s "$REMOTE_RPC/status" | jq -r '.result.sync_info.latest_block_height'
}

# Функция проверки статуса валидатора относительно сета

is_active_validator() {
  status=$(0gchaind q staking validator "$VALIDATOR_ADDRESS" --output json | jq -r '.status')
  [ "$status" = "BOND_STATUS_BONDED" ]
}

# === Стартовое уведомление при запуске мониторинга ===
initial_jailed=$(get_jailed_status)
initial_stake=$(get_stake)
initial_missed=$(get_missed_blocks)
high_missed_alert_sent=false
last_missed="$initial_missed"
initial_pid=$$

# === Формирование строки пропущенных блоков, если не в тюрьме ===
if [ "$initial_jailed" = "false" ]; then
  jail_line="🟢🥳 Ура! Вы на свободе, ваш статус: <b>unjailed</b>"
  missed_line="📉 Пропущено блоков: $initial_missed"
else
  jail_line="🔴😞 Все плохо, вы в тюрьме, примите меры, ваш статус: <b>jailed</b>"
  missed_line=""
fi

# === Стартовое уведомление ===
message=$(cat <<EOF
<b>📡 Мониторинг валидатора запущен</b>
<b>🔢 PID:</b> <code>$initial_pid</code>

$jail_line
$missed_line

<b>💰 Стейк:</b> $((initial_stake / 1000000))
EOF
)

send_telegram_alert "$message"

# === Инициализация переменных для отслеживания изменений ===
last_jail_status="$initial_jailed"
last_stake="$initial_stake"
last_jail_alert_ts=0

prev_local_height=$(get_local_height)
prev_remote_height=$(get_remote_height)

# Переменные состояния для отслеживания восстановления
recovery_in_progress=false
blocks_recovered=true

# ============= Главный цикл мониторинга =============
while true; do
  jailed=$(get_jailed_status)
  stake=$(get_stake)
  missed=$(get_missed_blocks)
  
  # === Проверка роста пропущенных блоков ===
if [[ "$missed" =~ ^[0-9]+$ ]] && [[ "$last_missed" =~ ^[0-9]+$ ]]; then
  missed_diff=$((missed - last_missed))

  if [ "$missed_diff" -ge 10 ]; then
     message=$(cat <<EOF
⚠️ <b>Рост пропущенных блоков!</b>

➕ <b>+$missed_diff</b> блоков за 5 минут
📊 <b>Всего пропущено:</b> <b>$missed</b>
EOF
)
    send_telegram_alert "$message"
    blocks_recovered=false  # Сбросить флаг восстановления
    recovery_in_progress=true  # Идёт восстановление
  fi

 # === Новый код: рост остановился ===
  if [ "$missed_diff" -eq 0 ] && [ "$recovery_in_progress" = "true" ]; then
    message=$(cat <<EOF
✅ <b>Рост пропущенных блоков остановился</b>

📉 Общее количество пропущенных: <b>$missed</b>
🛠 Блоки пока не восстановлены
EOF
)
    send_telegram_alert "$message"
    recovery_in_progress=false
  fi

  # === Новый код: полное восстановление ===
  if [ "$missed" -eq 0 ] && [ "$blocks_recovered" = "false" ]; then
    message=$(cat <<EOF
🎉 <b>Нода полностью восстановилась</b>

✅ Пропущенные блоки: <b>0</b>
🚀 Нода синхронизирована и снова в строю!
EOF
)
    send_telegram_alert "$message"
    blocks_recovered=true
  fi

 # === Отдельная тревога, если общее количество блоков > 700 ===
  if [ "$missed" -gt 700 ] && [ "$high_missed_alert_sent" = "false" ]; then
    message=$(cat <<EOF
🚨 <b>ВНИМАНИЕ!</b> 🚨

❗️ Вы пропустили уже <b>$missed</b> блоков!
⚡️ Срочно проверьте ноду, иначе нода окажется <b>в тюрьме</b>!
EOF
)
    send_telegram_alert "$message"
    high_missed_alert_sent=true
  fi

  # === Сброс флага, если пропущенные блоки снова ниже порога ===
  if [ "$missed" -le 700 ]; then
    high_missed_alert_sent=false
  fi
fi # <-- Вот это закрывает самое первое if (на missed)

  now_ts=$(date +%s)
  was_active=$(is_active_validator && echo "true" || echo "false")

  current_local_height=$(get_local_height)
  current_remote_height=$(get_remote_height)

  # === Проверка лагов ===
  if [[ "$current_local_height" =~ ^[0-9]+$ ]] && [[ "$current_remote_height" =~ ^[0-9]+$ ]] && \
     [[ "$prev_local_height" =~ ^[0-9]+$ ]] && [[ "$prev_remote_height" =~ ^[0-9]+$ ]]; then

    delta_local=$((current_local_height - prev_local_height))
    delta_remote=$((current_remote_height - prev_remote_height))
    lag=$((current_remote_height - current_local_height))

    if [ "$delta_local" -eq 0 ] && [ "$delta_remote" -ge 10 ]; then
      send_telegram_alert "❗️ <b>Локальная нода замерла</b>\nВысота не изменилась: <code>$current_local_height</code>\nУдалённый RPC вырос: <code>$delta_remote</code> блоков"
    fi
  else
    send_telegram_alert "❌ Ошибка получения высот. local=$current_local_height, remote=$current_remote_height"
  fi

  # === Проверка Jail ===
  if [ "$jailed" = "true" ]; then
    if [ $((now_ts - last_jail_alert_ts)) -ge 10800 ]; then
      [ "$lag" -lt 0 ] && lag="❌ Ошибка RPC, отставание < 0"

      message=$(cat <<EOF
⛔️ <b>Валидатор в тюрьме!</b>
📉 Отставание от RPC: $lag
EOF
)
      send_telegram_alert "$message"
      last_jail_alert_ts=$now_ts
    fi
  elif [ "$last_jail_status" = "true" ] && [ "$jailed" = "false" ]; then
    # === Валидатор вышел из тюрьмы ===
    stake_diff=$((stake - last_stake))
    stake_rounded=$((stake / 1000000))
    sign=$( [ "$stake_diff" -gt 0 ] && echo "+$((stake_diff / 1000000)) 🟢⬆️" || echo "$((stake_diff / 1000000)) 🔴⬇️" )

    message=$(cat <<EOF
✅ <b>Валидатор вышел из тюрьмы!</b>
📉 Отставание: $lag

💰 Изменение стейка: $stake_rounded ($sign)
EOF
)
    send_telegram_alert "$message"
    last_jail_alert_ts=0
  fi

    # === Уведомление об изменении стейка, если валидатор не в тюрьме ===
    if [ "$jailed" = "false" ] && [ "$stake" -ne "$last_stake" ]; then
      stake_diff=$((stake - last_stake))
      stake_rounded=$((stake / 1000000))
      sign=$( [ "$stake_diff" -gt 0 ] && echo "+$((stake_diff / 1000000)) 🟢⬆️" || echo "$((stake_diff / 1000000)) 🔴⬇️" )
    
    message=$(cat <<EOF
📈 <b>Изменение стейка</b>

💰 Новый стейк: $stake_rounded ($sign)
EOF
)

      send_telegram_alert "$message"
    fi

  last_jail_status="$jailed"
  last_stake="$stake"

  # === Проверка выпадения/возврата в активный сет ===
is_now_active=$(is_active_validator && echo "true" || echo "false")

if [ "$was_active" = "true" ] && [ "$is_now_active" = "false" ]; then
  send_telegram_alert "⚠️ <b>Валидатор выпал из активного сета</b>"
elif [ "$was_active" = "false" ] && [ "$is_now_active" = "true" ]; then
  send_telegram_alert "✅ <b>Валидатор вернулся в активный сет</b>"
fi
## === Отдельная тревога, если общее количество блоков > 700 ===
#  if [ "$missed" -gt 700 ]; then
#    message=$(cat <<EOF
#🚨 <b>ВНИМАНИЕ!</b> 🚨
#
#❗️ Вы пропустили уже <b>$missed</b> блоков!
#⚡️ Срочно проверьте ноду, иначе нода окажется <b>в тюрьме</b>!
#EOF
#)
#    send_telegram_alert "$message"
#  fi

was_active="$is_now_active"

  # === Проверка получения счетчика пропущенных блоков ===
  if [[ ! "$missed" =~ ^[0-9]+$ ]]; then
    send_telegram_alert "<b>❗️ Ошибка получения missed_blocks_counter</b>%0AВозможно, RPC не отвечает."
  fi
  # Обновляем высоты
    prev_local_height="$current_local_height"
    prev_remote_height="$current_remote_height"
  # обновляем переменные
    last_missed="$missed"
  sleep 300
done
