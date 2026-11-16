<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$config = require __DIR__ . '/photobooth_private/photobooth_config.php';
$deleted = 0;
foreach (glob($config['storage_dir'] . '/*_*.*') ?: [] as $file) {
    if (preg_match('/^[a-f0-9]{32}_([0-9]{10})\.(jpg|png|gif|mp4)$/', basename($file), $match) &&
        (int)$match[1] <= time() &&
        unlink($file)) {
        $deleted++;
    }
}

fwrite(STDOUT, 'Deleted ' . $deleted . " expired photo(s).\n");
