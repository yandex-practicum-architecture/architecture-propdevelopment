Задание 5. Управление трафиком внутри кластера Kubernetes

В этом задании мы будем использовать NetworkPolicy в Kubernetes для контроля сетевого трафика между подами. NetworkPolicy позволит нам определить, какие поды могут взаимодействовать друг с другом и с внешними сервисами.

Важное замечание перед началом: Для работы NetworkPolicy в нашем кластере Kubernetes должен быть установлен CNI (Container Network Interface) плагин, который поддерживает NetworkPolicy (например, Calico, Cilium, Weave Net, Canal). Если использовать minikube, Calico часто идет по умолчанию или легко включается. В облачных кластерах (GKE, EKS, AKS) эта функциональность обычно включена по умолчанию или активируется соответствующими настройками.

Цели задания:

	Развернуть четыре сервиса Nginx с заданными метками.

	Добавить один "изолированный" под, с которым запрещено любое взаимодействие.

	Настроить NetworkPolicy так, чтобы:
		front-end мог общаться только с back-end-api (в обе стороны).
		admin-front-end мог общаться только с admin-back-end-api (в обе стороны).

	Все остальные взаимодействия между этими четырьмя сервисами были запрещены.

	"Изолированный" под не мог ни с кем общаться, и никто не мог общаться с ним.

	Проверить работоспособность настроенных политик.

Шаг 1: Развертывание сервисов (Подов)

Мы развернем четыре сервиса Nginx с указанными метками и один изолированный под. Команда `kubectl run --expose` создаст Deployment (который управляет подами) и Service (который предоставляет стабильное сетевое имя для доступа к подам).

Создаем `front-end-app`:
Метка: `role=front-end`
Service Name: `front-end-app bash kubectl run front-end-app --image=nginx --labels role=front-end --expose --port 80`

Создаем `back-end-api-app`:
Метка: `role=back-end-api`
Service Name: `back-end-api-app bash kubectl run back-end-api-app --image=nginx --labels role=back-end-api --expose --port 80`

Создаем `admin-front-end-app`:
Метка: `role=admin-front-end`
Service Name: `admin-front-end-app bash kubectl run admin-front-end-app --image=nginx --labels role=admin-front-end --expose --port 80`

Создаем `admin-back-end-api-app`:
Метка: `role=admin-back-end-api`
Service Name: `admin-back-end-api-app bash kubectl run admin-back-end-api-app --image=nginx --labels role=admin-back-end-api --expose --port 80`

Создаем изолированный под `isolated-app`:
Метка: `role=isolated`
Для этого пода нам не нужен Service, так как он не должен быть доступен извне. 
`bash kubectl run isolated-app --image=nginx --labels role=isolated --port 80`

Проверка развернутых подов и сервисов: Убедимся, что все поды запущены, а сервисы доступны:

```
kubectl get pods -l role
kubectl get svc
```

Мы увидим примерно следующий вывод (названия подов будут содержать случайные символы/hash-и):

```
# kubectl get pods -l role
NAME                                READY   STATUS    RESTARTS   AGE
admin-back-end-api-app-xxxx-yyyy    1/1     Running   0          Xs
admin-front-end-app-xxxx-yyyy       1/1     Running   0          Xs
back-end-api-app-xxxx-yyyy          1/1     Running   0          Xs
front-end-app-xxxx-yyyy             1/1     Running   0          Xs
isolated-app-xxxx-yyyy              1/1     Running   0          Xs
```

```
# kubectl get svc
NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
admin-back-end-api-app     ClusterIP   10.xx.xx.xx      <none>        80/TCP     Xs
admin-front-end-app        ClusterIP   10.xx.xx.xx      <none>        80/TCP     Xs
back-end-api-app           ClusterIP   10.xx.xx.xx      <none>        80/TCP     Xs
front-end-app              ClusterIP   10.xx.xx.xx      <none>        80/TCP     Xs
kubernetes                 ClusterIP   10.xx.xx.xx      <none>        443/TCP    Xs
```

Шаг 2: Создание сетевых политик (NetworkPolicy)

Мы создадим файл `non-admin-api-allow.yaml`, который будет содержать несколько объектов NetworkPolicy.

Общая логика NetworkPolicy:

	Политики применяются к подам, выбранным по `podSelector`.
	Если для пода нет подходящих NetworkPolicy, весь трафик разрешен.
	Если для пода есть хотя бы одна NetworkPolicy, то по умолчанию весь трафик, не соответствующий правилам `ingress` или `egress` этой политики, будет запрещен.
	`policyTypes`: Определяет, контролирует ли политика входящий (Ingress) или исходящий (Egress) трафик. Если не указано, по умолчанию только Ingress.
	Правила `ingress`: Что разрешено входить в поды, к которым применяется политика.
	Правила `egress`: Что разрешено выходить из подов, к которым применяется политика.

