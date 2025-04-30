#!/bin/bash

echo "🔧 Запуск настройки валидатора..."

# Подгружаем .bash_profile для получения WALLET_NAME и прочих переменных
PROFILE_FILE="$HOME/.bash_profile"
if [ -f "$PROFILE_FILE" ]; then
  source "$PROFILE_FILE"
  echo "✅ Загружены переменные из $PROFILE_FILE"
else
  echo "❌ Файл $PROFILE_FILE не найден. Убедитесь, что он существует."
  exit 1
fi

# Проверяем наличие переменной WALLET_NAME
if [ -z "$WALLET_NAME" ]; then
  echo "❌ Переменная WALLET_NAME не задана в $PROFILE_FILE"
  exit 1
fi

# Запрашиваем пароль keyring
echo
read -sp "Введите пароль keyring: " KEYRING_PASSWORD
echo

# Получаем адреса по WALLET_NAME
WALLET_ADDRESS=$(echo "$KEYRING_PASSWORD" | xargs -0 printf "%s" | 0gchaind keys show "$WALLET_NAME" --bech acc -a)
VALIDATOR_ADDRESS=$(echo "$KEYRING_PASSWORD" | xargs -0 printf "%s" | 0gchaind keys show "$WALLET_NAME" --bech val -a)

# Сохраняем переменные в отдельный конфиг-файл
echo "💾 Сохраняем переменные..."
mkdir -p ~/.validator_config
cat > ~/.validator_config/env <<EOF
KEYRING_PASSWORD='$KEYRING_PASSWORD'
WALLET_NAME='$WALLET_NAME'
WALLET_ADDRESS='$WALLET_ADDRESS'
VALIDATOR_ADDRESS='$VALIDATOR_ADDRESS'
EOF

# Подключаем env в .bash_profile (если ещё не подключён)
if ! grep -q "source ~/.validator_config/env" "$PROFILE_FILE"; then
  echo 'source ~/.validator_config/env' >> "$PROFILE_FILE"
  echo "✅ Добавлен source ~/.validator_config/env в $PROFILE_FILE"
else
  echo "ℹ️ Файл env уже подгружается из $PROFILE_FILE"
fi

# Подгружаем в текущую сессию
source ~/.validator_config/env
echo "🔁 Переменные окружения применены в текущей сессии."

# Создаём alias-обёртку validator
echo ""
echo "🚀 Создаём команду 'validator' для быстрого запуска меню..."
mkdir -p "$HOME/bin"
cat > "$HOME/bin/validator" <<EOF
#!/bin/bash
source "\$HOME/0g/Validator/menu_validator.sh"
EOF
chmod +x "$HOME/bin/validator"

echo ""
echo "✅ Настройка завершена."
sleep 10
clear
echo "Теперь вы можете запускать меню в любой момент командой:"
echo "    validator"
echo ""
