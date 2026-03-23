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
	--values=values-sit.yaml \

uninstalldev:
	helm uninstall \
	parksmap

uninstallsit:
	helm uninstall \
	parksmap 

podmanbuild:
	podman build \                                        
	--platform linux/amd64 \
	-t quay.io/rhn-support-gong/mongo-init:latest .

podmanpush:
	podman push quay.io/rhn-support-gong/mongo-init:latest