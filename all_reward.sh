#!/bin/bash

# Проверка необходимых переменных
if [ -z "$KEYRING_PASSWORD" ] || [ -z "$VALIDATOR_ADDRESS" ]; then
  echo "❌ Необходимые переменные не загружены. Пожалуйста, сначала выполните setup_per.sh"
  exit 1
fi

# Получаем список имён кошельков
wallet_names=$(echo "$KEYRING_PASSWORD" | 0gchaind keys list | grep "name:" | awk '{print $2}')

# Проходим по каждому кошельку
for wallet_name in $wallet_names; do
  echo "💰 Выводим реварды для $wallet_name"

  echo "$KEYRING_PASSWORD" | 0gchaind tx distribution withdraw-rewards "$VALIDATOR_ADDRESS" \
    --chain-id="zgtendermint_16600-2" \
    --from "$wallet_name" \
    --gas=auto \
    --gas-prices=0.003ua0gi \
    --gas-adjustment=1.4 \
    -y

  sleep $((RANDOM % 81 + 20))
done
