 # Atelier API-driven : LocalStack + Lambda + API Gateway

## Objectif
Construire une petite architecture API-driven où une requête HTTP déclenche, via API Gateway et Lambda, des actions sur une instance EC2 (status / start / stop). L’ensemble s’exécute dans un GitHub Codespace et les services AWS sont émulés par LocalStack.

Contrainte importante : aucune dépendance à `localhost` — on utilise l’URL publique fournie par Codespaces pour le port 4566.

## Architecture (vue rapide)
- Client HTTP (curl / navigateur)
- API Gateway (endpoint public)
- Lambda (Python)
- EC2 (LocalStack)

Flux :

HTTP GET /ec2?action=status|start|stop → API Gateway → Lambda → EC2 (LocalStack)

## Fichiers importants
- `lambda/lambda_function.py` : fonction handler Lambda
- `Makefile` : automatisation (packaging, déploiement, tests)
- `.out/api_url` : URL de l’API après `make deploy-api`

## Prérequis
- Un Codespace lancé à partir de ce dépôt
- `python3`, `pip`, `make`, `zip` (disponibles par défaut dans Codespaces)

## Quickstart

1) Préparer l’environnement Python (optionnel localement)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install localstack awscli-local boto3
```

2) Démarrer LocalStack

```bash
localstack start -d
localstack status services
```

3) Rendre public le port 4566 (Codespaces)

- Dans l’onglet `Ports`, trouver le port `4566` et le passer en Public
- Copier l’URL générée (ex. `https://xxxxxx-4566.app.github.dev`) — c’est ton `AWS_ENDPOINT_URL`

```bash
export AWS_ENDPOINT_URL="https://TON-PORT-4566.app.github.dev"
curl -sS "$AWS_ENDPOINT_URL/_localstack/health" | head
```

Tu dois voir `apigateway`, `lambda`, `ec2`, `sts` en `running/available`.

4) Vérifier la Lambda

Le handler lit les variables d’environnement : `AWS_ENDPOINT_URL`, `INSTANCE_ID`, `AWS_REGION` (par défaut `us-east-1`). Il attend un paramètre query `action` avec les valeurs `start`, `stop` ou `status`.

5) Déployer / mettre à jour la Lambda

```bash
make deploy-lambda
# Test direct (sans API Gateway)
make test-lambda
```

La commande `make test-lambda` renvoie un JSON contenant l’état (`running` / `stopped`).

6) Déployer l’API Gateway

```bash
make clean-api
make deploy-api
```

`make clean-api` supprime les IDs API Gateway mis en cache (utile si tu changes d’environnement). Après `make deploy-api`, l’URL publique est affichée et sauvegardée dans `.out/api_url`.

7) Tester l’API (scénario complet)

```bash
make test-api
# OU manuellement
API_URL="$(cat .out/api_url)"
curl -s "$API_URL?action=status" && echo
curl -s "$API_URL?action=stop" && echo
curl -s "$API_URL?action=start" && echo
```

Réponses attendues (exemples):
- `status` → {"instance": "...", "state": "running"}
- `stop` → {"action": "stop", "instance": "..."}
- `start` → {"action": "start", "instance": "..."}

## Vérification de la contrainte « pas de localhost »

Pour s’assurer qu’aucune référence à `localhost` n’existe dans le projet :

```bash
grep -Rni "localhost\\|127.0.0.1" README.md Makefile lambda/lambda_function.py || true
```

Rien ne doit être renvoyé.

## Dépannage rapide

1) `make: No rule to make target …`

- Vérifie que tu es dans le bon dossier et que le fichier `Makefile` existe :

```bash
ls -la Makefile
```

2) `Invalid Resource identifier specified`

- IDs API Gateway invalides (cache). Solution :

```bash
make clean-api
make deploy-api
```

3) `Unable to parse response … invalid XML`

- Souvent lié à une mauvaise valeur de `AWS_ENDPOINT_URL`. Vérifie :

```bash
echo "$AWS_ENDPOINT_URL"
curl -sS "$AWS_ENDPOINT_URL/_localstack/health" | head
```

- Si ça ne répond pas → LocalStack n’est pas lancé ou le port 4566 n’est pas public.

## Commandes “one-shot” (tout dérouler)

```bash
source .venv/bin/activate
export AWS_ENDPOINT_URL="https://TON-PORT-4566.app.github.dev"
localstack start -d
make check-env
make deploy-lambda
make clean-api
make deploy-api
make test-api
```

## Résultat attendu

Une URL publique du type :

```
https://xxxx-4566.app.github.dev/restapis/<id>/dev/_user_request_/ec2
```

et tu pourras piloter l’instance EC2 via `?action=status`, `?action=stop`, `?action=start`.

---
Si tu veux, je peux :
- exécuter un test local rapide (si tu autorises l’accès à Codespaces/LocalStack),
- ou ajouter un exemple d’architecture diagramme (Mermaid) dans le README.