Для надежной изоляции и управления трафиком рекомендуется начать с политики "отказа по умолчанию" (Default Deny). Это значит, что если мы хотим, чтобы трафик был строго контролируем, сначала мы запрещаем весь трафик, а затем явно разрешаем только то, что необходимо.

Структура `non-admin-api-allow.yaml`:

	Default Deny All: Запрещает весь входящий и исходящий трафик для всех подов в данном namespace. Это наш базовый уровень безопасности.

	Allow DNS Egress: Поды должны иметь возможность разрешать доменные имена (например, имена сервисов Nginx) через Cluster DNS. Это правило разрешает исходящий трафик на порт 53 (UDP и TCP) для DNS-сервиса кластера (CoreDNS/Kube-DNS).

	Allow front-end <-> back-end-api: Две политики для двусторонней связи.

	Allow admin-front-end <-> admin-back-end-api: Две политики для двусторонней связи.

	Deny isolated-app (Optional but good for clarity): Хотя Default Deny уже запретит все, явное указание Deny для изолированного пода подчеркнет его назначение.

Создаём файл с именем `non-admin-api-allow.yaml` со следующим содержимым:
(см. файл по ссылке [Конфигурация: определение доступа](non-admin-api-allow.yaml))

```
# non-admin-api-allow.yaml

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default # Убедиться, что это наш текущий namespace
spec:
  podSelector: {} # Применяется ко всем подам в данном namespace
  policyTypes:
  - Ingress
  - Egress
  ingress: [] # Запретить весь входящий трафик
  egress: [] # Запретить весь исходящий трафик
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: default
spec:
  podSelector: {} # Применяется ко всем подам
  policyTypes:
    - Egress
  egress:
    - to:
      - namespaceSelector: {} # Разрешить к подам в любом namespace
        podSelector:
          matchLabels:
            k8s-app: kube-dns # Или coredns, в зависимости от вашей установки
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
# Политика для front-end-app: Разрешает ему отправлять запросы back-end-api-app
# и принимать от него ответы (обратный трафик по установленным соединениям).
# А также явное разрешение входящего трафика от back-end-api-app для двустороннего обмена.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: front-end
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: back-end-api
      ports:
        - protocol: TCP
          port: 80 # Порт, на котором слушает Nginx
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: back-end-api
      ports:
        - protocol: TCP
          port: 80 # Порт, на который мы отправляем запросы
---
# Политика для back-end-api-app: Разрешает ему отправлять запросы front-end-app
# и принимать от него ответы (обратный трафик по установленным соединениям).
# А также явное разрешение входящего трафика от front-end-app для двустороннего обмена.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-frontend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: back-end-api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: front-end
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: front-end
      ports:
        - protocol: TCP
          port: 80
---
# Политика для admin-front-end-app: Разрешает ему отправлять запросы admin-back-end-api-app
# и принимать от него ответы, а также явное разрешение входящего трафика.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-admin-frontend-to-admin-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: admin-front-end
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: admin-back-end-api
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: admin-back-end-api
      ports:
        - protocol: TCP
          port: 80
---
# Политика для admin-back-end-api-app: Разрешает ему отправлять запросы admin-front-end-app
# и принимать от него ответы, а также явное разрешение входящего трафика.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-admin-backend-to-admin-frontend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: admin-back-end-api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: admin-front-end
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: admin-front-end
      ports:
        - protocol: TCP
          port: 80
---
# Политика для isolated-app: Явно запрещает весь входящий и исходящий трафик.
# Это избыточно при наличии default-deny-all, но полезно для явного понимания.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-isolated-app
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: isolated
  policyTypes:
  - Ingress
  - Egress
  ingress: [] # Запретить весь входящий трафик к isolated-app
  egress: [] # Запретить весь исходящий трафик от isolated-app
```

Объяснение DNS-политики: Метка `k8s-app: kube-dns` (или `coredns`) является стандартной для пода, управляющего DNS-сервисом в кластере. Чтобы поды могли разрешать имена сервисов (например, `front-end-app`), им необходимо разрешить исходящий трафик на этот DNS-сервер. Если мы пропускаем эту политику, `wget` команды из тестовых подов, будут падать с ошибкой разрешения имени.

Шаг 3: Применение сетевых политик

Применяем созданный файл с политиками:

`kubectl apply -f non-admin-api-allow.yaml`

Мы должны увидеть вывод, подтверждающий создание каждой политики:

```
networkpolicy.networking.k8s.io/default-deny-all created
networkpolicy.networking.k8s.io/allow-dns-egress created
networkpolicy.networking.k8s.io/allow-frontend-to-backend created
networkpolicy.networking.k8s.io/allow-backend-to-frontend created
networkpolicy.networking.k8s.io/allow-admin-frontend-to-admin-backend created
networkpolicy.networking.k8s.io/allow-admin-backend-to-admin-frontend created
networkpolicy.networking.k8s.io/deny-isolated-app created
```

