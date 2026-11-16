# Kafka Console – instalacja (Helm)

Webowa konsola do Kafki: topiki, wiadomości, grupy konsumentów, schematy, ACL, uprawnienia per klaster i dziennik
zdarzeń. Instalujesz ją jednym poleceniem `helm install`.

Obrazy (publiczne, Docker Hub), wersja `0.10.1`:

- `docker.io/arturkiwa/kafka-console-backend`
- `docker.io/arturkiwa/kafka-console-frontend`

## Co pobrać

Z zakładki **Releases** (`v0.10.1`) trzy pliki:

- `kafka-console-0.10.1.tgz` – chart Helm,
- `values-poc.yaml` – ustawienia,
- `postgres-poc.yaml` – baza PostgreSQL na czas POC.

Przenieś je na maszynę, z której masz `kubectl` i `helm` do klastra.

## 1. Namespace i hasło do bazy

```sh
kubectl create namespace kafka-console
kubectl -n kafka-console create secret generic kafka-console-db --from-literal=password="$(openssl rand -hex 24)"
```

Hasła nie musisz znać: korzystają z niego tylko baza i konsola.

## 2. Baza

```sh
kubectl -n kafka-console apply -f postgres-poc.yaml
kubectl -n kafka-console rollout status statefulset/kafka-console-postgres
```

Potrzebna jest domyślna StorageClass (`kubectl get storageclass`), bo baza zajmuje wolumen 5 GiB.
Jeśli masz firmową bazę PostgreSQL 16 lub nowszą, pomiń ten krok i w `values-poc.yaml` ustaw `database.url` i `database.user`.

## 3. Ustawienia

W `values-poc.yaml` zmień miejsca oznaczone `ZMIEŃ`:

- `host`: adres konsoli,
- `expose.ingress.className`: klasa ingressu (`kubectl get ingressclass`),
- `clusters`: adresy brokerów Kafki,
- `networkPolicy.ingressFrom`: namespace kontrolera ingress.

## 4. Instalacja

```sh
helm install kafka-console kafka-console-0.10.1.tgz -n kafka-console -f values-poc.yaml
kubectl -n kafka-console rollout status deploy/kafka-console-backend
```

## 5. Pierwszy administrator

```sh
kubectl -n kafka-console exec deploy/kafka-console-backend -- kafka-console-admin create-admin admin "Administrator"
```

Polecenie wypisze hasło jednorazowe. Przy pierwszym logowaniu konsola każe je zmienić.
Uprawnienia do klastrów nadajesz sobie w konsoli, w zakładce **Dostęp**.

## 6. Otwarcie konsoli

Otwórz `https://<host>`.

Jeśli nie masz ingressu, w kroku 3 ustaw `expose.type: none` i połącz się przez port-forward:

```sh
kubectl -n kafka-console port-forward svc/kafka-console-frontend 8080:8080
```

Potem otwórz `http://localhost:8080`. Adres musi być dokładnie `localhost`, bo przez zwykłe http z innego adresu
przeglądarka nie zapisze ciasteczka sesji. Z innego komputera użyj tunelu: `ssh -L 8080:127.0.0.1:8080 <maszyna>`.

## Klaster z TLS

Certyfikaty wrzuć do Secretu:

```sh
kubectl -n kafka-console create secret generic kafka-test-01 \
  --from-file=ca.crt --from-file=tls.crt --from-file=tls.key
```

Plik `tls.crt` i `tls.key` dodajesz tylko wtedy, gdy broker wymaga certyfikatu klienta (mTLS).

W `values-poc.yaml`:

```yaml
clusters:
  - id: test-01
    name: Kafka TEST
    environment: TEST
    bootstrap: kafka-1.example:9093
    security:
      protocol: SSL
      truststore: { file: /etc/kafka-console/clusters/test-01/ca.crt }
      certificate:                       # tylko mTLS
        file: /etc/kafka-console/clusters/test-01/tls.crt
        key-file: /etc/kafka-console/clusters/test-01/tls.key

clusterSecrets:
  - name: test-01
    secretName: kafka-test-01
    mountPath: /etc/kafka-console/clusters/test-01
```

Keystore JKS lub PKCS12 też zadziała:

```yaml
      keystore: { file: /etc/kafka-console/clusters/test-01/keystore.jks, password-file: /etc/kafka-console/clusters/test-01/keystore.password }
```

Adres w `bootstrap` musi być nazwą z certyfikatu brokera, a nie adresem IP.

Zmiany wprowadzasz tak:

```sh
helm upgrade kafka-console kafka-console-0.10.1.tgz -n kafka-console -f values-poc.yaml
```

## ACL Kafki

Jeśli Kafka ma włączoną autoryzację, konsola potrzebuje ACL dla swojej tożsamości. Przy mTLS jest to `User:` + temat
certyfikatu, bez certyfikatu `User:ANONYMOUS`. Do samego podglądu wystarczy:

```sh
P='User:CN=kafka-console'
BS='--bootstrap-server kafka-1.example:9093 --command-config admin.properties'
kafka-acls.sh $BS --add --allow-principal "$P" --cluster --operation Describe --operation DescribeConfigs
kafka-acls.sh $BS --add --allow-principal "$P" --topic '*' --operation Describe --operation DescribeConfigs --operation Read
kafka-acls.sh $BS --add --allow-principal "$P" --group '*' --operation Describe
```

Ekran **ACL** w konsoli pokazuje, jak Kafka widzi tożsamość konsoli.
Jeśli coś nie działa, ekran **Przegląd klastra** pokazuje, czego brakuje: certyfikatu, DNS, portu albo ACL.

## Obrazy przez Artifactory

Jeśli klaster nie ma dostępu do Docker Hub, dopisz do `values-poc.yaml` adresy obrazów w swoim proxy. Digesty
zostają te same:

```yaml
image:
  backend:  { repository: artifactory.example/docker/arturkiwa/kafka-console-backend }
  frontend: { repository: artifactory.example/docker/arturkiwa/kafka-console-frontend }
```

To samo dotyczy obrazu `postgres:17-alpine` w `postgres-poc.yaml`.

## Usunięcie

```sh
helm -n kafka-console uninstall kafka-console
kubectl delete namespace kafka-console
```

Usunięcie namespace kasuje też bazę.
