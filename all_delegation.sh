#!/bin/bash

# Проверка необходимых переменных
if [ -z "$KEYRING_PASSWORD" ] || [ -z "$VALIDATOR_ADDRESS" ]; then
  echo "❌ Необходимые переменные не загружены. Пожалуйста, сначала выполните setup_per.sh"
  exit 1
fi

# Получение списка имён кошельков
wallet_names=$(echo "$KEYRING_PASSWORD" | 0gchaind keys list | grep "name:" | awk '{print $2}')

for wallet_name in $wallet_names; do
  # Получение баланса
  address=$(echo "$KEYRING_PASSWORD" | 0gchaind keys show "$wallet_name" -a)
  balance_info=$(0gchaind q bank balances "$address")
  amount=$(echo "$balance_info" | grep -B 1 "ua0gi" | grep "amount:" | awk '{print $3}' | tr -d '"')

  # Делегирование, если сумма достаточна
  if [ -n "$amount" ] && [ "$amount" -ge 100 ] 2>/dev/null; then
    echo "✅ Кошелек: $wallet_name, Баланс: ${amount} ua0gi"
    echo "$KEYRING_PASSWORD" | 0gchaind tx staking delegate "$VALIDATOR_ADDRESS" "${amount}ua0gi" \
      --from "$wallet_name" \
      --gas=auto \
      --gas-prices=0.003ua0gi \
      --gas-adjustment=1.4 \
      -y
    sleep $((RANDOM % 81 + 20))
  else
    echo "⚠️ Кошелек: $wallet_name, Недостаточно средств для делегации (текущий баланс: ${amount:-0})"
  fi
done
