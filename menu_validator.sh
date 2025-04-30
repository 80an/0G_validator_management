#!/bin/bash

# Берем цвета
source <(wget -qO- 'https://raw.githubusercontent.com/CBzeek/Nodes/refs/heads/main/!tools/bash-colors.sh')
B_BLUE='\033[1;34m' # Blue 
B_PURPLE='\033[0;35m' # Purple 
B_CYAN='\033[0;36m' # Cyan

ENV_FILE="$HOME/.validator_config/env"

# Подгрузка переменных окружения
if [ -f "$ENV_FILE" ]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "${B_RED}❌${NO_COLOR} Не найден файл $ENV_FILE. Пожалуйста, сначала запустите setup_per.sh."
  exit 1
fi

# Проверка основных переменных
if [[ -z "${KEYRING_PASSWORD// }" || -z "${WALLET_NAME// }" || -z "${VALIDATOR_ADDRESS// }" ]]; then
  echo "${B_RED}❌${NO_COLOR} Необходимые переменные не загружены. Пожалуйста, сначала запустите setup_per.sh."
  exit 1
fi

# Функция проверки изменений в папке 0g/Validator на сервере и GitHub
check_for_updates() {
  cd "$HOME/0g" || return

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    git fetch origin main &>/dev/null
    if ! git diff --quiet origin/main -- Validator; then
      echo -e "${B_YELLOW}⚠️ Обнаружены изменения в папке 0g/Validator. Рекомендуется обновить программу.${NO_COLOR}"
      echo -e "${B_YELLOW}Для этого запустите скрипт техменю${NO_COLOR}"
      echo -e "source <(wget -qO- 'https://raw.githubusercontent.com/80an/Nodes/refs/heads/main/0g/Validator/tech_menu.sh')"
      echo -e "${B_YELLOW}и выберите пункт меню 'Установка / обновление программы'.${NO_COLOR}"
      sleep 10
    else
      echo -e "${B_GREEN}✅ Все файлы актуальны в папке 0g/Validator, изменений не обнаружено.${NO_COLOR}"
    fi
  fi
}

#check_for_updates() {
#  # Переходим в директорию с программой
#  cd "$HOME/0g" || { echo "${B_RED}❌${NO_COLOR} Ошибка доступа к директории с программой"; exit 1; }

#  # Обновляем информацию о репозитории
#  git fetch --quiet

#  # Сравниваем только папку 0g/Validator
#  local changes=$(git diff --stat origin/main -- Validator)

#  if [ -n "$changes" ]; then
#    echo -e "${B_YELLOW}⚠️ Обнаружены изменения в папке 0g/Validator. Рекомендуется обновить программу.${NO_COLOR}"
#    echo -e "${B_YELLOW}Для этого запустите скрипт техменю${NO_COLOR}"
#    echo -e "source <(wget -qO- 'https://raw.githubusercontent.com/80an/Nodes/refs/heads/main/0g/Validator/tech_menu.sh')"
#    echo -e "${B_YELLOW}и выберите пункт меню 'Установка / обновление программы'.${NO_COLOR}"
#    sleep 10
#  else
#    echo -e "${B_GREEN}✅ Все файлы актуальны в папке 0g/Validator, изменений не обнаружено.${NO_COLOR}"
#  fi
#}

# Проверка наличия обновлений перед запуском меню валидатора
check_for_updates

MONITOR_PID_FILE="$HOME/.validator_config/monitor_validator.pid"
PROPOSAL_PID_FILE="$HOME/.validator_config/monitor_proposals.pid"

