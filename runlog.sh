#!/usr/bin/env bash
# Tiny command logger: records every command and its output to log.log so the
# whole run is reproducible/auditable after the fact.
#   usage: ./runlog.sh "step description" 'command string'
set -o pipefail
LOG=${LOG:-/home/user/qwen2/log.log}
{
  echo ""
  echo "################################################################################"
  echo "# $1"
  echo "# [$(date -Is)]"
  echo "################################################################################"
  echo "\$ $2"
} >> "$LOG"
bash -c "$2" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
echo "# [$(date -Is)] exit=$rc" >> "$LOG"
exit $rc
