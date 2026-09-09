#!/bin/sh
# ---------------------------------------------------------------------------
# patch-redis-auth.sh — live-patch for Appwrite 2.0.0 task-scheduler
#
# Fixes: "[StatsResources] Failed to publish stats resources message:
#         NOAUTH Authentication required" when using password-protected
#         external Redis.
#
# Root cause (upstream, two layers):
#   1. app/init/registers.php builds the publisher pool as
#      Queue\Connection\Redis($host, $port) — credentials dropped.
#   2. utopia-php/queue's Connection\Redis never calls auth(), even when
#      user/password are provided.
#
# This patch injects auth (from the container's own _APP_REDIS_* env) into
# the vendored queue library inside the RUNNING task-scheduler container.
#
# Usage (on the Docker host):
#   sh patch-redis-auth.sh
#
# IMPORTANT: the patch lives inside the container — a Coolify redeploy or
# image change recreates the container and wipes it. Re-run after each
# redeploy until an upstream release carries the fix (then delete this).
# ---------------------------------------------------------------------------

set -e

CID=$(docker ps -qf name=task-scheduler)
if [ -z "$CID" ]; then
    echo "ERROR: no running container matching 'task-scheduler' found." >&2
    exit 1
fi
echo "Patching container $CID ..."

docker exec -i "$CID" php <<'PHP'
<?php
$f = '/usr/src/code/vendor/utopia-php/queue/src/Queue/Connection/Redis.php';
$c = @file_get_contents($f);
if ($c === false) { echo "FILE NOT FOUND\n"; exit(1); }
if (strpos($c, 'APPREDIS_PATCH') !== false) { echo "already patched\n"; exit(0); }
$new = preg_replace(
    '/(\$redis->connect\([^;]*\);)/s',
    "$1\n                \$awp = getenv('_APP_REDIS_PASS'); \$awu = getenv('_APP_REDIS_USER');\n                if (\$awp) { \$awu ? \$redis->auth([\$awu, \$awp]) : \$redis->auth(\$awp); } /*APPREDIS_PATCH*/",
    $c, 1, $count);
if ($count !== 1) { echo "PATCH FAILED: connect() call not found\n"; exit(1); }
file_put_contents($f, $new);
echo "patched OK\n";
PHP

echo "Restarting container ..."
docker restart "$CID"

echo ""
echo "Done. Verify with:"
echo "  docker logs --tail 20 $CID"
echo "Success = stats_resources_task with projects_failed 0 and no NOAUTH line."
