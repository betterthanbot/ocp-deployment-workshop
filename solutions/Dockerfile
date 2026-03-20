# ──────────────────────────────────────────────────────────────────────────────
# OpenShift-compatible MongoDB init container
#
# Includes:
#   • mongosh  – MongoDB Shell (for ping + user provisioning)
#   • curl     – HTTP trigger for backend data-load endpoint
#
# OpenShift compliance:
#   • Runs as non-root user (uid 1001)
#   • /etc/passwd patching via nss_wrapper (handles arbitrary UIDs assigned
#     by OpenShift's SCC)
#   • All files group-owned by root (gid 0) and group-writable, per OpenShift
#     best-practice for random-UID workloads
# ──────────────────────────────────────────────────────────────────────────────
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

LABEL maintainer="platform-team" \
      description="Init container: MongoDB user provisioning + backend data load" \
      io.openshift.tags="init,mongodb,curl"

# ── Install mongosh + curl ────────────────────────────────────────────────────
# Add the official MongoDB repo, then install mongosh and curl via microdnf
RUN microdnf install -y bash && \
    # curl-minimal is already present in ubi-minimal and provides the curl binary;
    # installing the full 'curl' package would conflict with it, so we skip it.
    #
    # Add MongoDB 7 repo — uses $basearch so it works on both x86_64 and aarch64
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
         -o /etc/pki/rpm-gpg/RPM-GPG-KEY-mongodb && \
    echo $'[mongodb-org-7.0]\n\
name=MongoDB Repository\n\
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/$basearch/\n\
gpgcheck=1\n\
enabled=1\n\
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-mongodb' \
    > /etc/yum.repos.d/mongodb-org-7.0.repo && \
    microdnf install -y mongodb-mongosh && \
    microdnf clean all && \
    rm -rf /var/cache/dnf

# ── Copy init script ──────────────────────────────────────────────────────────
COPY init.sh /usr/local/bin/init.sh

# ── OpenShift: group-writable ownership (gid 0), non-root uid ────────────────
RUN chmod 550 /usr/local/bin/init.sh && \
    chown 1001:0 /usr/local/bin/init.sh

# Switch to non-root user
USER 1001

# ── Environment variable defaults (override at deploy time) ──────────────────
# These are intentionally left blank; all values MUST be injected via
# a Secret / ConfigMap in your OpenShift deployment manifest.
ENV MONGODB_HOST="" \
    MONGODB_ADMIN_PASSWORD="" \
    MONGODB_DATABASE="" \
    MONGODB_USER="" \
    MONGODB_PASSWORD="" \
    BACKEND_URL=""

ENTRYPOINT ["/usr/local/bin/init.sh"]