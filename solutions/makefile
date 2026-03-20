# Nothing to see here :)
dev:
	helm template \
	parksmap \
	--values=values-dev.yaml \
	./ \
	> parksmap-dev.yaml

sit:
	helm template \
	parksmap \
	--values=values-sit.yaml \
	./ \
	> parksmap-sit.yaml

installdev:
	helm install \
	parksmap \
	./ \
	--values=values-dev.yaml 

installsit:
	helm install \
	parksmap \
	./ \
	--values=values-sit.yaml

uninstalldev:
	helm uninstall \
	parksmap

uninstallsit:	
	helm uninstall \
	parksmap 