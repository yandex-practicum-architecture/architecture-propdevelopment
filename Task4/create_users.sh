#!/bin/bash

# Функция для создания сертификата пользователя
create_user_cert() {
  USER=$1
  openssl genrsa -out "${USER}.key" 2048
  openssl req -new -key "${USER}.key" -out "${USER}.csr" -subj "/CN=${USER}"
  openssl x509 -req -in "${USER}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${USER}.crt" -days 365
  echo "Created certificate for user: ${USER}"
}

# Создаем CA для подписи сертификатов.  В реальной среде использовать существующий CA.
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=kubernetes-ca" -days 3650 -out ca.crt

# Создаем сертификаты для пользователей
create_user_cert alice
create_user_cert bob

echo "User creation complete.  Key and certificate files are created."