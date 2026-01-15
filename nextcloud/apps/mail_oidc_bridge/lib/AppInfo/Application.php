<?php

declare(strict_types=1);

namespace OCA\MailOidcBridge\AppInfo;

use OCA\Mail\Events\BeforeImapClientCreated;
use OCA\MailOidcBridge\Listener\OidcMailTokenListener;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;

class Application extends App implements IBootstrap {
    public const APP_ID = 'mail_oidc_bridge';

    public function __construct(array $urlParams = []) {
        parent::__construct(self::APP_ID, $urlParams);
    }

    public function register(IRegistrationContext $context): void {
        $context->registerEventListener(BeforeImapClientCreated::class, OidcMailTokenListener::class);
    }

    public function boot(IBootContext $context): void {
        // Nothing to boot
    }
}
