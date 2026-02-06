SHELL := /bin/bash

AWS_ENDPOINT_URL ?=
AWS_REGION ?= us-east-1
STAGE ?= dev

AWSL := awslocal --no-verify-ssl --endpoint-url="$(AWS_ENDPOINT_URL)"
OUTDIR := .out

REST_API_ID_FILE := $(OUTDIR)/rest_api_id
ROOT_ID_FILE := $(OUTDIR)/root_id
RESOURCE_ID_FILE := $(OUTDIR)/resource_id
API_URL_FILE := $(OUTDIR)/api_url

.PHONY: help check-env package-lambda deploy-lambda test-lambda deploy-api test-api show clean-api

help:
	@echo "Usage:"
	@echo "  export AWS_ENDPOINT_URL=https://xxxx-4566.app.github.dev"
	@echo "  make deploy-lambda deploy-api test-api"
	@echo
	@echo "Targets:"
	@echo "  check-env     - verify endpoint reachable"
	@echo "  deploy-lambda - package + update lambda code"
	@echo "  test-lambda   - invoke lambda directly (status)"
	@echo "  deploy-api    - create/reuse API Gateway + link to lambda"
	@echo "  test-api      - call API (status/stop/start)"
	@echo "  show          - print saved API URL"
	@echo "  clean-api     - delete saved API ids (forces re-create)"

check-env:
	@test -n "$(AWS_ENDPOINT_URL)" || (echo "ERROR: set AWS_ENDPOINT_URL"; exit 1)
	@$(AWSL) sts get-caller-identity >/dev/null && echo "OK endpoint"

package-lambda:
	@cd lambda && zip -r function.zip lambda_function.py >/dev/null
	@echo "OK lambda packaged"

deploy-lambda: check-env package-lambda
	@$(AWSL) lambda update-function-code --function-name ec2-controller --zip-file fileb://lambda/function.zip >/dev/null
	@echo "OK lambda updated"

test-lambda: check-env
	@$(AWSL) lambda invoke --function-name ec2-controller --payload '{"queryStringParameters":{"action":"status"}}' /tmp/out.json >/dev/null
	@cat /tmp/out.json && echo

deploy-api: check-env
	@mkdir -p $(OUTDIR)
	@bash -eu -o pipefail -c '\
	if [ -f "$(REST_API_ID_FILE)" ]; then \
		REST_API_ID=$$(cat "$(REST_API_ID_FILE)"); \
		echo "Reusing REST_API_ID=$$REST_API_ID"; \
	else \
		REST_API_ID=$$($(AWSL) apigateway create-rest-api --name "ec2-api" | python -c "import sys,json;print(json.load(sys.stdin)[\"id\"])"); \
		echo "$$REST_API_ID" > "$(REST_API_ID_FILE)"; \
		echo "Created REST_API_ID=$$REST_API_ID"; \
	fi; \
	if [ -f "$(ROOT_ID_FILE)" ]; then \
		ROOT_ID=$$(cat "$(ROOT_ID_FILE)"); \
	else \
		ROOT_ID=$$($(AWSL) apigateway get-resources --rest-api-id $$REST_API_ID | python -c "import sys,json;print(json.load(sys.stdin)[\"items\"][0][\"id\"])"); \
		echo "$$ROOT_ID" > "$(ROOT_ID_FILE)"; \
	fi; \
	if [ -f "$(RESOURCE_ID_FILE)" ]; then \
		RESOURCE_ID=$$(cat "$(RESOURCE_ID_FILE)"); \
	else \
		RESOURCE_ID=$$($(AWSL) apigateway create-resource --rest-api-id $$REST_API_ID --parent-id $$ROOT_ID --path-part ec2 | python -c "import sys,json;print(json.load(sys.stdin)[\"id\"])"); \
		echo "$$RESOURCE_ID" > "$(RESOURCE_ID_FILE)"; \
	fi; \
	$(AWSL) apigateway put-method --rest-api-id $$REST_API_ID --resource-id $$RESOURCE_ID --http-method GET --authorization-type NONE >/dev/null; \
	$(AWSL) apigateway put-integration --rest-api-id $$REST_API_ID --resource-id $$RESOURCE_ID --http-method GET \
		--type AWS_PROXY --integration-http-method POST \
		--uri "arn:aws:apigateway:$(AWS_REGION):lambda:path/2015-03-31/functions/arn:aws:lambda:$(AWS_REGION):000000000000:function:ec2-controller/invocations" >/dev/null; \
	$(AWSL) lambda add-permission --function-name ec2-controller --statement-id apigw --action lambda:InvokeFunction --principal apigateway.amazonaws.com >/dev/null 2>&1 || true; \
	$(AWSL) apigateway create-deployment --rest-api-id $$REST_API_ID --stage-name $(STAGE) >/dev/null; \
	echo "$(AWS_ENDPOINT_URL)/restapis/$$REST_API_ID/$(STAGE)/_user_request_/ec2" > "$(API_URL_FILE)"; \
	echo "API_URL=$$(cat "$(API_URL_FILE)")"; \
	'

test-api: check-env
	@test -f "$(API_URL_FILE)" || (echo "Run: make deploy-api first"; exit 1)
	@API_URL=$$(cat "$(API_URL_FILE)"); \
	echo $$API_URL; \
	curl -s "$$API_URL?action=status" && echo; \
	curl -s "$$API_URL?action=stop" && echo; \
	curl -s "$$API_URL?action=start" && echo

show:
	@test -f "$(API_URL_FILE)" || (echo "No API URL yet. Run: make deploy-api"; exit 1)
	@cat "$(API_URL_FILE)" && echo

clean-api:
	@rm -f "$(REST_API_ID_FILE)" "$(ROOT_ID_FILE)" "$(RESOURCE_ID_FILE)" "$(API_URL_FILE)"
	@echo "OK removed saved API ids (next deploy-api will recreate)"