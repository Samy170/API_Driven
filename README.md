ATELIER API-DRIVEN INFRASTRUCTURE (LocalStack + Lambda + API Gateway)
Objectif
Mettre en place une architecture API-driven :
une requête HTTP (GET) déclenche, via API Gateway + Lambda, une action d’infrastructure sur une instance EC2 (démarrer / arrêter / connaître le statut).
Tout est exécuté dans un GitHub Codespace et les services AWS sont émulés par LocalStack.
✅ Contrainte respectée : aucune dépendance à localhost (on utilise l’URL publique du port 4566).

Architecture
Client HTTP (curl / navigateur)
API Gateway (endpoint public)
Lambda (code Python)
EC2 (LocalStack)
Flux :
HTTP GET /ec2?action=status|start|stop → API Gateway → Lambda → EC2 LocalStack

Prérequis
Avoir un Codespace lancé sur ce repo
Avoir python3, pip, make, zip disponibles (dans Codespaces c’est OK)
Étape 1 — Lancer LocalStack
1.1 Installer LocalStack (si pas déjà fait)
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install localstack awscli-local boto3
1.2 Démarrer LocalStack
localstack start -d
1.3 Vérifier que LocalStack tourne
localstack status services

Étape 2 — Rendre public le port 4566 (IMPORTANT)
Dans GitHub Codespaces : onglet PORTS
Repérer le port 4566
Le passer en Public
Copier l’URL générée, par exemple :
https://xxxxxx-4566.app.github.dev
Cette URL est ton endpoint AWS LocalStack (pas de localhost).
2.1 Exporter la variable d’environnement
export AWS_ENDPOINT_URL="https://TON-PORT-4566.app.github.dev"
2.2 Vérifier la santé LocalStack via HTTP
curl -sS "$AWS_ENDPOINT_URL/_localstack/health" | head
Tu dois voir apigateway, lambda, ec2, sts en running/available.

Étape 3 — Vérifier le code Lambda
Le fichier est ici :
lambda/lambda_function.py
Il expose une fonction handler qui lit :
AWS_ENDPOINT_URL (endpoint LocalStack public)
INSTANCE_ID (instance EC2 ciblée)
AWS_REGION (par défaut us-east-1)
Il attend un paramètre query :
?action=start
?action=stop
?action=status

Étape 4 — Automatisation avec Makefile
Ce repo fournit un Makefile qui automatise :
packaging lambda
déploiement lambda
création API Gateway
test complet via curl

4.1 Voir l’aide
make help
4.2 Vérifier l’endpoint (LocalStack public)
make check-env
Étape 5 — Déployer / mettre à jour la Lambda
make deploy-lambda

Ce que ça fait :
zip le fichier lambda_function.py
met à jour la fonction Lambda ec2-controller dans LocalStack
Test direct Lambda (sans API Gateway)
make test-lambda
Tu dois obtenir un JSON avec state: running|stopped.

Étape 6 — Déployer l’API Gateway
make clean-api
make deploy-api
Pourquoi clean-api ?
Parce que l’API Gateway crée des IDs (rest_api_id, resource_id…).
Si tu redémarres ou changes d’environnement, certains IDs peuvent devenir invalides.
Après deploy-api, le Makefile affiche un API_URL=... et l’enregistre dans :
.out/api_url

Étape 7 — Tester l’API HTTP (scénario complet)
make test-api
Résultat attendu (exemple) :
status → {"instance": "...", "state": "running"}
stop → {"action": "stop", "instance": "..."}
start → {"action": "start", "instance": "..."}
Test manuel (optionnel)
API_URL="$(cat .out/api_url)"
curl -s "$API_URL?action=status" && echo
curl -s "$API_URL?action=stop" && echo
curl -s "$API_URL?action=start" && echo
Étape 8 — Vérifier la contrainte “pas de localhost”
grep -Rni "localhost\|127.0.0.1" README.md Makefile lambda/lambda_function.py || true

Rien ne doit sortir.

Dépannage rapide
1) make: No rule to make target …

Vérifie que tu es dans le bon dossier et que le fichier s’appelle bien Makefile (pas Makerfile) :

ls -la Makefile
2) Invalid Resource identifier specified
Tu as des IDs API Gateway invalides (cache). Fais :

make clean-api
make deploy-api
3) Unable to parse response … invalid XML

Souvent causé par une mauvaise URL endpoint.
Vérifie AWS_ENDPOINT_URL :

echo "$AWS_ENDPOINT_URL"
curl -sS "$AWS_ENDPOINT_URL/_localstack/health" | head

Si ça ne répond pas → le port 4566 n’est pas public ou LocalStack n’est pas lancé.

Commandes “one-shot” (tout dérouler)
source .venv/bin/activate
export AWS_ENDPOINT_URL="https://TON-PORT-4566.app.github.dev"
localstack start -d
make check-env
make deploy-lambda
make clean-api
make deploy-api
make test-api
Résultat final
Tu obtiens une URL publique du type :
https://xxxx-4566.app.github.dev/restapis/<id>/dev/_user_request_/ec2
Et tu peux piloter l’instance EC2 via :
?action=status
?action=stop
?action=start