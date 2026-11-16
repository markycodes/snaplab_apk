<?php

use PHPMailer\PHPMailer\Exception as MailException;
use PHPMailer\PHPMailer\PHPMailer;

const FLEET_EMAIL_CONFIGURATION_ERROR = 1001;
const FLEET_EMAIL_DEPENDENCY_ERROR = 1002;
const FLEET_EMAIL_DELIVERY_ERROR = 1003;

function fleet_send_email(
    array $config,
    string $recipient,
    string $subject,
    string $plainBody,
    string $htmlBody
): void {
    $host = $config['fleet_smtp_host'] ?? null;
    $username = $config['fleet_smtp_username'] ?? null;
    $password = $config['fleet_smtp_password'] ?? null;
    $fromEmail = $config['fleet_smtp_from_email'] ?? null;
    $fromName = $config['fleet_smtp_from_name'] ?? 'SnapLab Fleet';
    $encryption = $config['fleet_smtp_encryption'] ?? 'tls';
    $rawPort = $config['fleet_smtp_port'] ?? 587;
    $port = is_int($rawPort) || (is_string($rawPort) && ctype_digit($rawPort))
        ? (int)$rawPort
        : 0;

    if (!is_string($host) || $host === '' || strlen($host) > 253 ||
        preg_match('/[\r\n]/', $host) ||
        !is_string($username) || $username === '' ||
        !is_string($password) || $password === '' ||
        !is_string($fromEmail) || !filter_var($fromEmail, FILTER_VALIDATE_EMAIL) ||
        !is_string($fromName) || preg_match('/[\r\n]/', $fromName) ||
        !in_array($encryption, ['tls', 'ssl'], true) ||
        $port < 1 || $port > 65535 ||
        !filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException(
            'Fleet SMTP is not configured correctly.',
            FLEET_EMAIL_CONFIGURATION_ERROR
        );
    }

    $autoloadPath = __DIR__ . '/vendor/autoload.php';
    if (!is_file($autoloadPath) || !is_readable($autoloadPath)) {
        throw new RuntimeException(
            'Fleet email dependency is not installed.',
            FLEET_EMAIL_DEPENDENCY_ERROR
        );
    }
    require_once $autoloadPath;

    try {
        $mailer = new PHPMailer(true);
        $mailer->isSMTP();
        $mailer->Host = $host;
        $mailer->SMTPAuth = true;
        $mailer->Username = $username;
        $mailer->Password = $password;
        $mailer->SMTPSecure = $encryption === 'ssl'
            ? PHPMailer::ENCRYPTION_SMTPS
            : PHPMailer::ENCRYPTION_STARTTLS;
        $mailer->Port = $port;
        $mailer->Timeout = 15;
        $mailer->SMTPKeepAlive = false;
        $mailer->CharSet = PHPMailer::CHARSET_UTF8;
        $mailer->setFrom($fromEmail, $fromName);
        $mailer->addAddress($recipient);
        $mailer->Subject = $subject;
        $mailer->isHTML();
        $mailer->Body = $htmlBody;
        $mailer->AltBody = $plainBody;
        $mailer->send();
    } catch (MailException $error) {
        error_log('Fleet email delivery failed: ' . $error->getMessage());
        throw new RuntimeException(
            'Fleet email delivery failed.',
            FLEET_EMAIL_DELIVERY_ERROR,
            $error
        );
    }
}

/**
 * Send a password reset notification email to the owner.
 *
 * @param array $config SMTP configuration
 * @param string $ownerEmail Owner's email address
 * @param string $resetUrl URL for password reset
 * @param string $ownerName Owner's name, or an empty string
 * @return void
 */
