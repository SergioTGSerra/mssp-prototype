<?php

declare(strict_types=1);

namespace OCA\MailOidcBridge\Listener;

use OCA\Mail\Db\MailAccount;
use OCA\Mail\Db\MailAccountMapper;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\User\Events\UserLoggedInEvent;
use Psr\Log\LoggerInterface;

/**
 * Listener that updates provisioned mail accounts for OIDC users to use XOAUTH2
 * Works with Mail app's native provisioning - just changes auth_method to xoauth2
 */
class UserLoggedInListener implements IEventListener {

    public function __construct(
        private MailAccountMapper $mailAccountMapper,
        private LoggerInterface $logger
    ) {}

    public function handle(Event $event): void {
        if (!($event instanceof UserLoggedInEvent)) {
            return;
        }

        $user = $event->getUser();
        $userId = $user->getUID();

        $this->logger->info('[MailOidcBridge] UserLoggedInEvent received', ['user_id' => $userId]);

        // Only process OIDC users
        $backend = $user->getBackendClassName();
        $this->logger->info('[MailOidcBridge] User backend: ' . $backend);
        
        if ($backend !== 'OCA\\UserOIDC\\User\\Backend' && $backend !== 'user_oidc') {
            $this->logger->info('[MailOidcBridge] Not OIDC user, skipping');
            return;
        }

        // Find user's mail accounts and update to xoauth2
        try {
            $accounts = $this->mailAccountMapper->findByUserId($userId);
            
            foreach ($accounts as $account) {
                if ($account->getAuthMethod() !== 'xoauth2') {
                    $account->setAuthMethod('xoauth2');
                    $this->mailAccountMapper->update($account);
                    $this->logger->info('[MailOidcBridge] Updated account to xoauth2: ' . $account->getEmail());
                }
            }
        } catch (\Exception $e) {
            $this->logger->debug('[MailOidcBridge] Error updating accounts: ' . $e->getMessage());
        }
    }
}

