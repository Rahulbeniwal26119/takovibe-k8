# takovibe infra

Kubernetes manifests for takovibe. The same YAML runs on minikube (local) and k3s (prod).

```
.sops.yaml                 which files get encrypted, and to which age public key
deploy.sh                  apply manifests + decrypted secrets to one environment
base/                      shared by every environment
  redis/
overlays/
  local/                   minikube
  prod/                    k3s
    secrets/*.enc.yaml     SOPS-encrypted, safe to commit
```

## Prerequisites

```sh
brew install kubectl minikube sops age redis   # redis only for redis-cli
```

## age key (once per machine)

**First machine**, generate a key:

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Put the printed public key (`age1...`) in `.sops.yaml`, then back up `keys.txt` in a password manager.
**If it is lost, every secret in this repo is unrecoverable.**

**New machine**, restore `keys.txt` from the password manager to `~/.config/sops/age/keys.txt` and `chmod 600` it.

**Both**, tell sops where the key is (on macOS it otherwise looks in `~/Library/Application Support/sops/age/`):

```sh
echo 'export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt' >> ~/.zshrc
```

| Key | Looks like | Where it lives |
|---|---|---|
| public | `age1...` | `.sops.yaml`, committed. Can only encrypt. |
| private | `AGE-SECRET-KEY-1...` | `keys.txt` on your laptop only. Never in the repo, never on the server. |

## Secrets

**Create**

```sh
kubectl create secret generic <name> -n takovibe \
  --from-literal=<key>="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml > overlays/<env>/secrets/<name>.enc.yaml
sops -e -i overlays/<env>/secrets/<name>.enc.yaml
grep ENC overlays/<env>/secrets/<name>.enc.yaml   # must show ENC[...] before you commit
```

**Edit**: opens decrypted in `$EDITOR`, re-encrypts on save. Values under `data:` are base64 (`echo -n 'value' | base64`).

```sh
sops overlays/<env>/secrets/<name>.enc.yaml
```

**Read one value**

```sh
sops -d --extract '["data"]["password"]' overlays/local/secrets/redis-auth.enc.yaml | base64 -d; echo
```

**Rotate**: edit, `./deploy.sh <env>`, then restart whatever reads it. Env vars from secrets are only read at pod start.

```sh
kubectl -n takovibe rollout restart statefulset/redis
```

**Add another key** (new laptop with its own key, CI): append its public key to `age:` in `.sops.yaml` (comma-separated), then re-encrypt:

```sh
for f in overlays/*/secrets/*.enc.yaml; do sops updatekeys -y "$f"; done
```

Never write decrypted files to disk. If you must, name them `*.dec.yaml` (gitignored).

## Deploy

```sh
minikube start --cpus=4 --memory=6g
kubectl kustomize overlays/local                                      # render only
kubectl apply -k overlays/local --dry-run=server --context minikube   # validate against the API
./deploy.sh local
kubectl -n takovibe get pods -w
```

`./deploy.sh prod` needs a kubectl context named `takovibe-prod`. Each env is pinned to its context so one can never be deployed to the other's cluster.

## Redis

```sh
kubectl -n takovibe exec -it redis-0 -- redis-cli          # shell inside the pod, already authenticated

kubectl -n takovibe port-forward svc/redis 6380:6379       # from your Mac, in another terminal:
REDISCLI_AUTH=$(sops -d --extract '["data"]["password"]' overlays/local/secrets/redis-auth.enc.yaml | base64 -d) \
  redis-cli -p 6380
```

In-cluster URL for apps: `redis://:<password>@redis:6379/0`
