helm: add fetch deployment

HELM_CHART_NAME := stackrox/
HELM_CHART_PRODUCT := stackrox-secured-cluster-services
HELM_CHART_VERSION := 400.5.2

add:
	helm repo add stackrox https://raw.githubusercontent.com/stackrox/helm-charts/main/opensource/
	helm repo update

fetch:
	helm fetch \
		$(HELM_CHART_NAME)$(HELM_CHART_PRODUCT) \
		--version $(HELM_CHART_VERSION) \
		--untar \
		--untardir vendor/$(HELM_CHART_VERSION)

deployment:
	helm template $(HELM_RELEASE_NAME) \
	--namespace=stackrox \
	--values=values.yaml \
	--set clusterName=test \
    --set centralEndpoint=test \
	vendor/$(HELM_CHART_VERSION)/$(HELM_CHART_PRODUCT) > $(HELM_CHART_VERSION)-$(HELM_CHART_PRODUCT)-deployment.yaml