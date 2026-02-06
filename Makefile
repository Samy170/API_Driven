SHELL := /bin/bash

AWS_ENDPOINT_URL ?=
AWS_REGION ?= us-east-1
STAGE ?= dev

AWSL := awslocal --no-verify-ssl --endpoint-url="$(AWS_ENDPOINT_URL)"
OUTDIR := .out

.PHONY: help check-env package-lambda deploy-lambda test-lambda deploy-api test-api

help:
	@echo "Usage:"
	@echo "  export AWS_ENDPOINT_URL=https://xxxx-4566.app.github.dev"
	@echo "  make deploy-lambda deploy-api test-api"

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
	@cat /tmp/out.json

deploy-api: check-env
	@REST_API_ID=$$($(AWSL) apigateway create-rest-api --name "ec2-api" | python -c "import sys,json;print(json.load(sys.stdin)['id'])"); \
	ROOT_ID=$$($(AWSL) apigateway get-resources --rest-api-id $$REST_API_ID | python -c "import sys,json;print(json.load(sys.stdin)['items'][0]['id'])"); \
	RESOURCE_ID=$$($(AWSL) apigateway create-resource --rest-api-id $$REST_API_ID --parent-id $$ROOT_ID --path-part ec2 | python -c "import sys,json;print(json.load(sys.stdin)['id'])"); \
	$(AWSL) apigateway put-method --rest-api-id $$REST_API_ID --resource-id $$RESOURCE_ID --http-method GET --authorization-type NONE >/dev/null; \
	$(AWSL) apigateway put-integration --rest-api-id $$REST_API_ID --resource-id $$RESOURCE_ID --http-method GET \
	  --type AWS_PROXY --integration-http-method POST \
	  --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations" >/dev/null; \
	$(AWSL) lambda add-permission --function-name ec2-controller --statement-id apigw --action lambda:InvokeFunction --principal apigateway.amazonaws.com >/dev/null 2>&1 || true; \
	$(AWSL) apigateway create-deployment --rest-api-id $$REST_API_ID --stage-name $(STAGE) >/dev/null; \
	mkdir -p $(OUTDIR); \
	echo "$(AWS_ENDPOINT_URL)/restapis/$$REST_API_ID/$(STAGE)/_user_request_/ec2" > $(OUTDIR)/api_url; \
	echo "API_URL=$$(cat $(OUTDIR)/api_url)"

test-api: check-env
	@test -f $(OUTDIR)/api_url || (echo "Run: make deploy-api first"; exit 1)
	@API_URL=$$(cat $(OUTDIR)/api_url); \
	echo $$API_URL; \
	curl -s "$$API_URL?action=status" && echo; \
	curl -s "$$API_URL?action=stop" && echo; \
	curl -s "$$API_URL?action=start" && echo
