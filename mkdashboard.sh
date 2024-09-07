#!/usr/bin/env bash
set -eo pipefail

fail() {
    echo "$@" 2>&1
    exit 1
}

# ./mkdashboard.sh file.json
main() {
  local RESULT
  command -v sd > /dev/null || fail "sd must be installed"
  command -v jq > /dev/null || fail "jq must be installed"
  command -v sed > /dev/null || fail "sed must be installed" # TODO: mac sed?

  # Read from file if given
  if [ -f "$1" ]; then
    RESULT="$(cat "$1")"
  else
    # clipboard assumed
    if command -v xclip; then
      RESULT="$(xclip -o)"
    elif command -v wl-paste; then
      RESULT="$(wl-paste -o)"
    else
      RESULT="$(pbpaste)"
    fi
  fi

  # For consistency ensure dashboard datasources always say just "Prometheus"
  # shellcheck disable=SC2001
  RESULT="$(echo "${RESULT}" | sed 's/\"datasource\"\: null\,/\"datasource\"\: \"Prometheus\",/g')"

  # NB: Not using folders because uids are not consistent across grafana replicas
  # Use tags in dashboards instead.
  # https://github.com/grafana/grafana/issues/46782

  local -r DBUID="$(echo "${RESULT}" | jq ".uid" -r)"
  test -n "${DBUID}" || fail "uid field must be set"
  # Make dashboard title usable as a file name in git + grafana
  DBNAME="$(echo "${RESULT}" | jq -r '.title | ascii_downcase')"
  DBNAME="${DBNAME//[^a-zA-Z0-9]/}" # sanitize
  # Indent dashboard content as json
  local -r DBCONTENT_YAML="$(echo "${RESULT}" | yq | sed 's/^/    /')"
  # Minify the content if it's > 250k characters to try to avoid 1MB etcd object size limit
  if [ "${#DBCONTENT_YAML}" -gt 250000 ]; then
    DBCONTENT="  ${DBNAME}.json: $(echo "${RESULT}" | jq -c "@json")"
  else
    DBCONTENT="  \"${DBNAME}.json\": |-"
    DBCONTENT="${DBCONTENT}"$'\n'"${DBCONTENT_YAML}"
  fi
  cat << EOF > "./deploy/dashboards/${DBNAME}.yaml"
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: monitoring
  name: grafana-dashboard-${DBNAME}
  labels:
    grafana_dashboard: "1"
data:
${DBCONTENT}
EOF
}
# shellcheck disable=SC2068
main $@