Для проверки списка политик, выполним:

`kubectl get networkpolicy`

Шаг 4: Проверка трафика

Для проверки трафика мы будем использовать временные поды с образом `alpine` и утилитой `wget`. Kubernetes будет автоматически уничтожать эти поды после завершения их работы (`--rm`).

Команда `wget -qO- --timeout=2 http://<service-name>` означает: `-q: тихий режим`, `-O-: вывести содержимое на стандартный вывод`, `--timeout=2: таймаут 2 секунды` (чтобы не ждать долго при заблокированном соединении) `http://<service-name>`: URL для запроса. Kubernetes DNS позволяет использовать имя сервиса как hostname.

1. Проверка разрешенного трафика:

`front-end-app -> back-end-api-app` (должно работать) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=front-end-test -- wget -qO- --timeout=2 http://back-end-api-app` 
Ожидаемый результат: `<!DOCTYPE html><html><head><title>Welcome to nginx!</title>...` (HTML-код страницы Nginx).

`back-end-api-app -> front-end-app` (должно работать, т.к. двусторонняя связь) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=backend-test -- wget -qO- --timeout=2 http://front-end-app`
Ожидаемый результат: HTML-код страницы Nginx.

`admin-front-end-app -> admin-back-end-api-app` (должно работать) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=admin-frontend-test -- wget -qO- --timeout=2 http://admin-back-end-api-app`
Ожидаемый результат: HTML-код страницы Nginx.

`admin-back-end-api-app -> admin-front-end-app` (должно работать, т.к. двусторонняя связь) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=admin-backend-test -- wget -qO- --timeout=2 http://admin-front-end-app`
Ожидаемый результат: HTML-код страницы Nginx.

2. Проверка запрещенного трафика:

`front-end-app -> admin-back-end-api-app` (должно быть запрещено) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=front-end-test -- wget -qO- --timeout=2 http://admin-back-end-api-app`
Ожидаемый результат: Ошибка таймаута (`wget: download timed out`) или ошибка соединения, без HTML-кода.

`admin-front-end-app -> back-end-api-app` (должно быть запрещено)
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=admin-frontend-test -- wget -qO- --timeout=2 http://back-end-api-app`
Ожидаемый результат: Ошибка таймаута или ошибка соединения.

Любой под (например, `front-end-app`) -> `isolated-app` (должно быть запрещено) 
`bash kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=front-end-test -- wget -qO- --timeout=2 http://isolated-app`
Ожидаемый результат: Ошибка таймаута или ошибка соединения. 

Важно: `isolated-app` не имеет Service, поэтому http://isolated-app не сработает. Мы должны обратиться по имени пода (`isolated-app-xxxx-yyyy`) или по его IP-адресу. Но так как `isolated-app` не должен иметь Service, то обращение по имени Service не имеет смысла. Лучше всего для проверки изолированности попробовать запустить тестовый под и с него попробовать обратиться к `isolated-app` по имени его пода (не Service), предварительно узнав его имя: 
`bash ISOLATED_POD_NAME=$(kubectl get pod -l role=isolated -o jsonpath='{.items[0].metadata.name}') kubectl run test-from-frontend-to-isolated --rm -i -t --image=alpine --labels role=front-end-test -- sh -c "wget -qO- --timeout=2 http://$ISOLATED_POD_NAME"` 
Ожидаемый результат: Ошибка таймаута или соединения.

`isolated-app` -> любой другой под (например, `front-end-app`) (должно быть запрещено) Для этого нам нужно выполнить команду прямо внутри `isolated-app` (или создать тестовый под с той же меткой `role=isolated`). 
`bash ISOLATED_POD_NAME=$(kubectl get pod -l role=isolated -o jsonpath='{.items[0].metadata.name}') kubectl exec -it $ISOLATED_POD_NAME -- sh -c "wget -qO- --timeout=2 http://front-end-app"` 
Ожидаемый результат: Ошибка таймаута или соединения.

Шаг 5: Освобождение ресурсов

После завершения можно удалить созданные ресурсы:

```
kubectl delete deployment front-end-app back-end-api-app admin-front-end-app admin-back-end-api-app isolated-app
kubectl delete service front-end-app back-end-api-app admin-front-end-app admin-back-end-api-app
kubectl delete networkpolicy default-deny-all allow-dns-egress allow-frontend-to-backend allow-backend-to-frontend allow-admin-frontend-to-admin-backend allow-admin-backend-to-admin-frontend deny-isolated-app
```
Или просто: `kubectl delete -f non-admin-api-allow.yaml`