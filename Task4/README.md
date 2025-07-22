# Задание 4. Защита доступа к кластеру Kubernetes

**Цель:** Организовать ролевой доступ (RBAC) в Kubernetes для различных групп пользователей, разграничить доступ к ресурсам кластера в соответствии с организационной структурой компании.

## Шаги выполнения:

1. **Поднимаем пустой Minikube.**
2. **Определяем роли и их полномочия.**
3. **Подготавливаем скрипты для создания пользователей.**
4. **Подготавливаем скрипты для создания ролей (Role/ClusterRole).**
5. **Подготавливаем скрипты для связывания пользователей с ролями (RoleBinding/ClusterRoleBinding).**

### 1. Поднимаем пустой Minikube

Выполняем следующую команду для запуска Minikube: `minikube start`

2. Определяем роли и их полномочия
### 2. Определяем роли и их полномочия

В нашем задании мы будем использовать следующие роли:
(см. файл с ролями/правами/группами пользователей на основе шаблона по ссылке [Роли и полномочия](Шаблон_проектная_работа_7спринт.md))

```
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| Роль          | Права роли                                                                                  | Группы пользователей                           |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| cluster-admin     | Полный доступ ко всем ресурсам в кластере.                                                                   | system:masters (как пример, для администраторов платформы Kubernetes) |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| namespace-reader    | Доступ только на чтение ресурсов в конкретном namespace. Должен иметь возможность просматривать Deployment, Pod, Service и другие ресурсы, но не изменять их.                                  | developers, support (для отладки и мониторинга)         |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| namespace-developer   | Доступ на чтение, создание, обновление и удаление ресурсов в конкретном namespace. Должен иметь возможность создавать и редактировать Deployment, Pod, Service и другие ресурсы.                             | developers                              |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| secret-viewer      | Доступ только на чтение секретов (Secrets) во всех namespaces. Для пользователей, которым нужно знать конфигурационные данные, но не менять их.                  | security, auditors                          |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
| resource-quota-manager | Доступ на управление ResourceQuota в конкретном namespace.  Для управления ограничениями ресурсов.                                       | platform-engineering                        |
+-------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------------------------------------+
```

### 3. Подготавливаем скрипты для создания пользователей

Kubernetes не управляет пользователями напрямую. Аутентификация в Kubernetes обычно выполняется через внешние системы, такие как LDAP, OIDC, или TLS-сертификаты. В нашем примере для простоты будем использовать TLS-сертификаты.

**Важно:** В production-среде рекомендуется использовать более безопасные методы аутентификации.

Создадим два пользователя: `alice` (namespace-developer) и `bob` (namespace-reader).

**Скрипт:** [create_users.sh](create_users.sh) (см. файл по ссылке)

```
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
```

**Пояснения:**

- Скрипт генерирует приватные ключи (`alice.key`, `bob.key`) и CSR (Certificate Signing Request, `alice.csr`, `bob.csr`) для каждого пользователя.
- Используя CA (Certificate Authority) `ca.crt` и `ca.key`, скрипт подписывает CSR, создавая сертификаты (`alice.crt`, `bob.crt`).
- В production, CA должен быть надежным и хорошо защищенным. Не рекомендуется хранить CA key рядом с сертификатами пользователей.
- Этот скрипт предполагает, что у нас есть файлы `ca.crt` и `ca.key`. Если их нет, раскомментируем строки в скрипте для их генерации. Сам CA необходимо хранить в безопасном месте и не коммитить в репозиторий.

**Запуск скрипта:**

```
chmod +x create_users.sh
./create_users.sh
```

**Полученные файлы:**

- `alice.key`: Приватный ключ пользователя `alice`.
- `alice.crt`: Сертификат пользователя `alice`.
- `bob.key`: Приватный ключ пользователя `bob`.
- `bob.crt`: Сертификат пользователя `bob`.
- `ca.key`: Приватный ключ CA (Certificate Authority).
- `ca.crt`: Сертификат CA.

**Важная информация о безопасности:**

- Не коммитим приватные ключи (`alice.key`, `bob.key`, `ca.key`) в репозиторий. Храним их в безопасном месте.
- В production используем более безопасные методы аутентификации, такие как OIDC, LDAP или другие.
- Включаем Audit Logging в Kubernetes для отслеживания действий пользователей.

### 4. Подготавливаем скрипты для создания ролей (Role/ClusterRole)

Мы будем использовать `Role` для предоставления доступа в конкретном namespace и `ClusterRole` для предоставления доступа на уровне всего кластера. Для целей этого примера создадим роли `namespace-reader` и `namespace-developer` в namespace `default`.

**Файл конфигурации:** [create_roles.yaml](create_roles.yaml) (см. файл по ссылке)

