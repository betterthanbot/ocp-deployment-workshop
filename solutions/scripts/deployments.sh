#!/usr/bin/env bash
# =============================================================================
# deploy-all-namespaces.sh
# Deploys the parksmap Helm chart into every user*-dev and user*-sit namespace
# in parallel. Run with:  bash deploy-all-namespaces.sh
#
# Options:
#   --dry-run     Template-only, no actual install
#   --uninstall   Uninstall existing releases instead of installing
#   --workers N   Max parallel jobs (default: 20)
# =============================================================================

# ---------- defaults ---------------------------------------------------------
CHART_DIR="../"
VALUES_DEV="${CHART_DIR}/values-dev.yaml"
VALUES_SIT="${CHART_DIR}/values-sit.yaml"
RELEASE_NAME="parksmap"
MAX_WORKERS=5
DRY_RUN=false
UNINSTALL=false
LOG_DIR="$(pwd)/deploy-logs"
FAIL_LOG="${LOG_DIR}/failed.txt"

# ---------- arg parsing ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=true    ; shift ;;
    --uninstall) UNINSTALL=true  ; shift ;;
    --workers)   MAX_WORKERS="$2"; shift; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------- sanity checks ----------------------------------------------------
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found in PATH"; exit 1; }

OC=""
command -v oc      >/dev/null 2>&1 && OC="oc"
command -v kubectl >/dev/null 2>&1 && OC="kubectl"
[ -z "$OC" ] && { echo "ERROR: neither oc nor kubectl found in PATH"; exit 1; }

[ -d "$CHART_DIR" ] || { echo "ERROR: chart dir not found: $CHART_DIR"; exit 1; }
[ -f "$VALUES_DEV" ] || { echo "ERROR: values-dev.yaml not found"; exit 1; }
[ -f "$VALUES_SIT" ] || { echo "ERROR: values-sit.yaml not found"; exit 1; }

mkdir -p "$LOG_DIR"
> "$FAIL_LOG"

# ---------- helpers ----------------------------------------------------------
log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[FAIL] $*"; }

# ---------- discover namespaces ----------------------------------------------
log "Discovering namespaces..."

DEV_NS_FILE="${LOG_DIR}/.dev_ns"
SIT_NS_FILE="${LOG_DIR}/.sit_ns"

$OC get ns -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' \
  | grep -E '^user.*-dev$' \
  | sort > "$DEV_NS_FILE"

$OC get ns -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' \
  | grep -E '^user.*-sit$' \
  | sort > "$SIT_NS_FILE"

DEV_COUNT=$(wc -l < "$DEV_NS_FILE" | tr -d ' ')
SIT_COUNT=$(wc -l < "$SIT_NS_FILE" | tr -d ' ')
TOTAL=$(( DEV_COUNT + SIT_COUNT ))

echo ""
echo "  DEV namespaces : $DEV_COUNT"
echo "  SIT namespaces : $SIT_COUNT"
echo "  Total          : $TOTAL"
echo "  Workers        : $MAX_WORKERS"
echo "  Dry run        : $DRY_RUN"
echo "  Uninstall      : $UNINSTALL"
echo ""

if [ "$TOTAL" -eq 0 ]; then
  warn "No matching namespaces found. Are you logged in as kubeadmin?"
  exit 0
fi

# ---------- per-namespace worker ---------------------------------------------
deploy_one() {
  ns="$1"
  values_file="$2"
  log_file="${LOG_DIR}/${ns}.log"

  if [ "$UNINSTALL" = "true" ]; then
    if helm status "$RELEASE_NAME" -n "$ns" >/dev/null 2>&1; then
      if helm uninstall "$RELEASE_NAME" -n "$ns" > "$log_file" 2>&1; then
        ok "$ns -- uninstalled"
      else
        err "$ns -- uninstall failed (see ${log_file})"
        echo "$ns" >> "$FAIL_LOG"
      fi
    else
      warn "$ns -- no release found, skipping"
    fi
    return
  fi

  if [ "$DRY_RUN" = "true" ]; then
    DRY_FLAG="--dry-run"
  else
    DRY_FLAG=""
  fi

  if helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
      --namespace "$ns" \
      --values "$values_file" \
      --set "namespace=${ns}" \
      --timeout 5m \
      --atomic \
      --wait \
      $DRY_FLAG > "$log_file" 2>&1; then
    ok "$ns -- deployed"
  else
    err "$ns -- FAILED (see ${log_file})"
    echo "$ns" >> "$FAIL_LOG"
  fi
}

# ---------- parallel runner --------------------------------------------------
run_all() {
  values_file="$1"
  ns_file="$2"
  active=0

  while IFS= read -r ns; do
    [ -z "$ns" ] && continue
    deploy_one "$ns" "$values_file" &

    active=$(( active + 1 ))

    if [ "$active" -ge "$MAX_WORKERS" ]; then
      wait
      active=0
    fi
  done < "$ns_file"

  wait
}

# ---------- run DEV ----------------------------------------------------------
if [ "$DEV_COUNT" -gt 0 ]; then
  log "Starting DEV installs ($DEV_COUNT namespaces, $MAX_WORKERS workers)..."
  run_all "$VALUES_DEV" "$DEV_NS_FILE"
fi

# ---------- run SIT ----------------------------------------------------------
if [ "$SIT_COUNT" -gt 0 ]; then
  log "Starting SIT installs ($SIT_COUNT namespaces, $MAX_WORKERS workers)..."
  run_all "$VALUES_SIT" "$SIT_NS_FILE"
fi

# ---------- summary ----------------------------------------------------------
echo ""
log "============= SUMMARY ============="

FAILED_COUNT=0
[ -s "$FAIL_LOG" ] && FAILED_COUNT=$(wc -l < "$FAIL_LOG" | tr -d ' ')
PASSED=$(( TOTAL - FAILED_COUNT ))

ok "Attempted : $TOTAL"
ok "Succeeded : $PASSED"

if [ "$FAILED_COUNT" -gt 0 ]; then
  err "Failed    : $FAILED_COUNT"
  err "Failed namespaces:"
  while IFS= read -r ns; do
    err "  - $ns  ->  ${LOG_DIR}/${ns}.log"
  done < "$FAIL_LOG"
  echo ""
  log "To retry only failed namespaces:"
  echo "  while IFS= read -r ns; do"
  echo "    helm upgrade --install parksmap ./solutions -n \"\$ns\" --set namespace=\"\$ns\" --wait --atomic"
  echo "  done < $FAIL_LOG"
  exit 1
else
  ok "All installs completed successfully!"
fi

log "Logs in: $LOG_DIR"