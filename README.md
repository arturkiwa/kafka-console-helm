# Kafka Console – instalacja (Helm)

Webowa konsola do Kafki: topiki, wiadomości, grupy konsumentów, schematy, ACL, uprawnienia per klaster i dziennik
zdarzeń. Instalujesz ją jednym poleceniem `helm install`.

Obrazy (publiczne, Docker Hub), wersja `0.10.4`:

- `docker.io/arturkiwa/kafka-console-backend`
- `docker.io/arturkiwa/kafka-console-frontend`

## Co pobrać

Z zakładki **Releases** (`v0.10.4`) dwa pliki:

- `kafka-console-0.10.4.tgz` – chart Helm,
- `values-poc.yaml` – ustawienia.

Przenieś je na maszynę, z której masz `kubectl` i `helm` do klastra.

Baza PostgreSQL instaluje się razem z konsolą. Potrzebna jest tylko StorageClass dla wolumenu 5 GiB.

## 1. Ustawienia

W `values-poc.yaml` zmień miejsca oznaczone `ZMIEŃ`:

- `host`: adres konsoli,
- `expose.ingress.className`: klasa ingressu (`kubectl get ingressclass`),
- `clusters`: adresy brokerów Kafki,
- `networkPolicy.ingressFrom`: namespace kontrolera ingress.

## 2. Instalacja

```sh
helm install kafka-console kafka-console-0.10.4.tgz -n kafka-console --create-namespace -f values-poc.yaml
kubectl -n kafka-console rollout status statefulset/kafka-console-postgres
kubectl -n kafka-console rollout status deploy/kafka-console-backend
```

## 3. Pierwszy administrator

```sh
kubectl -n kafka-console exec deploy/kafka-console-backend -- kafka-console-admin create-admin admin "Administrator"
```

Polecenie wypisze hasło jednorazowe. Przy pierwszym logowaniu konsola każe je zmienić.
Uprawnienia do klastrów nadajesz sobie w konsoli, w zakładce **Dostęp**.

## 4. Otwarcie konsoli

Otwórz `https://<host>`.

Jeśli nie masz ingressu, w kroku 1 ustaw `expose.type: none` i połącz się przez port-forward:

```sh
kubectl -n kafka-console port-forward svc/kafka-console-frontend 8080:8080
```

Potem otwórz `http://localhost:8080`. Adres musi być dokładnie `localhost`, bo przez zwykłe http z innego adresu
przeglądarka nie zapisze ciasteczka sesji. Z innego komputera użyj tunelu: `ssh -L 8080:127.0.0.1:8080 <maszyna>`.

## Kafka po SSL

1. Skopiuj CA brokera do katalogu chartu: `kafka-console/certs/<id klastra>/ca.crt`, np.
   `kafka-console/certs/test-01/ca.crt`. Przy mTLS dorzuć tam też `tls.crt` i `tls.key`.
2. W `values-poc.yaml` ustaw dla tego klastra `security: { protocol: SSL }`.
3. Wdróż:

```sh
helm upgrade kafka-console ./kafka-console -n kafka-console -f values-poc.yaml
```

Chart sam wgra certyfikaty do klastra i wskaże je konsoli. W `bootstrap` podaj nazwy z certyfikatu brokera, nie IP.

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

Jeśli klaster nie ma dostępu do Docker Hub, dopisz do `values-poc.yaml` adresy obrazów w swoim proxy:

```yaml
image:
  backend:  { repository: artifactory.example/docker/arturkiwa/kafka-console-backend }
  frontend: { repository: artifactory.example/docker/arturkiwa/kafka-console-frontend }
postgres:
  image: { repository: artifactory.example/docker/library/postgres }
```

## Usunięcie

```sh
helm -n kafka-console uninstall kafka-console
kubectl delete namespace kafka-console
```

Usunięcie namespace kasuje też bazę.
