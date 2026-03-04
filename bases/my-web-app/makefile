.PHONY: template save-images pack-images push-images clean
helm: add fetch deployment

SYNC_YAML       ?= skopeo.yaml
SYNC_DIR        ?= ./offline-image-data
TAR_FILE        ?= offline-images.tar.gz
MIRROR_REGISTRY ?= registry.disconnected.local:5000/my-project

fetch:
	vendir sync -f vendir.yml

# 1. Build your Helm Templates
template:
	helm template \
	my-web-app \
	--values=values.yaml \
	vendor/ \
	> deployment.yaml

# 2. Repo to Disk (Reads the YAML and pulls deduplicated layers)
save-images:
	@echo "Syncing images from $(SYNC_YAML) to local directory $(SYNC_DIR)..."
	mkdir -p $(SYNC_DIR)
	skopeo sync --src yaml --dest dir $(SYNC_YAML) $(SYNC_DIR)
	@echo "Images successfully synced to disk."

# 3. Create a single Tarball for the USB drive / secure transfer
pack-images: save-images
	@echo "Compressing downloaded layers into $(TAR_FILE)..."
	tar -czvf $(TAR_FILE) $(SYNC_DIR)
	@echo "Success! $(TAR_FILE) is ready to be moved to the disconnected environment."

# 4. Disk to Mirror Repo (Run this inside the disconnected environment)
# Note: Ensure you have extracted the tarball first! (tar -xzvf offline-images.tar.gz)
push-images:
	@echo "Syncing images from $(SYNC_DIR) to $(MIRROR_REGISTRY)..."
	skopeo sync \
		--src dir \
		--dest docker \
		--dest-tls-verify=false \
		$(SYNC_DIR) \
		$(MIRROR_REGISTRY)
	@echo "All images pushed to $(MIRROR_REGISTRY)."

# Cleanup local artifacts
clean:
	rm -rf $(SYNC_DIR) $(TAR_FILE) deployment.yaml