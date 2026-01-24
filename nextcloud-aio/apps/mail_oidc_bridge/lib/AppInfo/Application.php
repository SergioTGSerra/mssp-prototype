<?php

declare(strict_types=1);

namespace OCA\MailOidcBridge\AppInfo;

use OCA\Mail\Events\BeforeImapClientCreated;
use OCA\MailOidcBridge\Listener\OidcMailTokenListener;
use OCA\MailOidcBridge\Listener\UserLoggedInListener;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\User\Events\UserLoggedInEvent;

class Application extends App implements IBootstrap {
    public const APP_ID = 'mail_oidc_bridge';

    public function __construct(array $urlParams = []) {
        parent::__construct(self::APP_ID, $urlParams);
    }

    public function register(IRegistrationContext $context): void {
        // Inject OIDC tokens into mail accounts during IMAP connection
        $context->registerEventListener(BeforeImapClientCreated::class, OidcMailTokenListener::class);
        
        // Auto-provision mail accounts when OIDC users log in
        $context->registerEventListener(UserLoggedInEvent::class, UserLoggedInListener::class);
    }

    public function boot(IBootContext $context): void {
        // Nothing to boot
    }
}
