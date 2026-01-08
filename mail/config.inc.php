<?php
$config['db_dsnw'] = 'sqlite:////var/roundcube/db/sqlite.db';
$config['proxy_whitelist'] = ['*', 'localhost', '127.0.0.1'];
$config['use_https'] = true;
$config['default_host'] = 'mail.netzor.pt';
$config['smtp_server'] = 'mail.netzor.pt';
$config['smtp_port'] = 25;
$config['imap_port'] = 143;
$config['imap_conn_options'] = [
  'ssl' => [
     'verify_peer' => false,
     'verify_peer_name' => false,
     'allow_self_signed' => true
   ]
];
$config['smtp_conn_options'] = [
  'ssl' => [
     'verify_peer' => false,
     'verify_peer_name' => false,
     'allow_self_signed' => true
   ]
];

['temp_dir'] = '/var/www/html/temp/';
['log_dir'] = '/var/www/html/logs/';
['drafts_mbox'] = 'Drafts';
['junk_mbox'] = 'Junk';
['sent_mbox'] = 'Sent';
['trash_mbox'] = 'Trash';
['archive_mbox'] = 'Archive';

$config['plugins'] = array_filter(array_map('trim', explode(',', getenv('ROUNDCUBEMAIL_PLUGINS') ?: '')));

// Debugging
$config['debug_level'] = 1;
$config['log_driver'] = 'stdout';
$config['imap_debug'] = true;
$config['smtp_debug'] = true;
// OAuth2 Configuration - Read from Env
$config['oauth_provider'] = getenv('ROUNDCUBEMAIL_OAUTH_PROVIDER');
$config['oauth_provider_name'] = getenv('ROUNDCUBEMAIL_OAUTH_PROVIDER_NAME');
$config['oauth_client_id'] = getenv('ROUNDCUBEMAIL_OAUTH_CLIENT_ID');
$config['oauth_client_secret'] = getenv('ROUNDCUBEMAIL_OAUTH_CLIENT_SECRET');
$config['oauth_auth_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_AUTH_URI');
$config['oauth_token_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_TOKEN_URI');
$config['oauth_identity_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_IDENTITY_URI');
$config['oauth_verify_peer'] = filter_var(getenv('ROUNDCUBEMAIL_OAUTH_VERIFY_PEER'), FILTER_VALIDATE_BOOLEAN);
$config['oauth_scope'] = getenv('ROUNDCUBEMAIL_OAUTH_SCOPE');
$config['oauth_identity_fields'] = array_filter(array_map('trim', explode(',', getenv('ROUNDCUBEMAIL_OAUTH_IDENTITY_FIELDS') ?: 'email')));
$config['oauth_login_redirect'] = filter_var(getenv('ROUNDCUBEMAIL_OAUTH_LOGIN_REDIRECT'), FILTER_VALIDATE_BOOLEAN);

