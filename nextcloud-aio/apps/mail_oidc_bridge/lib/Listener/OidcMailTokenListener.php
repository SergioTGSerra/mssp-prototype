<?php

declare(strict_types=1);

namespace OCA\MailOidcBridge\Listener;

use OCA\Mail\Events\BeforeImapClientCreated;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\Security\ICrypto;
use Psr\Log\LoggerInterface;

/**
 * Listener that injects OIDC tokens from user_oidc into Mail accounts
 * This enables XOAUTH2 authentication with generic OIDC providers like Keycloak
 */
class OidcMailTokenListener implements IEventListener {

    public function __construct(
        private ICrypto $crypto,
        private LoggerInterface $logger
    ) {}

    public function handle(Event $event): void {
        $this->logger->debug('[MailOidcBridge] handle() called');
        
        if (!($event instanceof BeforeImapClientCreated)) {
            return;
        }

        $account = $event->getAccount();
        $mailAccount = $account->getMailAccount();

        $this->logger->info('[MailOidcBridge] Processing mail account', [
            'email' => $mailAccount->getEmail(),
            'auth_method' => $mailAccount->getAuthMethod(),
            'inbound_host' => $mailAccount->getInboundHost()
        ]);

        // Only process xoauth2 accounts
        if ($mailAccount->getAuthMethod() !== 'xoauth2') {
            $this->logger->debug('[MailOidcBridge] Skipping non-xoauth2 account');
            return;
        }

        // Skip Google and Microsoft accounts (they have their own handlers)
        $inboundHost = $mailAccount->getInboundHost();
        if (str_contains($inboundHost, 'gmail.com') || 
            str_contains($inboundHost, 'outlook.') || 
            str_contains($inboundHost, 'office365.')) {
            $this->logger->debug('[MailOidcBridge] Skipping Google/Microsoft account');
            return;
        }

        try {
            // Get TokenService from container dynamically to avoid DI issues
            $tokenService = \OC::$server->get(\OCA\UserOIDC\Service\TokenService::class);
            
            if ($tokenService === null) {
                $this->logger->warning('[MailOidcBridge] TokenService not available');
                return;
            }
            
            // Get token from user_oidc
            $token = $tokenService->getToken(true);
            
            if ($token === null) {
                $this->logger->warning('[MailOidcBridge] No OIDC token available for user');
                return;
            }

            $accessToken = $token->getAccessToken();
            
            if (empty($accessToken)) {
                $this->logger->warning('[MailOidcBridge] OIDC access token is empty');
                return;
            }

            $this->logger->info('[MailOidcBridge] Got access token, length: ' . strlen($accessToken));
            
            // Decode JWT to check audience
            $parts = explode('.', $accessToken);
            if (count($parts) === 3) {
                $payload = json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true);
                $this->logger->info('[MailOidcBridge] JWT claims - aud: ' . json_encode($payload['aud'] ?? 'NOT_SET') . ', azp: ' . ($payload['azp'] ?? 'NOT_SET'));
            }

            // Encrypt and set the token
            $encryptedToken = $this->crypto->encrypt($accessToken);
            $mailAccount->setOauthAccessToken($encryptedToken);
            
            $this->logger->info('[MailOidcBridge] Successfully injected OIDC token into mail account', [
                'account_id' => $mailAccount->getId(),
                'email' => $mailAccount->getEmail()
            ]);
            
        } catch (\Exception $e) {
            $this->logger->error('[MailOidcBridge] Failed to inject OIDC token: ' . $e->getMessage(), [
                'exception' => $e
            ]);
        }
    }
}
