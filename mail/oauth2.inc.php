<?php
// Usa HTTPS nos URLs gerados (necessário quando atrás de reverse proxy)
// use_https diz ao Roundcube para gerar URLs HTTPS sem causar redirect loop
$config['use_https'] = true;

$config['oauth_provider'] = 'generic';
$config['oauth_provider_name'] = 'Keycloak';
$config['oauth_client_id'] = '${ROUNDCUBE_OIDC_CLIENT_ID}';
$config['oauth_client_secret'] = '${ROUNDCUBE_OIDC_CLIENT_SECRET}';
$config['oauth_auth_uri'] = 'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/auth';
$config['oauth_token_uri'] = 'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token';
$config['oauth_identity_uri'] = 'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo';

// Optional: disable SSL certificate check on HTTP requests to OAuth server. For possible values, see:
// http://docs.guzzlephp.org/en/stable/request-options.html#verify
$config['oauth_verify_peer'] = false;

$config['oauth_scope'] = 'email profile';
$config['oauth_identity_fields'] = ['email'];

// Boolean: automatically redirect to OAuth login when opening Roundcube without a valid session
$config['oauth_login_redirect'] = true;