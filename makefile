# Nothing to see here :)
dev:
	helm template \
	parksmap \
	--set=namespace=user1-dev\
	--values=values-dev.yaml \
	./ \
	> parksmap-dev.yaml

sit:
	helm template \
	parksmap \
	--set=namespace=user1-sit \
	--values=values-sit.yaml \
	./ \
	> parksmap-sit.yaml

installdev:
	helm install \
	parksmap \
	./ \
	--namespace=user1-dev \
	--values=values-dev.yaml 

installsit:
	helm install \
	parksmap \
	./ \
	--namespace=user1-sit \
	--values=values-sit.yaml

uninstalldev:
	helm uninstall \
	parksmap \
	--namespace=user1-dev	

uninstallsit:	
	helm uninstall \
	parksmap \
	--namespace=user1-sit