while true; do
  echo
  echo -e "${B_GREEN}========= 📋 Меню управления валидатором =========${NO_COLOR}"
  echo -e "1) ${B_YELLOW}💰${NO_COLOR} Забрать комиссии и реварды валидатора"
  echo -e "2) ${B_GREEN}💸${NO_COLOR} Забрать все реварды со всех кошельков"
  echo -e "3) ${B_PURPLE}📥${NO_COLOR} Делегировать со всех кошельков в своего валидатора"
  echo -e "4) ${B_CYAN}🗳${NO_COLOR}  Голосование по пропозалу"
  echo -e "5) 🚪 Вызволить из тюрьмы"
  echo -e "6) ${B_BLUE}📡${NO_COLOR} Мониторинг"
  echo -e "7) ${B_RED}❌${NO_COLOR} Выход"
  echo -e -e "${B_GREEN}==================================================${NO_COLOR}"
  echo

  read -p "Выберите пункт меню (1-7): " choice

  case $choice in
    1)
      echo "${B_YELLOW}💰${NO_COLOR} Забрать комиссии и реварды валидатора"
      echo "$KEYRING_PASSWORD" | 0gchaind tx distribution withdraw-rewards "$VALIDATOR_ADDRESS" \
        --chain-id="zgtendermint_16600-2" \
        --from "$WALLET_NAME" \
        --commission \
        --gas=auto \
        --gas-prices=0.003ua0gi \
        --gas-adjustment=1.8 \
        -y
      ;;
    2)
      echo "${B_GREEN}💸${NO_COLOR} Забрать все реварды со всех кошельков"
      source "$HOME/0g/Validator/all_reward.sh"
      ;;
    3)
      echo "${B_PURPLE}📥${NO_COLOR} Делегировать со всех кошельков в своего валидатора"
      source "$HOME/0g/Validator/all_delegation.sh"
      ;;
    4)
            # === Проверка на текущие активные голосования в периоде депозита ===
      active_proposals=$(0gchaind q gov proposals --status voting_period --output json 2>/dev/null || echo '{"proposals": []}' | jq '.proposals | length')
      
      # Если активных предложений нет (значение 0), выходим в основное меню
      if [ "$active_proposals" -eq 0 ]; then
        echo -e "${B_RED}❌${NO_COLOR} В данный момент нет активных голосований!"
             
      # Возврат в главное меню
      validator
      
      fi
        echo "${B_CYAN}🗳${NO_COLOR} Голосование по пропозалу"
        read -p "Введите номер пропозала: " proposal
        read -p "Введите ваш голос (yes/no/abstain/no_with_veto): " vote
        echo "$KEYRING_PASSWORD" | 0gchaind tx gov vote "$proposal" "$vote" \
          --from "$WALLET_NAME" \
          --chain-id="zgtendermint_16600-2" \
          --gas=auto \
          --gas-prices=0.003ua0gi \
          --gas-adjustment=1.8 \
          -y
      ;;
    5)
      echo "🚪 Вызволить из тюрьмы"
      echo "$KEYRING_PASSWORD" | 0gchaind tx slashing unjail \
        --from "$WALLET_NAME" \
        --chain-id="zgtendermint_16600-2" \
        --gas=auto \
        --gas-prices=0.003ua0gi \
        --gas-adjustment=1.8 \
        -y
      ;;
    6)
        # Проверка наличия переменных Telegram в env-файле (только наличие строк)
      if ! grep -q '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" || ! grep -q '^TELEGRAM_CHAT_ID=' "$ENV_FILE"; then
        echo "🤖 Параметры Telegram-бота не найдены в env-файле. Пожалуйста, введите:"
        read -p "🔑 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        read -p "💬 Telegram Chat ID: " TELEGRAM_CHAT_ID
      
        mkdir -p "$HOME/.validator_config"
      
        # Очистка старых значений
        sed -i '/^TELEGRAM_BOT_TOKEN=/d' "$ENV_FILE"
        sed -i '/^TELEGRAM_CHAT_ID=/d' "$ENV_FILE"
      
        # Запись новых
        echo "TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\"" >> "$ENV_FILE"
        echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$ENV_FILE"
      fi
      
      # Подгружаем переменные Telegram
      set -o allexport
      source "$ENV_FILE"
      set +o allexport

      
      # Подменю мониторинга
      while true; do
        echo
        echo "========= 📡 Подменю мониторинга ========="
        echo "1) ▶️ Включить мониторинг валидатора"
        echo "2) ▶️ Включить мониторинг пропозалов"
        echo "3) 📊 Состояние мониторинга"
        echo "4) ⏹ Отключить мониторинг валидатора"
        echo "5) ⏹ Отключить мониторинг пропозалов"
        echo "6) 🔙 Вернуться в главное меню"
        echo "=========================================="
        read -p "Выберите действие (1-6): " subchoice

        case $subchoice in
         1)
            echo "▶️ Включаем мониторинг валидатора..."
            # 🔁 Повторная подгрузка переменных
            if [ -f "$ENV_FILE" ]; then
              set -o allexport
              source "$ENV_FILE"
              set +o allexport
            fi
          
            # 🔐 Проверка параметров Telegram
            if [[ -z "${TELEGRAM_BOT_TOKEN// }" || -z "${TELEGRAM_CHAT_ID// }" ]]; then
              echo "🤖 Не заданы параметры Telegram-бота. Введите заново:"
              read -p "🔑 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
              read -p "💬 Telegram Chat ID: " TELEGRAM_CHAT_ID
          
              # Очистка старых значений
              sed -i '/^TELEGRAM_BOT_TOKEN=/d' "$ENV_FILE"
              sed -i '/^TELEGRAM_CHAT_ID=/d' "$ENV_FILE"
          
              # Запись новых
              echo "TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\"" >> "$ENV_FILE"
              echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$ENV_FILE"
          
              # Подгружаем заново
              set -o allexport
              source "$ENV_FILE"
              set +o allexport
            fi

            # ▶️ Запуск мониторинга
            nohup bash "$HOME/0g/Validator/Monitoring/monitoring_validator.sh" > /dev/null 2>&1 &
            MONITOR_PID=$!
            sleep 1  # даём немного времени процессу стартануть
            if ps -p "$MONITOR_PID" > /dev/null 2>&1; then
              echo "$MONITOR_PID" > "$MONITOR_PID_FILE"
              echo "✅ Мониторинг запущен. PID сохранён в $MONITOR_PID_FILE"
            else
              echo "${B_RED}❌${NO_COLOR} Ошибка запуска мониторинга. Проверь переменные окружения или логи."
            fi
            ;;

         2)
            echo "▶️ Включаем мониторинг пропозалов..."
            nohup bash "$HOME/0g/Validator/Monitoring/monitoring_proposal.sh" > /dev/null 2>&1 &
            PROPOSAL_PID=$!
            sleep 1
            if ps -p "$PROPOSAL_PID" > /dev/null 2>&1; then
              echo "$PROPOSAL_PID" > "$PROPOSAL_PID_FILE"
              echo "✅ Мониторинг запущен. PID сохранён в $PROPOSAL_PID_FILE"
            else
              echo "${B_RED}❌${NO_COLOR} Ошибка запуска мониторинга пропозалов. Проверь переменные окружения или логи."
            fi
            ;;
          3)
            echo "📊 Проверяем статус мониторинга..."
            if [ -f "$MONITOR_PID_FILE" ]; then
              PID=$(cat "$MONITOR_PID_FILE")
              if ps -p "$PID" > /dev/null 2>&1; then
                echo "✅ Мониторинг валидатора запущен (PID: $PID)"
              else
                echo "⚠️ Процесс с PID $PID не найден. Возможно, мониторинг неактивен."
              fi
            else
              echo "ℹ️ PID-файл мониторинга валидатора не найден."
            fi
            if [ -f "$PROPOSAL_PID_FILE" ]; then
              PID=$(cat "$PROPOSAL_PID_FILE")
              if ps -p "$PID" > /dev/null 2>&1; then
                echo "✅ Мониторинг пропозалов запущен (PID: $PID)"
              else
                echo "⚠️ Процесс с PID $PID не найден. Возможно, мониторинг пропозалов неактивен."
              fi
            else
              echo "ℹ️ PID-файл мониторинга пропозалов не найден."
            fi
            ;;
          4)
            echo "${B_RED}⛔${NO_COLOR} Останавливаем мониторинг валидатора..."
            if [ -f "$MONITOR_PID_FILE" ]; then
              PID=$(cat "$MONITOR_PID_FILE")
              if kill "$PID" > /dev/null 2>&1; then
                echo "✅ Мониторинг остановлен."
                sleep 5
                rm "$MONITOR_PID_FILE"
              else
                echo "⚠️ Не удалось завершить процесс. Возможно, он уже не существует."
              fi
            else
              echo "ℹ️ PID-файл не найден. Мониторинг, возможно, не запускался."
            fi
            ;;
          5)
            echo "${B_RED}⛔${NO_COLOR} Останавливаем мониторинг пропозалов..."
            if [ -f "$PROPOSAL_PID_FILE" ]; then
              PID=$(cat "$PROPOSAL_PID_FILE")
              if kill "$PID" > /dev/null 2>&1; then
                echo "✅ Мониторинг пропозалов остановлен."
                sleep 5
                rm "$PROPOSAL_PID_FILE"
              else
                echo "⚠️ Не удалось завершить процесс. Возможно, он уже не существует."
              fi
            else
              echo "ℹ️ PID-файл мониторинга пропозалов не найден."
            fi
            ;;
          6)
            break
            ;;
          *)
            echo "🚫 Неверный выбор, пожалуйста, выберите от 1 до 6."
            ;;
        esac
      done
      ;;
    7)
      echo "${B_RED}❌${NO_COLOR} Выход из программы..."
      break
      ;;
    *)
      echo "🚫 Неверный выбор, пожалуйста, выберите пункт от 1 до 7."
      ;;
  esac
done