```
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: namespace-reader
  namespace: default
rules:
- apiGroups: ["", "apps", "extensions"]
  resources: ["pods", "services", "deployments", "replicasets", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: namespace-developer
  namespace: default
rules:
- apiGroups: ["", "apps", "extensions"]
  resources: ["pods", "services", "deployments", "replicasets", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-viewer
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
```

**Пояснения:**

- `namespace-reader`: Роль с правами только на чтение основных ресурсов в namespace `default`.
- `namespace-developer`: Роль с правами на чтение, создание, обновление и удаление основных ресурсов в namespace `default`.
- `secret-viewer`: `ClusterRole` с правами на чтение секретов во всех namespaces.

**Применение ролей:** 

`kubectl apply -f create_roles.yaml`


### 5. Подготавливаем скрипты для связывания пользователей с ролями (RoleBinding/ClusterRoleBinding)

Теперь свяжем созданных пользователей с созданными ролями. Для ролей `namespace-reader` и `namespace-developer` мы будем использовать `RoleBinding`, так как они действуют в конкретном namespace. Для `secret-viewer` используем `ClusterRoleBinding`, так как она действует на уровне всего кластера.

**Файл конфигурации:** [bind_roles.yaml](bind_roles.yaml) (см. файл по ссылке)

```
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-namespace-developer-binding
  namespace: default
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bob-namespace-reader-binding
  namespace: default
subjects:
- kind: User
  name: bob
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bob-secret-viewer-binding
subjects:
- kind: User
  name: bob
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: secret-viewer
  apiGroup: rbac.authorization.k8s.io
```

**Пояснения:**

- `alice-namespace-developer-binding`: Связывает пользователя `alice` с ролью `namespace-developer` в namespace `default`.
- `bob-namespace-reader-binding`: Связывает пользователя `bob` с ролью `namespace-reader` в namespace `default`.
- `bob-secret-viewer-binding`: Связывает пользователя `bob` с `ClusterRole` `secret-viewer` во всем кластере.

**Применение связок:**

`kubectl apply -f bind_roles.yaml`


### 6. Проверка доступа пользователей

Для проверки доступа нужно настроить `kubectl` для каждого пользователя, используя созданные сертификаты.

**Настройка kubectl для alice:**

```
kubectl config set-credentials alice --client-certificate=alice.crt --client-key=alice.key
kubectl config set-context alice-context --cluster=minikube --user=alice --namespace=default
kubectl config use-context alice-context
```

Теперь `kubectl` настроен для работы от имени пользователя `alice`. Попробуем выполнить различные команды:

### Должна сработать успешно:
`kubectl get pods`

### Должна сработать успешно:
`kubectl create deployment nginx --image=nginx`

### Должна сработать успешно:
`kubectl delete deployment nginx`

Настройка kubectl для bob:

```
kubectl config set-credentials bob --client-certificate=bob.crt --client-key=bob.key
kubectl config set-context bob-context --cluster=minikube --user=bob --namespace=default
kubectl config use-context bob-context
```

Теперь `kubectl` настроен для работы от имени пользователя `bob`. Попробуем выполнить различные команды:

### Должна сработать успешно:
`kubectl get pods`

### Должна выдать ошибку (forbidden), так как у bob нет прав на создание:
`kubectl create deployment nginx --image=nginx`

### Должна сработать успешно (чтение секретов):
`kubectl get secrets --all-namespaces`

## Замечания по безопасности и масштабируемости:

- **Управление сертификатами:** Управление жизненным циклом сертификатов (создание, ротация, отзыв) важно для безопасности.
- **Использование внешних систем аутентификации:** В реальных средах следует использовать внешние системы аутентификации, такие как LDAP, OIDC (например, Keycloak), чтобы упростить управление пользователями и интеграцию с существующими системами.
- **Audit Logging:** Включите Audit Logging в Kubernetes для отслеживания действий пользователей и выявления подозрительной активности.
- **Network Policies:** Используйте Network Policies для ограничения сетевого трафика между Pods, чтобы дополнительно защитить приложение.
- **Контроль доступа к секретам:** Вместо предоставления права на просмотр секретов во всех namespaces, желательно использовать Kubernetes Secrets для предоставления доступа только к необходимым секретам. Также можно использовать External Secrets Operator для интеграции с системами хранения секретов, такими как HashiCorp Vault.
- **Namespace Isolation:** Использование Namespaces для изоляции команд и приложений, что упрощает управление ролями и ресурсами.
- **RBAC Best Practices:** Учет рекомендаций Kubernetes по RBAC, чтобы обеспечить безопасность и управляемость вашего кластера.

## Заключение:

Мы успешно настроили ролевой доступ в Kubernetes с помощью RBAC. Создали пользователей, роли и связали их, обеспечив разграничение доступа к ресурсам кластера. В реальной среде необходимо использовать более сложные методы аутентификации и следовать рекомендациям по безопасности Kubernetes.