function fleet_send_password_reset_notification(
    array $config,
    string $ownerEmail,
    string $resetUrl,
    string $ownerName = ''
): void {
    $fromName = $config['fleet_smtp_from_name'] ?? 'SnapLab Fleet';
    $plainBody = "A password reset was requested for your SnapLab Fleet account.\n\n";
    $plainBody .= "Open this link within one hour to choose a new password:\n" . $resetUrl . "\n\n";
    $plainBody .= "If you did not request this, you can ignore this email.";

    $htmlBody = '<p>A password reset was requested for your SnapLab Fleet account.</p>' . "\n";
    $htmlBody .= '<p><a href="' . htmlspecialchars($resetUrl, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') . '">Set a new password</a></p>' . "\n";
    $htmlBody .= '<p>This link expires in one hour. If you did not request this, ignore this email.</p>';

    if (!empty($ownerName)) {
        $htmlBody = '<p>Hello ' . htmlspecialchars($ownerName, ENT_QUOTES, 'UTF-8') . ',</p>' . $htmlBody;
        $plainBody = "Hello " . $ownerName . ",\n\n" . $plainBody;
    }

    fleet_send_email($config, $ownerEmail, 'SnapLab Fleet: Password Reset Request', $plainBody, $htmlBody);
}

function fleet_send_welcome_email(array $config, string $ownerEmail): void
{
    $plainBody = "Welcome to SnapLab Fleet!\n\n";
    $plainBody .= "Your booth-owner account has been created successfully. ";
    $plainBody .= "You can now sign in to register and manage your booths.\n\n";
    $plainBody .= "If you did not create this account, please contact the site administrator.";

    $htmlBody = '<h2>Welcome to SnapLab Fleet!</h2>' . "\n";
    $htmlBody .= '<p>Your booth-owner account has been created successfully. ';
    $htmlBody .= 'You can now sign in to register and manage your booths.</p>' . "\n";
    $htmlBody .= '<p>If you did not create this account, please contact the site administrator.</p>';

    fleet_send_email(
        $config,
        $ownerEmail,
        'Welcome to SnapLab Fleet',
        $plainBody,
        $htmlBody
    );
}

/**
 * Send a weekly sales report email to the owner.
 *
 * @param array $config SMTP configuration
 * @param string $ownerEmail Owner's email address
 * @param string $ownerName Owner's name (optional)
 * @param int $periodStart Unix timestamp for the start of the reporting period
 * @param int $periodEnd Unix timestamp for the end of the reporting period
 * @param array $salesData Aggregated sales data by payment method
 * @param array $deviceNames Human-readable device names
 * @return void
 */
function fleet_send_weekly_sales_report(
    array $config,
    string $ownerEmail,
    string $ownerName,
    int $periodStart,
    int $periodEnd,
    array $salesData,
    array $deviceNames = []
): void {
    $weekStart = date('M d, Y', $periodStart);
    $weekEnd = date('M d, Y', $periodEnd);

    // Build sales breakdown HTML
    $breakdownHtml = '<h3>Sales by Payment Method</h3><ul>';
    $breakdownPlain = "Sales by Payment Method\n";

    foreach ($salesData as $method => $amount) {
        $methodName = ucfirst(str_replace('_', ' ', $method));
        $breakdownHtml .= '<li>' . htmlspecialchars($methodName, ENT_QUOTES, 'UTF-8') . ': $' . number_format($amount, 2) . '</li>' . "\n";
        $breakdownPlain .= $methodName . ': $' . number_format($amount, 2) . "\n";
    }

    $breakdownHtml .= '</ul>';
    $breakdownPlain .= "\n";

    // Build device sales summary
    $deviceHtml = '<h3>Device Sales Summary</h3><table border="1" cellpadding="5" cellspacing="0">';
    $deviceHtml .= '<tr><th>Device</th><th>Sales</th></tr>';
    $devicePlain = "Device Sales Summary\n";

    foreach ($deviceNames as $deviceId => $deviceName) {
        $deviceSales = $salesData[$deviceId] ?? 0;
        $deviceHtml .= '<tr><td>' . htmlspecialchars($deviceName, ENT_QUOTES, 'UTF-8') . '</td><td>$' . number_format($deviceSales, 2) . '</td></tr>' . "\n";
        $devicePlain .= $deviceName . ': $' . number_format($deviceSales, 2) . "\n";
    }

    $deviceHtml .= '</table>';
    $devicePlain .= "\n";

    $plainBody = "Weekly Sales Report\n";
    $plainBody .= "Period: $weekStart - $weekEnd\n\n";
    $plainBody .= $breakdownPlain;
    $plainBody .= $devicePlain;
    $plainBody .= "\n---\n";
    $plainBody .= "SnapLab Fleet Weekly Report\n";

    $htmlBody = '<h2>Weekly Sales Report</h2>' . "\n";
    $htmlBody .= '<p><strong>Period:</strong> ' . $weekStart . ' - ' . $weekEnd . '</p>' . "\n";
    $htmlBody .= $breakdownHtml . "\n";
    $htmlBody .= $deviceHtml . "\n";
    $htmlBody .= '<hr>' . "\n";
    $htmlBody .= '<p>SnapLab Fleet Weekly Report</p>';

    if (!empty($ownerName)) {
        $htmlBody = '<p>Hello ' . htmlspecialchars($ownerName, ENT_QUOTES, 'UTF-8') . ',</p>' . $htmlBody;
        $plainBody = "Hello " . $ownerName . ",\n\n" . $plainBody;
    }

    fleet_send_email($config, $ownerEmail, 'SnapLab Fleet: Weekly Sales Report (' . $weekStart . ' - ' . $weekEnd . ')', $plainBody, $htmlBody);
}

/**
 * Send a system problem notification email to the owner.
 *
 * @param array $config SMTP configuration
 * @param string $ownerEmail Owner's email address
 * @param string $ownerName Owner's name, or an empty string
 * @param string $problem Description of the problem
 * @param string $affectedDevice Device identifier affected (optional)
 * @param string $severity Severity level (info, warning, critical)
 * @return void
 */
function fleet_send_problem_notification(
    array $config,
    string $ownerEmail,
    string $ownerName,
    string $problem,
    string $affectedDevice = '',
    string $severity = 'warning'
): void {
    $severityLabels = [
        'info' => 'Information',
        'warning' => 'Warning',
        'critical' => 'Critical',
    ];
    $severityLabel = $severityLabels[$severity] ?? $severity;

    $timestamp = time();
    $date = date('M d, Y H:i', $timestamp);

    $plainBody = "SnapLab Fleet System Notification\n";
    $plainBody .= "Date: $date\n";
    $plainBody .= "Severity: $severityLabel\n\n";
    if (!empty($affectedDevice)) {
        $plainBody .= "Affected Device: $affectedDevice\n\n";
    }
    $plainBody .= "Problem: $problem\n\n";
    $plainBody .= "This is an automated notification from your SnapLab Fleet system.\n";

    $htmlBody = '<h2>SnapLab Fleet System Notification</h2>' . "\n";
    $htmlBody .= '<p><strong>Date:</strong> ' . date('M d, Y H:i', $timestamp) . '</p>' . "\n";
    $htmlBody .= '<p><strong>Severity:</strong> ' . htmlspecialchars($severityLabel, ENT_QUOTES, 'UTF-8') . '</p>' . "\n";
    if (!empty($affectedDevice)) {
        $htmlBody .= '<p><strong>Affected Device:</strong> ' . htmlspecialchars($affectedDevice, ENT_QUOTES, 'UTF-8') . '</p>' . "\n";
    }
    $htmlBody .= '<p><strong>Problem:</strong> ' . htmlspecialchars($problem, ENT_QUOTES, 'UTF-8') . '</p>' . "\n";
    $htmlBody .= '<hr>' . "\n";
    $htmlBody .= '<p>This is an automated notification from your SnapLab Fleet system.</p>';

    if (!empty($ownerName)) {
        $htmlBody = '<p>Hello ' . htmlspecialchars($ownerName, ENT_QUOTES, 'UTF-8') . ',</p>' . $htmlBody;
        $plainBody = "Hello " . $ownerName . ",\n\n" . $plainBody;
    }

    $subject = 'SnapLab Fleet: ' . htmlspecialchars($severityLabel, ENT_QUOTES, 'UTF-8') . ' Notification';
    fleet_send_email($config, $ownerEmail, $subject, $plainBody, $htmlBody);
}
