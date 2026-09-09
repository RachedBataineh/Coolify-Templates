<?php
/**
 * Patches the vendored utopia-php/queue Redis connection inside the
 * appwrite/appwrite image so the queue publisher authenticates when
 * _APP_REDIS_USER / _APP_REDIS_PASS are set.
 *
 * Used by Dockerfile.appwrite-redisauth. Safe to run on any version:
 * idempotent (marker check) and fails loudly if the patch target moves.
 */
$f = '/usr/src/code/vendor/utopia-php/queue/src/Queue/Connection/Redis.php';
$c = @file_get_contents($f);
if ($c === false) {
    fwrite(STDERR, "patch target not found: {$f}\n");
    exit(1);
}
if (strpos($c, 'APPREDIS_PATCH') !== false) {
    echo "already patched\n";
    exit(0);
}
$new = preg_replace(
    '/(\$redis->connect\([^;]*\);)/s',
    "$1\n                \$awp = getenv('_APP_REDIS_PASS'); \$awu = getenv('_APP_REDIS_USER');\n                if (\$awp) { \$awu ? \$redis->auth([\$awu, \$awp]) : \$redis->auth(\$awp); } /*APPREDIS_PATCH*/",
    $c, 1, $count);
if ($count !== 1) {
    fwrite(STDERR, "patch failed: connect() call not found — upstream file changed, update the patch\n");
    exit(1);
}
file_put_contents($f, $new);
echo "patched OK\n";
