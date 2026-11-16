<?php
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
$cspNonce = base64_encode(random_bytes(18));
$https = strtolower((string) ($_SERVER['HTTPS'] ?? ''));
if ($https !== 'on' && $https !== '1') {
  header('Location: https://snaplabbooth.com/', true, 302);
  exit;
}
$fleetPage = $_GET['view'] ?? 'home';
if (!in_array($fleetPage, ['home', 'login', 'register'], true)) {
  $fleetPage = 'home';
}
if (isset($_GET['reset'])) {
  $fleetPage = 'login';
}
$fleetConfig = require __DIR__ . '/photobooth_private/photobooth_config.php';
$turnstileSiteKey = $fleetConfig['fleet_turnstile_site_key'] ?? '';
if (!is_string($turnstileSiteKey)) {
  $turnstileSiteKey = '';
}
header('Strict-Transport-Security: max-age=31536000');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-$cspNonce' https://challenges.cloudflare.com https://unpkg.com; style-src 'self' 'nonce-$cspNonce' https://unpkg.com; img-src 'self' data: https://server.arcgisonline.com; connect-src 'self' https://challenges.cloudflare.com https://server.arcgisonline.com; frame-src https://challenges.cloudflare.com; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
?>
<!doctype html>
<html lang="en">

<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="dark">
  <title>SnapLab Fleet | Photobooth Monitoring</title>
  <meta name="description"
    content="Monitor SnapLab photobooth connections, reported sales, and device status from one fleet dashboard.">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
    integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
  <style nonce="<?= htmlspecialchars($cspNonce, ENT_QUOTES, 'UTF-8') ?>">
    :root {
      color-scheme: light;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
      color: #17212b;
      background: #f8fafc;
      font-synthesis: none;
      --panel: #f1f3f6;
      --panel-raised: #ffffff;
      --border: #e2e8f0;
      --muted: #64748b;
      --accent: #47667d;
      --accent-deep: #eaf0f5;
      --ink: #17212b;
      --canvas: #f8fafc
    }

    * {
      box-sizing: border-box
    }

    body {
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      background: radial-gradient(ellipse at 50% -25%, #eaf0f5 0, transparent 54%), var(--canvas)
    }

    button,
    input {
      font: inherit
    }

    .shell {
      max-width: 1240px;
      margin: auto;
      padding: 42px 28px
    }

    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 28px;
      padding-bottom: 22px;
      border-bottom: 1px solid var(--border)
    }

    h1 {
      font-size: clamp(26px, 4vw, 36px);
      margin: 0;
      letter-spacing: -.045em;
      color: #f5f8fb
    }

    .subtitle {
      color: var(--muted);
      margin: 8px 0 0
    }

    .card {
      background: linear-gradient(145deg, #141d27, #101720);
      border: 1px solid var(--border);
      border-radius: 17px;
      box-shadow: 0 16px 40px #0005
    }

    .login {
      max-width: 440px;
      margin: 8vh auto;
      padding: 34px
    }

    .login h1 {
      margin-bottom: 8px
    }

    .login p {
      color: var(--muted);
      line-height: 1.55
    }

    .login form h2 {
      margin: 4px 0 8px;
      font-size: 20px
    }

    .login .secondary-link {
      padding: 8px 0;
      color: var(--muted);
      background: transparent;
      border: 0;
      box-shadow: none
    }

    .login p.error {
      color: #ff8e91
    }

    label {
      display: block;
      color: #d2dbe6;
      font-size: 13px;
      font-weight: 650;
      margin: 18px 0 8px
    }

    input,
    select {
      color: #edf3f8;
      background: #0d141c;
      width: 100%;
      padding: 12px 14px;
      border: 1px solid #344252;
      border-radius: 10px;
      outline: none;
      transition: border-color .16s, box-shadow .16s
    }

    input::placeholder {
      color: #738296
    }

    input:focus,
    select:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px #65d7b025
    }

    button {
      border: 1px solid transparent;
      border-radius: 10px;
      padding: 11px 16px;
      font-weight: 700;
      cursor: pointer;
      background: var(--accent);
      color: #0b1714;
      transition: transform .15s, filter .15s, border-color .15s
    }

    button:hover {
      filter: brightness(1.08);
      transform: translateY(-1px)
    }

    button:focus-visible {
      outline: 3px solid #65d7b080;
      outline-offset: 2px
    }

    button.secondary {
      background: #1b2632;
      color: #dbe4ed;
      border-color: #344252
    }

    .error {
      color: #ff8e91;
      min-height: 22px;
      margin-top: 10px
    }

    .hidden {
      display: none !important
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;
      margin-bottom: 20px
    }

    .metric {
      padding: 21px 22px;
      position: relative;
      overflow: hidden
    }

    .metric:after {
      content: "";
      position: absolute;
      right: -25px;
      top: -35px;
      width: 100px;
      height: 100px;
      border-radius: 50%;
      background: #65d7b00c
    }

    .metric small {
      display: block;
      color: var(--muted);
      font-weight: 650;
      letter-spacing: .01em
    }

    .metric strong {
      display: block;
      margin-top: 12px;
      font-size: 28px;
      letter-spacing: -.03em;
      color: #f4f7fa
    }

    .section {
      padding: 22px;
      margin-top: 18px
    }

    .section h2 {
      font-size: 18px;
      margin: 0;
      color: #f1f5f9
    }

    .section-heading {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 16px
    }

    .register-form {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      margin: 12px 0 14px
    }

    .register-form input {
      flex: 1;
      min-width: 0
    }

    .register-message {
      min-height: 22px;
      margin: 0 0 12px;
      color: #ff8e91
    }

    .register-message.success {
      color: var(--accent)
    }

    .filters {
      display: flex;
      gap: 10px;
      margin-bottom: 14px
    }

    .filters input,
    .filters select {
      width: auto;
      min-width: 180px;
      padding: 10px 12px
    }

    .filters input {
      flex: 1
    }

    .status-text {
      font-weight: 650
    }

    .status-good {
      color: #65d7b0
    }

    .status-warn {
      color: #f2b766
    }

    .status-bad {
      color: #ff878b
    }

    .device-row {
      cursor: pointer;
      transition: background .15s
    }

    .device-row:hover,
    .device-row:focus {
      background: #1a2631;
      outline: 2px solid #65d7b080;
      outline-offset: -2px
    }

    .count {
      font-size: 13px;
      color: var(--muted)
    }

    .table-wrap {
      overflow: auto
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 720px
    }

    th,
    td {
      text-align: left;
      padding: 14px 12px;
      border-top: 1px solid #24303d;
      white-space: nowrap
    }

    th {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: .08em;
      color: #92a1b3;
      background: #101720
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      font-weight: 700
    }

    .dot {
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: #8492a3
    }

    .online .dot {
      background: #65d7b0;
      box-shadow: 0 0 9px #65d78080
    }

    .offline .dot {
      background: #ff777d
    }

    .muted {
      color: var(--muted);
      font-size: 13px
    }

    .detail-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 10px
    }

    .detail {
      background: #0d141c;
      border: 1px solid #25313e;
      border-radius: 11px;
      padding: 14px
    }

    .detail small {
      display: block;
      color: var(--muted)
    }

    .detail strong {
      display: block;
      margin-top: 7px;
      color: #e8edf4
    }

    .fleet-map {
      width: 100%;
      height: 420px;
      margin-top: 14px;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: #0d141c
    }

    #mapStyle {
      width: auto;
      min-width: 150px;
      padding: 9px 12px
    }

    .map-legend {
      display: flex;
      flex-wrap: wrap;
      gap: 14px;
      margin-top: 12px;
      color: var(--muted);
      font-size: 13px
    }

    .map-legend span {
      display: inline-flex;
      align-items: center;
      gap: 6px
    }

    .map-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: #36c98f
    }

    .map-dot.offline {
      background: #9aa6b2
    }

    .remote-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
      gap: 12px;
      align-items: end
    }

    .onboarding-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 0 14px;
      align-items: end
    }

    .photo-count-options {
      display: flex;
      flex-wrap: wrap;
      gap: 12px
    }

    .photo-count-options label {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      margin: 8px 0
    }

    .photo-count-options input {
      width: auto
    }

    .empty {
      text-align: center;
      color: var(--muted);
      padding: 35px 12px
    }

    .toolbar {
      display: flex;
      gap: 10px;
      align-items: center
    }

    .landing {
      overflow: hidden
    }

    .landing-nav {
      width: min(1180px, calc(100% - 48px));
      min-height: 82px;
      margin: 0 auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 24px;
      border-bottom: 1px solid #ffffff16
    }

    .brand {
      display: inline-flex;
      align-items: center;
      gap: 11px;
      color: #f5f8fb;
      text-decoration: none;
      font-weight: 800;
      letter-spacing: -.035em
    }

    .brand-mark {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      border-radius: 12px;
      color: #071611;
      background: var(--accent);
      box-shadow: 0 0 28px #65d7b033;
      font-size: 15px
    }

    .landing-links {
      display: flex;
      align-items: center;
      gap: 28px
    }

    .landing-links a,
    .landing-footer a {
      color: #b6c1ce;
      text-decoration: none;
      font-size: 14px;
      font-weight: 650;
      transition: color .15s
    }

    .landing-links a:hover,
    .landing-footer a:hover {
      color: var(--accent)
    }

    .landing-nav .nav-cta {
      padding: 10px 15px;
      border: 1px solid #65d7b05c;
      border-radius: 10px;
      color: #b7ffe9;
      background: #65d7b012;
      font-size: 13px;
      font-weight: 750;
      text-decoration: none
    }

    .landing-button {
      display: inline-flex;
      justify-content: center;
      align-items: center;
      padding: 13px 18px;
      border: 1px solid transparent;
      border-radius: 10px;
      background: var(--accent);
      color: #0b1714;
      font-size: 14px;
      font-weight: 750;
      text-decoration: none;
      transition: transform .15s, filter .15s, border-color .15s
    }

    .landing-button:hover {
      filter: brightness(1.08);
      transform: translateY(-1px)
    }

    .landing-button.secondary {
      border-color: #344252;
      background: #1b2632;
      color: #dbe4ed
    }

    .landing-hero {
      width: min(1180px, calc(100% - 48px));
      min-height: 590px;
      margin: 0 auto;
      scroll-margin-top: 102px;
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(340px, .92fr);
      align-items: center;
      gap: 64px;
      padding: 74px 0 88px
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 9px;
      color: var(--accent);
      font-size: 12px;
      font-weight: 800;
      letter-spacing: .13em;
      text-transform: uppercase
    }

    .eyebrow:before {
      content: "";
      width: 22px;
      height: 1px;
      background: currentColor
    }

    .hero-copy h1 {
      max-width: 650px;
      margin: 20px 0 18px;
      color: #f5f8fb;
      font-size: clamp(42px, 6.2vw, 72px);
      line-height: 1.02;
      letter-spacing: -.065em
    }

    .hero-copy h1 span {
      color: var(--accent)
    }

    .hero-copy > p {
      max-width: 550px;
      margin: 0;
      color: #a7b3c0;
      font-size: 17px;
      line-height: 1.75
    }

    .hero-actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 12px;
      margin-top: 30px
    }

    .hero-actions button {
      padding: 13px 18px
    }

    .hero-note {
      margin-top: 17px !important;
      color: #8190a0 !important;
      font-size: 12px !important
    }

    .hero-visual {
      position: relative;
      min-height: 385px;
      display: grid;
      place-items: center
    }

    .hero-glow {
      position: absolute;
      width: 80%;
      aspect-ratio: 1;
      border-radius: 50%;
      background: #65d7b018;
      filter: blur(35px)
    }

    .preview-window {
      position: relative;
      width: min(100%, 470px);
      padding: 18px;
      border: 1px solid #344252;
      border-radius: 20px;
      background: linear-gradient(145deg, #16212b, #0d141c);
      box-shadow: 0 30px 90px #0008;
      transform: rotate(1.5deg)
    }

    .preview-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 2px 2px 16px;
      color: #dce5ed;
      font-size: 13px;
      font-weight: 750
    }

    .live-badge {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      color: var(--accent);
      font-size: 11px;
      font-weight: 750
    }

    .live-badge:before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 10px #65d7b0aa
    }

    .preview-map {
      position: relative;
      height: 206px;
      overflow: hidden;
      border: 1px solid #30404d;
      border-radius: 13px;
      background-color: #111f25;
      background-image: linear-gradient(#ffffff08 1px, transparent 1px), linear-gradient(90deg, #ffffff08 1px, transparent 1px);
      background-size: 34px 34px
    }

    .map-road {
      position: absolute;
      height: 12px;
      border: 1px solid #91a0b220;
      border-right: 0;
      border-left: 0;
      background: #33434a;
      transform: rotate(-24deg)
    }

    .map-road.road-one {
      top: 57px;
      left: -8%;
      width: 120%
    }

    .map-road.road-two {
      top: 138px;
      left: -8%;
      width: 115%;
      transform: rotate(18deg)
    }

    .map-road.road-three {
      top: 44%;
      left: 52%;
      width: 78%;
      transform: rotate(72deg)
    }

    .map-pin {
      position: absolute;
      z-index: 1;
      display: grid;
      place-items: center;
      width: 28px;
      height: 28px;
      border: 4px solid #143d34;
      border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 0 7px #65d7b020, 0 5px 15px #0008
    }

    .map-pin:after {
      content: "";
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: #10211c
    }

    .map-pin.pin-one {
      top: 39%;
      left: 31%
    }

    .map-pin.pin-two {
      top: 63%;
      left: 68%
    }

    .map-pin.pin-three {
      top: 19%;
      left: 74%;
      border-color: #42404a;
      background: #9aa6b2;
      box-shadow: 0 0 0 7px #9aa6b220, 0 5px 15px #0008
    }

    .preview-stats {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 9px;
      margin-top: 12px
    }

    .preview-stat {
      padding: 12px;
      border: 1px solid #273442;
      border-radius: 11px;
      background: #101821
    }

    .preview-stat small {
      display: block;
      color: #8493a3;
      font-size: 10px
    }

    .preview-stat strong {
      display: block;
      margin-top: 6px;
      color: #f0f5f8;
      font-size: 17px
    }

    .preview-stat strong.green {
      color: var(--accent)
    }

    .floating-status {
      position: absolute;
      right: -24px;
      bottom: 28px;
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 13px 16px;
      border: 1px solid #354450;
      border-radius: 13px;
      background: #111a22;
      box-shadow: 0 15px 40px #0008;
      color: #dce5ed;
      font-size: 12px;
      font-weight: 700
    }

    .floating-status .status-icon {
      display: grid;
      place-items: center;
      width: 30px;
      height: 30px;
      border-radius: 9px;
      color: var(--accent);
      background: #65d7b01c
    }

    .landing-section {
      padding: 92px 24px;
      border-top: 1px solid #ffffff12
    }

    .landing-section-inner {
      width: min(1040px, 100%);
      margin: 0 auto
    }

    .section-intro {
      max-width: 660px;
      margin-bottom: 34px
    }

    .section-intro h2 {
      margin: 14px 0 12px;
      color: #f3f6f9;
      font-size: clamp(30px, 4vw, 44px);
      letter-spacing: -.05em
    }

    .section-intro p {
      margin: 0;
      color: #a5b1bf;
      line-height: 1.75
    }

    .feature-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px
    }

    .feature-card {
      padding: 22px;
      border: 1px solid var(--border);
      border-radius: 16px;
      background: linear-gradient(145deg, #141d27, #101720)
    }

    .feature-icon {
      display: grid;
      place-items: center;
      width: 40px;
      height: 40px;
      margin-bottom: 17px;
      border: 1px solid #65d7b02a;
      border-radius: 12px;
      color: var(--accent);
      background: #65d7b012;
      font-size: 19px
    }

    .feature-card h3 {
      margin: 0 0 9px;
      color: #edf2f6;
      font-size: 16px
    }

    .feature-card p {
      margin: 0;
      color: #9aa8b6;
      font-size: 13px;
      line-height: 1.7
    }

    .about-panel {
      display: grid;
      grid-template-columns: .85fr 1.15fr;
      gap: 44px;
      padding: 34px;
      border: 1px solid var(--border);
      border-radius: 20px;
      background: linear-gradient(135deg, #14221f, #111821 64%)
    }

    .about-panel h2 {
      margin: 13px 0 0;
      color: #f3f6f9;
      font-size: clamp(29px, 4vw, 42px);
      line-height: 1.1;
      letter-spacing: -.05em
    }

    .about-copy {
      color: #a8b4c0;
      line-height: 1.8
    }

    .about-copy p {
      margin: 0 0 14px
    }

    .about-copy p:last-child {
      margin-bottom: 0
    }

    .faq-list {
      display: grid;
      gap: 10px;
      max-width: 820px
    }

    .faq-list details {
      padding: 18px 20px;
      border: 1px solid var(--border);
      border-radius: 13px;
      background: #111821
    }

    .faq-list summary {
      position: relative;
      padding-right: 28px;
      color: #edf2f6;
      font-weight: 700;
      cursor: pointer;
      list-style: none
    }

    .faq-list summary::-webkit-details-marker {
      display: none
    }

    .faq-list summary:after {
      content: "+";
      position: absolute;
      right: 0;
      top: -3px;
      color: var(--accent);
      font-size: 22px;
      font-weight: 500
    }

    .faq-list details[open] summary:after {
      content: "−"
    }

    .faq-list details p {
      max-width: 720px;
      margin: 12px 0 0;
      color: #a5b1bf;
      font-size: 14px;
      line-height: 1.7
    }

    .landing-cta {
      padding: 66px 24px;
      border-top: 1px solid #ffffff12;
      background: radial-gradient(ellipse at 50% 100%, #1a302d 0, transparent 66%)
    }

    .landing-cta-inner {
      max-width: 760px;
      margin: 0 auto;
      text-align: center
    }

    .landing-cta h2 {
      margin: 0 0 12px;
      color: #f3f6f9;
      font-size: clamp(30px, 4vw, 44px);
      letter-spacing: -.05em
    }

    .landing-cta p {
      margin: 0;
      color: #a5b1bf;
      line-height: 1.7
    }

    .landing-cta .hero-actions {
      justify-content: center;
      margin-top: 22px
    }

    .landing-footer {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 18px;
      padding: 24px max(24px, calc((100% - 1180px) / 2));
      border-top: 1px solid #ffffff12;
      color: #8290a0;
      font-size: 12px
    }

    .landing-footer nav {
      display: flex;
      flex-wrap: wrap;
      gap: 20px
    }

    .landing a:focus-visible,
    .landing summary:focus-visible {
      outline: 3px solid #65d7b080;
      outline-offset: 4px;
      border-radius: 4px
    }

    @media(max-width:780px) {
      .summary {
        grid-template-columns: repeat(2, minmax(0, 1fr))
      }

      .landing-hero {
        grid-template-columns: 1fr minmax(260px, .85fr);
        gap: 28px
      }

      .floating-status {
        right: -8px
      }

      .feature-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr))
      }
    }

    @media(max-width:640px) {
      .shell {
        padding: 24px 14px
      }

      .login {
        margin: 5vh 14px;
        padding: 24px
      }

      .summary {
        grid-template-columns: 1fr
      }

      .metric {
        padding: 16px 18px
      }

      .metric strong {
        font-size: 24px
      }

      header {
        align-items: flex-start
      }

      .toolbar {
        flex-direction: column;
        align-items: flex-end
      }

      .filters,
      .register-form {
        flex-direction: column
      }

      .filters input,
      .filters select,
      .register-form input,
      .register-form button {
        width: 100%
      }

      .section {
        padding: 16px
      }

      .fleet-map {
        height: 320px
      }

      .landing-nav {
        width: 100%;
        min-height: 68px;
        gap: 10px;
        padding-right: 16px;
        padding-left: 16px
      }

      .landing {
        padding-top: 68px
      }

      .landing-links {
        gap: 14px
      }

      .landing-links a {
        font-size: 12px
      }

      .landing-nav .nav-cta {
        padding: 8px 10px;
        font-size: 12px
      }

      .brand-mark {
        width: 34px;
        height: 34px
      }

      .landing-hero {
        width: calc(100% - 36px);
        min-height: 0;
        grid-template-columns: 1fr;
        gap: 28px;
        padding: 66px 0 56px
      }

      .hero-copy h1 {
        font-size: clamp(42px, 12vw, 60px)
      }

      .hero-copy > p {
        font-size: 15px
      }

      .hero-visual {
        min-height: 315px;
        padding: 0 10px
      }

      .preview-window {
        padding: 13px
      }

      .preview-map {
        height: 175px
      }

      .floating-status {
        right: 0;
        bottom: 4px
      }

      .landing-section {
        padding: 64px 18px
      }

      .feature-grid {
        grid-template-columns: 1fr
      }

      .about-panel {
        grid-template-columns: 1fr;
        gap: 20px;
        padding: 24px
      }

      .landing-footer {
        flex-direction: column;
        align-items: flex-start;
        padding: 22px 18px
      }
    }

    @media(max-width:380px) {
      .landing-nav {
        min-height: 68px;
        gap: 7px
      }

      .brand {
        gap: 6px;
        font-size: 13px
      }

      .landing-links {
        gap: 8px
      }

      .landing-links a {
        font-size: 11px
      }

      .landing-nav .nav-cta {
        padding: 8px;
        font-size: 11px
      }
    }

    .turnstile {
      margin-top: 12px;
      margin-bottom: 8px
      width: 100%;
    }

    body {
      scroll-behavior: smooth
    }

    .card {
      background: linear-gradient(145deg, #ffffff, #f8fafc);
      border-color: var(--border);
      box-shadow: 0 12px 32px #17212b12
    }

    .shell header {
      border-color: var(--border)
    }

    .shell h1,
    .section h2,
    .metric strong,
    .detail strong {
      color: var(--ink)
    }

    .login {
      color: var(--ink)
    }

    .login h1,
    .login form h2 {
      color: var(--ink)
    }

    .login p,
    .subtitle,
    .muted,
    .count,
    .map-legend {
      color: var(--muted)
    }

    label {
      color: var(--ink)
    }

    input,
    select {
      color: var(--ink);
      background: #ffffff;
      border-color: var(--border)
    }

    input::placeholder {
      color: #94a3b8
    }

    input:focus,
    select:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px #47667d20
    }

    button {
      background: var(--accent);
      color: #ffffff
    }

    button:focus-visible {
      outline-color: #47667d70
    }

    button.secondary {
      background: #ffffff;
      color: var(--ink);
      border-color: var(--border)
    }

    .metric:after {
      background: #47667d0c
    }

    .section h2 {
      color: var(--ink)
    }

    .register-message.success,
    .status-good {
      color: #287d3c
    }

    .device-row:hover,
    .device-row:focus {
      background: #eaf0f5;
      outline-color: #47667d70
    }

    th,
    td {
      border-color: var(--border)
    }

    th {
      color: #64748b;
      background: #f1f3f6
    }

    .detail {
      background: #f8fafc;
      border-color: var(--border)
    }

    .detail strong {
      color: var(--ink)
    }

    .fleet-map {
      background: #f1f3f6;
      border-color: var(--border)
    }

    .landing {
      --landing-ink: #17212b;
      --landing-muted: #64748b;
      --landing-accent: #47667d;
      --landing-panel: #ffffff;
      --landing-soft: #f1f3f6;
      --landing-border: #e2e8f0;
      color: var(--landing-ink);
      padding-top: 82px;
      background: radial-gradient(ellipse at 72% 15%, #eaf0f5 0, transparent 35%), #f8fafc
    }

    .landing-nav {
      position: fixed;
      z-index: 1100;
      inset: 0 0 auto;
      width: 100%;
      min-height: 82px;
      padding: 0 max(24px, calc((100% - 1180px) / 2));
      border-color: #17212b12;
      background: #f8fafceF;
      box-shadow: 0 6px 24px #17212b0a;
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px)
    }

    .brand {
      color: var(--landing-ink)
    }

    .brand-mark {
      color: #ffffff;
      background: var(--landing-accent);
      box-shadow: 0 7px 18px #47667d35
    }

    .landing-links a,
    .landing-footer a {
      color: var(--landing-muted)
    }

    .landing-links a:hover,
    .landing-footer a:hover {
      color: var(--landing-accent)
    }

    .landing-nav .nav-cta {
      border-color: #47667d40;
      color: var(--landing-accent);
      background: #47667d0d
    }

    .landing-button {
      background: var(--landing-accent);
      color: #ffffff;
      box-shadow: 0 7px 16px #47667d25
    }

    .landing-button.secondary {
      border-color: #cbd5e1;
      background: #ffffff;
      color: var(--landing-ink);
      box-shadow: 0 3px 10px #17212b0a
    }

    .landing-button:hover {
      filter: brightness(1.05);
      box-shadow: 0 12px 25px #47667d35
    }

    .eyebrow,
    .hero-copy h1 span,
    .preview-stat strong.green,
    .live-badge {
      color: var(--landing-accent)
    }

    .hero-copy h1,
    .section-intro h2,
    .about-panel h2,
    .landing-cta h2 {
      color: var(--landing-ink)
    }

    .hero-copy > p,
    .section-intro p,
    .about-copy,
    .faq-list details p,
    .landing-cta p {
      color: var(--landing-muted)
    }

    .hero-note {
      color: #7b8795 !important
    }

    .hero-glow {
      background: #47667d18
    }

    .preview-window {
      border-color: #ffffff;
      background: linear-gradient(145deg, #ffffff, #f1f3f6);
      box-shadow: 0 28px 75px #17212b1c, 0 0 0 1px #e2e8f0
    }

    .preview-top {
      color: var(--landing-ink)
    }

    .live-badge:before {
      background: var(--landing-accent);
      box-shadow: 0 0 0 4px #47667d20
    }

    .preview-map {
      border-color: #d7e0e8;
      background-color: #eaf0f5;
      background-image: linear-gradient(#47667d0c 1px, transparent 1px), linear-gradient(90deg, #47667d0c 1px, transparent 1px)
    }

    .map-road {
      border-color: #ffffff;
      background: #d5e0e8
    }

    .map-pin {
      border-color: #ffffff;
      background: var(--landing-accent);
      box-shadow: 0 0 0 7px #47667d20, 0 5px 15px #17212b20
    }

    .map-pin:after {
      background: #ffffff
    }

    .map-pin.pin-three {
      border-color: #ffffff;
      background: #94a3b8;
      box-shadow: 0 0 0 7px #94a3b820, 0 5px 15px #17212b20
    }

    .preview-stat {
      border-color: var(--landing-border);
      background: #ffffff
    }

    .preview-stat small {
      color: var(--landing-muted)
    }

    .preview-stat strong {
      color: var(--landing-ink)
    }

    .floating-status {
      border-color: #ffffff;
      background: #ffffff;
      box-shadow: 0 15px 40px #17212b20, 0 0 0 1px #e2e8f0;
      color: var(--landing-ink)
    }

    .floating-status .status-icon {
      color: #ffffff;
      background: var(--landing-accent)
    }

    .landing-section {
      border-color: #17212b12;
      scroll-margin-top: 102px
    }

    .feature-card,
    .faq-list details {
      border-color: var(--landing-border);
      background: #ffffff;
      box-shadow: 0 8px 24px #17212b08
    }

    .feature-icon {
      border-color: #47667d24;
      color: var(--landing-accent);
      background: #47667d0d
    }

    .feature-card h3,
    .faq-list summary {
      color: var(--landing-ink)
    }

    .feature-card p {
      color: var(--landing-muted)
    }

    .about-panel {
      border-color: var(--landing-border);
      background: linear-gradient(135deg, #eaf0f5, #ffffff 68%)
    }

    .faq-list summary:after {
      color: var(--landing-accent)
    }

    .landing-cta {
      border-color: #17212b12;
      background: radial-gradient(ellipse at 50% 100%, #eaf0f5 0, transparent 66%)
    }

    .landing-footer {
      border-color: #17212b12;
      color: var(--landing-muted)
    }

    .landing a:focus-visible,
    .landing summary:focus-visible {
      outline-color: #47667d80
    }

    .hero-copy {
      animation: fleet-enter-up .75s cubic-bezier(.2, .75, .25, 1) both
    }

    .hero-visual {
      animation: fleet-enter-right .9s .12s cubic-bezier(.2, .75, .25, 1) both
    }

    .hero-glow {
      animation: fleet-glow 7s ease-in-out infinite alternate
    }

    .preview-window {
      animation: fleet-float 6s ease-in-out infinite
    }

    .floating-status {
      animation: fleet-float 5s .5s ease-in-out infinite reverse
    }

    .map-pin {
      animation: fleet-pin-pulse 2.8s ease-out infinite
    }

    .map-pin.pin-two {
      animation-delay: .85s
    }

    .map-pin.pin-three {
      animation-delay: 1.7s
    }

    .landing-button,
    .landing-nav .nav-cta,
    .feature-card,
    .faq-list details {
      transition: transform .22s ease, box-shadow .22s ease, border-color .22s ease, background-color .22s ease
    }

    .feature-card:hover {
      transform: translateY(-5px);
      border-color: #47667d55;
      box-shadow: 0 16px 34px #17212b12
    }

    .faq-list details[open] {
      border-color: #47667d55;
      box-shadow: 0 10px 24px #17212b0b
    }

    .faq-list details p {
      animation: fleet-enter-up .25s ease both
    }

    .landing-nav .nav-cta:hover {
      transform: translateY(-2px);
      background: #47667d18
    }

    .landing-links a {
      position: relative;
      padding: 10px 0
    }

    .landing-links a:after {
      content: "";
      position: absolute;
      right: 0;
      bottom: 3px;
      left: 0;
      height: 2px;
      border-radius: 2px;
      background: var(--landing-accent);
      transform: scaleX(0);
      transform-origin: left center;
      transition: transform .24s ease
    }

    .landing-links a[aria-current="location"] {
      color: var(--landing-accent)
    }

    .landing-links a[aria-current="location"]:after,
    .landing-links a:hover:after {
      transform: scaleX(1)
    }

    .landing-section.nav-arrive,
    .landing-hero.nav-arrive {
      animation: fleet-section-arrive .72s cubic-bezier(.2, .75, .25, 1) both
    }

    body.is-navigating:after {
      content: "";
      position: fixed;
      z-index: 1200;
      inset: 0;
      pointer-events: none;
      background: radial-gradient(ellipse at center, #47667d24, #f8fafc00 72%);
      animation: fleet-navigation-wash .62s cubic-bezier(.2, .75, .25, 1) both
    }

    @keyframes fleet-section-arrive {
      from {
        opacity: .48;
        transform: translateY(22px) scale(.99)
      }

      to {
        opacity: 1;
        transform: translateY(0) scale(1)
      }
    }

    @keyframes fleet-navigation-wash {
      0% {
        opacity: 0;
        transform: scale(.98)
      }

      32% {
        opacity: 1;
        transform: scale(1)
      }

      100% {
        opacity: 0;
        transform: scale(1.02)
      }
    }

    .motion-ready .reveal {
      opacity: 0;
      transform: translateY(24px);
      transition: opacity .65s ease var(--reveal-delay, 0ms), transform .65s cubic-bezier(.2, .75, .25, 1) var(--reveal-delay, 0ms)
    }

    .motion-ready .reveal.is-visible {
      opacity: 1;
      transform: translateY(0)
    }

    @keyframes fleet-enter-up {
      from {
        opacity: 0;
        transform: translateY(24px)
      }

      to {
        opacity: 1;
        transform: translateY(0)
      }
    }

    @keyframes fleet-enter-right {
      from {
        opacity: 0;
        transform: translateX(28px)
      }

      to {
        opacity: 1;
        transform: translateX(0)
      }
    }

    @keyframes fleet-float {
      0%,
      100% {
        translate: 0 0
      }

      50% {
        translate: 0 -9px
      }
    }

    @keyframes fleet-glow {
      from {
        opacity: .5;
        scale: .92
      }

      to {
        opacity: .95;
        scale: 1.08
      }
    }

    @keyframes fleet-pin-pulse {
      0%,
      100% {
        box-shadow: 0 0 0 6px #47667d18, 0 5px 15px #17212b20
      }

      50% {
        box-shadow: 0 0 0 12px #47667d08, 0 5px 15px #17212b20
      }
    }

    @media(prefers-reduced-motion:reduce) {
      *,
      *:before,
      *:after {
        scroll-behavior: auto !important;
        animation-duration: .01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: .01ms !important
      }

      .motion-ready .reveal {
        opacity: 1;
        transform: none
      }
    }

  </style>
</head>

<body>
  <div id="landingView" class="landing<?= $fleetPage === 'home' ? '' : ' hidden' ?>">
    <nav class="landing-nav" aria-label="Main navigation">
      <a class="brand" href="#home" aria-label="SnapLab Fleet home">
        <span class="brand-mark" aria-hidden="true">SL</span>
        <span>SnapLab Fleet</span>
      </a>
      <div class="landing-links">
        <a href="#home" aria-current="<?= $fleetPage === 'home' ? 'location' : 'false' ?>">Home</a>
        <a href="#about">About</a>
        <a href="#faq">FAQ</a>
      </div>
      <a class="nav-cta" href="/login">Sign in</a>
    </nav>
    <main>
      <section id="home" class="landing-hero" aria-labelledby="heroTitle">
        <div class="hero-copy">
          <span class="eyebrow">Photobooth fleet monitoring</span>
          <h1 id="heroTitle">Your booths. <span>One clear view.</span></h1>
          <p>Check booth connectivity, review sales activity, and manage supported settings from one fleet dashboard—wherever your work takes you.</p>
          <div class="hero-actions">
            <a class="landing-button" href="/login">Open Fleet Dashboard</a>
            <a class="landing-button secondary" href="/register">Create owner account</a>
          </div>
          <p class="hero-note">For SnapLab booth owners and fleet administrators.</p>
        </div>
        <div class="hero-visual" aria-label="Illustration of booth status and fleet activity">
          <div class="hero-glow"></div>
          <div class="preview-window">
            <div class="preview-top"><span>Fleet overview</span><span class="live-badge">Live status</span></div>
            <div class="preview-map" aria-hidden="true">
              <span class="map-road road-one"></span><span class="map-road road-two"></span>
              <span class="map-road road-three"></span><span class="map-pin pin-one"></span>
              <span class="map-pin pin-two"></span><span class="map-pin pin-three"></span>
            </div>
            <div class="preview-stats">
              <div class="preview-stat"><small>Connection</small><strong class="green">Live</strong></div>
              <div class="preview-stat"><small>Device health</small><strong>Reported</strong></div>
              <div class="preview-stat"><small>Sales activity</small><strong>Tracked</strong></div>
            </div>
          </div>
          <div class="floating-status"><span class="status-icon" aria-hidden="true">✓</span><span>Booth status at a glance</span></div>
        </div>
      </section>
      <section class="landing-section" aria-labelledby="featuresTitle">
        <div class="landing-section-inner">
          <div class="section-intro">
            <span class="eyebrow">Built for booth operators</span>
            <h2 id="featuresTitle">Spend less time guessing.</h2>
            <p>Fleet brings the key operational signals together so you can quickly see which booths are reporting and where follow-up may be needed.</p>
          </div>
          <div class="feature-grid">
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">⌁</span>
              <h3>Connection status</h3>
              <p>See which registered booths are online, offline, or waiting for their first report.</p>
            </article>
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">₱</span>
              <h3>Sales overview</h3>
              <p>Review recorded totals and transaction activity reported by your booths.</p>
            </article>
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">⌖</span>
              <h3>Location and device details</h3>
              <p>View shared booth locations and available device health details when the booth reports them.</p>
            </article>
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">⚙</span>
              <h3>Remote management</h3>
              <p>Use supported remote settings and commands for eligible booths from the device detail view.</p>
            </article>
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">◷</span>
              <h3>Automatic refresh</h3>
              <p>The dashboard refreshes regularly while you are signed in, so new booth reports appear without a manual reload.</p>
            </article>
            <article class="feature-card">
              <span class="feature-icon" aria-hidden="true">▣</span>
              <h3>Owner-specific access</h3>
              <p>Booth-owner accounts are scoped to their registered booths, while administrators can oversee the fleet.</p>
            </article>
          </div>
        </div>
      </section>
      <section id="about" class="landing-section" aria-labelledby="aboutTitle">
        <div class="landing-section-inner">
          <div class="about-panel">
            <div>
              <span class="eyebrow">About SnapLab Fleet</span>
              <h2 id="aboutTitle">A practical control center for your booths.</h2>
            </div>
            <div class="about-copy">
              <p>SnapLab Fleet is the web dashboard for monitoring SnapLab photobooth devices. It brings connection status, booth-reported sales, device information, and available management tools into one place.</p>
              <p>Each booth needs internet access to send status updates. Location details are shown only when location sharing is enabled and a booth has reported its coordinates. Fleet marks a booth offline when its reports become stale.</p>
              <p>Sign in with your owner account to see your booths, or use an administrator account for fleet-wide management.</p>
            </div>
          </div>
        </div>
      </section>
      <section id="faq" class="landing-section" aria-labelledby="faqTitle">
        <div class="landing-section-inner">
          <div class="section-intro">
            <span class="eyebrow">Quick answers</span>
            <h2 id="faqTitle">Frequently asked questions</h2>
            <p>Helpful details about connecting and managing booths with SnapLab Fleet.</p>
          </div>
          <div class="faq-list">
            <details>
              <summary>How do I get started?</summary>
              <p>Create a booth-owner account, sign in, and register an activated booth using its device details. The booth must be online and configured to report to Fleet.</p>
            </details>
            <details>
              <summary>Why does my booth appear offline?</summary>
              <p>Fleet considers a booth offline when it has not sent a report recently. Check that the booth app is open, the device has working internet, and its Fleet configuration is correct. A newly registered booth may show no report until it checks in.</p>
            </details>
            <details>
              <summary>How often does Fleet update booth status?</summary>
              <p>The dashboard refreshes every five seconds. Booths generally report about every 15 seconds and are marked offline after 90 seconds without a report.</p>
            </details>
            <details>
              <summary>Can I see a booth's location?</summary>
              <p>Location appears only if the booth has permission and location sharing is enabled in the booth app. Otherwise, Fleet still shows the booth's other reported status information.</p>
            </details>
            <details>
              <summary>Can I change booth settings remotely?</summary>
              <p>Supported remote settings and commands are available for eligible connected booths. Some actions require the booth app to be active in the foreground.</p>
            </details>
            <details>
              <summary>Can an owner account see other owners' booths?</summary>
              <p>No. Booth-owner accounts see their own registered devices and related sales. Fleet-wide visibility is reserved for administrator accounts.</p>
            </details>
          </div>
        </div>
      </section>
      <section class="landing-cta" aria-labelledby="ctaTitle">
        <div class="landing-cta-inner">
          <h2 id="ctaTitle">Ready to check in on your booths?</h2>
          <p>Sign in to your Fleet dashboard or create an owner account to get started.</p>
          <div class="hero-actions">
            <a class="landing-button" href="/login">Sign in to Fleet</a>
            <a class="landing-button secondary" href="/register">Create owner account</a>
          </div>
        </div>
      </section>
    </main>
    <footer class="landing-footer">
      <span>© <?= date('Y') ?> SnapLab Fleet</span>
      <nav aria-label="Footer navigation">
        <a href="#home">Home</a>
        <a href="#about">About</a>
        <a href="#faq">FAQ</a>
      </nav>
    </footer>
  </div>
  <main id="loginView" class="login card<?= $fleetPage === 'home' ? ' hidden' : '' ?>">
    <h1>SnapLab Fleet</h1>
    <p>Sign in to manage your photobooths, or create a booth-owner account.</p>
    <form id="loginForm"<?= $fleetPage === 'register' ? ' class="hidden"' : '' ?>>
      <label for="loginEmail">Owner email (leave blank for administrator)</label>
      <input id="loginEmail" type="email" autocomplete="username">
      <label for="password">Password</label>
      <input id="password" type="password" autocomplete="current-password" required>
      <div class="turnstile" id="loginTurnstile"></div>
      <p id="loginError" class="error"></p>
      <button type="submit">Sign in</button>
    </form>
    <p<?= $fleetPage === 'register' ? ' class="hidden"' : '' ?>><button id="showPasswordReset" class="secondary-link" type="button">Forgot password?</button></p>
    <form id="passwordResetRequestForm" class="hidden">
      <h2>Reset your password</h2>
      <p>Enter your owner account email and we’ll send a one-hour password reset link if the account exists.</p>
      <label for="passwordResetEmail">Owner email</label>
      <input id="passwordResetEmail" type="email" maxlength="254" autocomplete="email" required>
      <div class="turnstile" id="resetRequestTurnstile"></div>
      <p id="passwordResetRequestMessage" class="error" aria-live="polite"></p>
      <button type="submit">Send reset link</button>
      <button id="backToLoginFromReset" class="secondary" type="button">Back to sign in</button>
    </form>
    <form id="passwordResetCompleteForm" class="hidden">
      <h2>Choose a new password</h2>
      <p>Choose a password with at least 12 characters.</p>
      <label for="newPassword">New password</label>
      <input id="newPassword" type="password" minlength="12" maxlength="72" autocomplete="new-password" required>
      <label for="newPasswordConfirm">Confirm new password</label>
      <input id="newPasswordConfirm" type="password" minlength="12" maxlength="72" autocomplete="new-password"
        required>
      <p id="passwordResetCompleteMessage" class="error" aria-live="polite"></p>
      <button type="submit">Reset password</button>
      <button id="backToLoginFromComplete" class="secondary" type="button">Back to sign in</button>
    </form>
    <p id="showSignupLink"<?= $fleetPage === 'register' ? ' class="hidden"' : '' ?>><a class="secondary-link" href="/register">Create owner account</a></p>
    <form id="signupForm"<?= $fleetPage === 'register' ? '' : ' class="hidden"' ?>>
      <h2>Create booth-owner account</h2>
      <p>Each account can register activated booths and only view its own devices and sales.</p>
      <label for="signupEmail">Email</label>
      <input id="signupEmail" type="email" maxlength="254" autocomplete="email" required>
      <label for="signupPassword">Password (at least 12 characters)</label>
      <input id="signupPassword" type="password" minlength="12" maxlength="72" autocomplete="new-password" required>
      <label for="signupPasswordConfirm">Confirm password</label>
      <input id="signupPasswordConfirm" type="password" minlength="12" maxlength="72" autocomplete="new-password"
        required>
      <div class="turnstile" id="signupTurnstile"></div>
      <p id="signupError" class="error"></p>
      <button type="submit">Create account</button>
      <a id="showLogin" class="secondary-link" href="/login">Back to sign in</a>
      <p class="muted">Email verification is not configured. Owners can use “Forgot password?” to request a reset link.</p>
    </form>
  </main>
  <main id="dashboard" class="shell hidden">
    <header>
      <div>
        <h1>SnapLab Fleet</h1>
        <p id="dashboardSubtitle" class="subtitle">Online status and sales across your booths</p>
      </div>
      <div class="toolbar"><span id="updated" class="muted" aria-live="polite">Connecting…</span><button id="refresh"
          class="secondary" type="button">Refresh</button><button id="logout" class="secondary">Sign out</button></div>
    </header>
    <p id="welcomeEmailNotice" class="hidden error" role="status" aria-live="polite"></p>
    <section class="summary">
      <div class="card metric"><small>Devices online</small><strong id="onlineCount">0</strong></div>
      <div class="card metric"><small>Total registered booths</small><strong id="deviceCount">0</strong></div>
      <div class="card metric"><small>Needs attention</small><strong id="attentionCount">0</strong></div>
      <div class="card metric"><small>All-time recorded sales</small><strong id="totalSales">₱0</strong></div>
    </section>
    <section id="paymongoSection" class="card section hidden">
      <div class="section-heading">
        <h2>PayMongo QR Ph account</h2>
      </div>
      <p class="muted">Connect your own merchant account. Identity photos are securely forwarded to PayMongo for verification and are not retained by SnapLab after the request.</p>
      <p id="paymongoStatus" class="muted" aria-live="polite"></p>
      <button id="paymongoCreateAccount" type="button">Create PayMongo merchant account</button>
      <form id="paymongoIdentityForm" class="hidden">
        <h3>Identity verification</h3>
        <p class="muted">Use clear images. Images must be JPEG or PNG and no larger than 10 MB each. PayMongo identity sessions expire after 72 hours.</p>
        <label for="paymongoDocumentType">PayMongo document type</label>
        <input id="paymongoDocumentType" name="document_type" type="text" maxlength="80"
          pattern="[a-z0-9_]{3,80}" placeholder="For example: alien_registration_card_ph" required>
        <div class="onboarding-grid">
          <div><label for="paymongoDocumentFront">ID front</label><input id="paymongoDocumentFront"
            name="document_front" type="file" accept="image/jpeg,image/png" required></div>
          <div><label for="paymongoDocumentBack">ID back (if required)</label><input id="paymongoDocumentBack"
            name="document_back" type="file" accept="image/jpeg,image/png"></div>
          <div><label for="paymongoSelfie">Selfie</label><input id="paymongoSelfie"
            name="selfie" type="file" accept="image/jpeg,image/png" required></div>
        </div>
        <button type="submit">Submit identity verification</button>
      </form>
      <form id="paymongoProfileForm" class="hidden">
        <h3>Merchant details</h3>
        <p class="muted">Enter the representative and business details requested by PayMongo. SnapLab sends them to PayMongo and does not store them.</p>
        <div class="onboarding-grid">
          <div><label for="pmFirstName">First name</label><input id="pmFirstName" maxlength="80" required></div>
          <div><label for="pmMiddleName">Middle name (optional)</label><input id="pmMiddleName" maxlength="80"></div>
          <div><label for="pmLastName">Last name</label><input id="pmLastName" maxlength="80" required></div>
          <div><label for="pmMobile">Mobile number with country code</label><input id="pmMobile" type="tel" placeholder="+639XXXXXXXXX" required></div>
          <div><label for="pmEmail">Representative email</label><input id="pmEmail" type="email" maxlength="254" required></div>
          <div><label for="pmBirthDay">Date of birth (day)</label><input id="pmBirthDay" type="number" min="1" max="31" required></div>
          <div><label for="pmBirthMonth">Date of birth (month)</label><input id="pmBirthMonth" type="number" min="1" max="12" required></div>
          <div><label for="pmBirthYear">Date of birth (year)</label><input id="pmBirthYear" type="number" min="1900" required></div>
          <div><label for="pmNationality">3-letter nationality code</label><input id="pmNationality" maxlength="3" value="PHL" pattern="[A-Z]{3}" required></div>
          <div><label for="pmBirthCity">City of birth</label><input id="pmBirthCity" maxlength="80" required></div>
          <div><label for="pmNatureOfWork">Nature of work</label><select id="pmNatureOfWork" required>
            <option value="self_employed">Self-employed</option><option value="employed_locally">Employed locally</option>
            <option value="retired">Retired</option><option value="pensioner">Pensioner</option>
            <option value="ofw">OFW</option><option value="ofw_beneficiary">OFW beneficiary</option>
            <option value="student">Student</option><option value="unemployed_spouse_income">Unemployed with spouse income</option>
            <option value="unemployed_other_income">Unemployed with other income</option>
          </select></div>
          <div><label for="pmSourceOfFunds">Source of funds</label><select id="pmSourceOfFunds" required>
            <option value="other">Other/business</option><option value="salary">Salary</option>
            <option value="allowance">Allowance</option><option value="commission">Commission</option>
            <option value="donation">Donation</option><option value="pension">Pension</option>
          </select></div>
          <div><label for="pmSourceOther">Other funds detail (if selected)</label><input id="pmSourceOther" maxlength="120"></div>
          <div><label for="pmSourceSalary">Employer (if salary selected)</label><input id="pmSourceSalary" maxlength="120"></div>
          <div><label for="pmPersonalTin">Personal TIN (optional)</label><input id="pmPersonalTin" maxlength="32"></div>
          <div><label for="pmHomeAddress">Home address line 1</label><input id="pmHomeAddress" maxlength="120" required></div>
          <div><label for="pmHomeCity">Home city</label><input id="pmHomeCity" maxlength="80" required></div>
          <div><label for="pmHomeState">Home province/state code</label><input id="pmHomeState" maxlength="32" required></div>
          <div><label for="pmHomePostal">Home postal code</label><input id="pmHomePostal" maxlength="16" required></div>
          <div><label for="pmBusinessName">Business/trade name</label><input id="pmBusinessName" maxlength="120" required></div>
          <div><label for="pmBusinessDescription">Business description</label><input id="pmBusinessDescription" maxlength="255" required></div>
          <div><label for="pmIndustry">4-digit merchant category code (MCC)</label><input id="pmIndustry" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required></div>
          <div><label for="pmBusinessAge">Business age</label><select id="pmBusinessAge" required>
            <option value="less_than_1_year">Less than 1 year</option><option value="between_1_and_2_years">1–2 years</option>
            <option value="between_2_and_5_years">2–5 years</option><option value="greater_than_5_years">More than 5 years</option>
          </select></div>
          <div><label for="pmBusinessSize">Number of employees</label><select id="pmBusinessSize" required>
            <option value="less_than_10">Less than 10</option><option value="between_10_and_50">10–50</option>
            <option value="between_51_and_250">51–250</option><option value="greater_than_250">More than 250</option>
          </select></div>
          <div><label for="pmMonthlyVolume">Estimated monthly volume</label><select id="pmMonthlyVolume" required>
            <option value="less_than_100K">Less than ₱100,000</option><option value="between_100K_and_300K">₱100,000–₱300,000</option>
            <option value="between_300K_and_500K">₱300,000–₱500,000</option><option value="between_500K_and_1M">₱500,000–₱1,000,000</option>
            <option value="between_1M_and_3M">₱1,000,000–₱3,000,000</option><option value="greater_than_3M">More than ₱3,000,000</option>
          </select></div>
          <div><label for="pmBusinessAddress">Business address line 1</label><input id="pmBusinessAddress" maxlength="120" required></div>
          <div><label for="pmBusinessCity">Business city</label><input id="pmBusinessCity" maxlength="80" required></div>
          <div><label for="pmBusinessState">Business province/state code</label><input id="pmBusinessState" maxlength="32" required></div>
          <div><label for="pmBusinessPostal">Business postal code</label><input id="pmBusinessPostal" maxlength="16" required></div>
          <div><label for="pmBusinessTin">Business TIN (optional)</label><input id="pmBusinessTin" maxlength="32"></div>
          <div><label for="pmPhysicalStore">Physical store</label><select id="pmPhysicalStore" required>
            <option value="false">No</option><option value="true">Yes</option>
          </select></div>
        </div>
        <button type="submit">Send merchant details to PayMongo</button>
      </form>
      <button id="paymongoActivateAccount" class="hidden" type="button">Activate PayMongo account</button>
    </section>
    <section class="card section">
      <div class="section-heading">
        <h2>Booth locations</h2>
        <div class="toolbar">
          <label class="hidden" for="mapStyle">Map style</label>
          <select id="mapStyle" aria-label="Map style">
            <option value="street">Street</option>
            <option value="satellite">Satellite imagery</option>
            <option value="terrain">Terrain</option>
          </select>
          <span id="mapDeviceCount" class="count">0 locations</span>
        </div>
      </div>
      <p id="fleetMapStatus" class="muted">Booths appear here after sharing their location from the app.</p>
      <div id="fleetMap" class="fleet-map" role="application" aria-label="Map showing all booth locations"></div>
      <div class="map-legend" aria-label="Map pin legend">
        <span><i class="map-dot"></i>Online booth</span>
        <span><i class="map-dot offline"></i>Offline booth</span>
      </div>
    </section>
    <section class="card section">
      <div class="section-heading">
        <h2>Devices</h2><span id="deviceResultCount" class="count"></span>
      </div>
      <div class="filters">
        <input id="deviceSearch" type="search" placeholder="Search device ID" aria-label="Search device ID">
        <select id="statusFilter" aria-label="Filter device status">
          <option value="all">All devices</option>
          <option value="online">Online</option>
          <option value="offline">Offline</option>
          <option value="attention">Needs attention</option>
        </select>
      </div>
      <p class="muted">Use the Device ID and its matching activation code from your booth's Admin screen. Only
        registered booths can report and appear here.</p>
      <form id="registerForm" class="register-form" autocomplete="off">
        <input id="registerDeviceId" name="booth_device_id" type="text" minlength="8" maxlength="128"
          autocomplete="off" placeholder="Enter your booth's Device ID"
          aria-label="Booth device ID to register" required>
        <input id="registerActivationCode" name="booth_activation_code" type="text" maxlength="512"
          autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Booth activation code"
          aria-label="Booth activation code" required>
        <button type="submit">Register booth</button>
      </form>
      <p id="registerMessage" class="register-message" aria-live="polite"></p>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Status</th>
              <th>Device ID</th>
              <th>Last seen</th>
              <th>ESP32</th>
              <th>Camera</th>
              <th>Battery / charging</th>
              <th>All-time sales</th>
            </tr>
          </thead>
          <tbody id="devices"></tbody>
        </table>
      </div>
      <div id="empty" class="empty hidden">No booths registered yet. Enter the Device ID shown in the booth's Admin
        screen to add your booth.</div>
      <div id="noMatches" class="empty hidden">No booths match these filters.</div>
    </section>
    <section id="salesSection" class="card section hidden">
      <h2>Sales by payment method</h2>
      <div id="salesBreakdown" class="detail-grid"></div>
    </section>
    <section id="deviceDetail" class="card section hidden">
      <div class="section-heading">
        <h2 id="deviceTitle">Booth details</h2>
        <div class="toolbar"><button id="unregisterDevice" class="secondary" type="button">Unregister
            booth</button><button id="closeDetail" class="secondary" type="button">Close details</button></div>
      </div>
      <div id="deviceBreakdown" class="detail-grid"></div>
      <div class="section-heading"><h2>Booth location</h2></div>
      <p id="locationStatus" class="muted">Location has not been shared by this booth.</p>
      <div class="section-heading"><h2>Remote booth controls</h2></div>
      <p class="muted">Commands are sent securely and run at the booth's next online check-in.</p>
      <div class="toolbar">
        <button id="restartBoothApp" class="secondary" type="button">Restart booth app</button>
        <button id="rebootBoothDevice" class="secondary" type="button">Reboot Android device</button>
        <button id="pauseBooth" class="secondary" type="button">Pause booth</button>
        <button id="resumeBooth" class="secondary" type="button">Resume booth</button>
        <button id="enableKiosk" class="secondary" type="button">Enable kiosk mode</button>
        <button id="disableKiosk" class="secondary" type="button">Disable kiosk mode</button>
        <button id="checkBoothUpdate" class="secondary" type="button">Check/install update</button>
        <button id="testPrint" class="secondary" type="button">Test print</button>
      </div>
      <p id="commandStatus" class="muted" aria-live="polite"></p>
      <div class="section-heading"><h2>Remote settings</h2></div>
      <p class="muted">Changes apply when the booth is online with the app open. Passwords, payment/API credentials, activation, and Android permissions stay protected. Custom image uploads and local-only file paths must still be managed on the booth.</p>
      <form id="remoteSettingsForm">
        <div class="remote-grid">
          <div>
            <label for="remoteTheme">Event theme</label>
            <select id="remoteTheme">
              <option value="classic">Classic</option><option value="birthday">Birthday</option>
              <option value="wedding">Wedding</option><option value="graduation">Graduation</option>
              <option value="holiday">Christmas</option><option value="summer">Summer</option>
              <option value="coffeeBeans">Coffee Beans</option><option value="coffeeCup">Coffee Cups</option>
              <option value="latteArt">Latte Art</option><option value="valentines">Valentine's Day</option>
            </select>
          </div>
          <div><label for="remoteWelcome">Welcome message</label><input id="remoteWelcome" maxlength="36" required></div>
          <div>
            <label for="remoteIdleTimeout">Idle timeout</label>
            <select id="remoteIdleTimeout">
              <option value="30">30 seconds</option><option value="60">1 minute</option>
              <option value="120">2 minutes</option><option value="300">5 minutes</option>
            </select>
          </div>
          <div>
            <label for="remotePrinter">Paired printer</label>
            <select id="remotePrinter"></select>
          </div>
        </div>
        <label>Available photo counts</label>
        <div class="photo-count-options">
          <label><input type="checkbox" name="photoCount" value="1">1</label>
          <label><input type="checkbox" name="photoCount" value="2">2</label>
          <label><input type="checkbox" name="photoCount" value="3">3</label>
          <label><input type="checkbox" name="photoCount" value="4">4</label>
          <label><input type="checkbox" name="photoCount" value="5">5</label>
        </div>
        <div class="remote-grid">
          <div><label for="remoteCamera">Camera</label><select id="remoteCamera"><option value="back">Back</option><option value="front">Front</option></select></div>
          <div><label for="remoteCountdown">Countdown</label><select id="remoteCountdown"><option value="1">1 second</option><option value="2">2 seconds</option><option value="3">3 seconds</option><option value="4">4 seconds</option><option value="5">5 seconds</option></select></div>
          <div><label for="remotePreview">Photo preview</label><select id="remotePreview"><option value="3">3 seconds</option><option value="5">5 seconds</option><option value="8">8 seconds</option><option value="10">10 seconds</option><option value="15">15 seconds</option></select></div>
          <div><label for="remoteBorder">Photo border</label><select id="remoteBorder">
            <option value="none">None</option><option value="classic">Classic</option><option value="party">Party</option><option value="elegant">Elegant</option><option value="christmas">Christmas</option><option value="valentinesDay">Valentine's Day</option><option value="halloween">Halloween</option><option value="newYear">New Year</option><option value="birthday">Birthday</option><option value="wedding">Wedding</option><option value="easter">Easter</option><option value="summer">Summer</option><option value="graduation">Graduation</option><option value="mothersDay">Mother's Day</option><option value="lunarNewYear">Lunar New Year</option><option value="diwali">Diwali</option><option value="babyShower">Baby Shower</option><option value="anniversary">Anniversary</option>
          </select></div>
          <div><label for="remoteEffect">Photo effect</label><select id="remoteEffect">
            <option value="original">Original</option><option value="vivid">Vivid</option><option value="warm">Warm</option><option value="monochrome">B&amp;W</option><option value="vintage">Vintage</option><option value="cartoon">Cartoon</option><option value="soft">Soft</option><option value="cool">Cool</option><option value="rose">Rose</option><option value="matte">Matte</option><option value="sepia">Sepia</option><option value="cinematic">Cinematic</option><option value="pastel">Pastel</option><option value="fade">Fade</option>
          </select></div>
          <div><label for="remoteLogoAnimation">Logo animation</label><select id="remoteLogoAnimation"><option value="none">None</option><option value="jump">Jump</option><option value="pump">Pump</option><option value="sway">Sway</option><option value="float">Float</option></select></div>
          <div><label for="remotePrinterType">Printer type</label><select id="remotePrinterType"><option value="receipt">Receipt printer</option><option value="color">Color printer</option></select></div>
          <div><label for="remotePaperWidth">Receipt width</label><select id="remotePaperWidth"><option value="384">58 mm</option><option value="576">80 mm</option></select></div>
          <div><label for="remoteBrightness">Receipt brightness (20–50%)</label><input id="remoteBrightness" type="number" min="20" max="50" step="5"></div>
          <div><label for="remoteCutMode">Receipt cut</label><select id="remoteCutMode"><option value="full">Full cut</option><option value="partial">Partial cut</option></select></div>
          <div><label for="remoteCopies">Print copies</label><select id="remoteCopies"><option value="1">1</option><option value="2">2</option><option value="3">3</option></select></div>
          <div><label for="remoteCoinPrice">Coin session price (₱)</label><input id="remoteCoinPrice" type="number" min="1" max="100000"></div>
          <div><label for="remotePayMongoAmount">PayMongo amount (₱)</label><input id="remotePayMongoAmount" type="number" min="1" max="100000"></div>
          <div><label for="remoteChargeStart">Charging start (%)</label><input id="remoteChargeStart" type="number" min="0" max="99"></div>
          <div><label for="remoteChargeStop">Charging stop (%)</label><input id="remoteChargeStop" type="number" min="1" max="100"></div>
        </div>
        <div class="photo-count-options">
          <label><input id="remoteVoiceGuidance" type="checkbox">Voice guidance</label>
          <label><input id="remoteWalletPayments" type="checkbox">Ganap payments</label>
          <label><input id="remotePayMongoPayments" type="checkbox">PayMongo payments</label>
          <label><input id="remoteLiveWallpaper" type="checkbox">Live wallpaper</label>
          <label><input id="remoteIdleVideoLoop" type="checkbox">Loop idle video</label>
          <label><input id="remoteLocationSharing" type="checkbox">Share location</label>
        </div>
        <button type="submit">Apply remote settings</button>
        <p id="remoteSettingsStatus" class="muted" aria-live="polite"></p>
      </form>
    </section>
    <p class="muted">Live updates refresh every 5 seconds. Booths report about every 15 seconds and appear offline after
      90 seconds without a report.</p>
  </main>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
    integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
  <script nonce="<?= htmlspecialchars($cspNonce, ENT_QUOTES, 'UTF-8') ?>">
    const fleetPage = <?= json_encode($fleetPage, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    const revealTargets = document.querySelectorAll(
      '.landing-section .section-intro, .feature-card, .about-panel, .faq-list details, .landing-cta-inner'
    );
    const reducedLandingMotion = window.matchMedia(
      '(prefers-reduced-motion: reduce)'
    ).matches;
    const landingSections = [...document.querySelectorAll('#home, #about, #faq')];
    const sectionNavLinks = [
      ...document.querySelectorAll('.landing-links a[href^="#"]')
    ];
    let navigationAnimationTimer;
    const setActiveLandingLink = id => {
      sectionNavLinks.forEach(link => {
        if (link.hash === `#${id}`) {
          link.setAttribute('aria-current', 'location');
        } else {
          link.removeAttribute('aria-current');
        }
      });
    };
    document.querySelectorAll('.landing a[href^="#"]').forEach(link => {
      link.addEventListener('click', event => {
        if (
          event.defaultPrevented ||
          event.button !== 0 ||
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey
        ) return;
        const target = document.getElementById(link.hash.slice(1));
        if (!target) return;
        event.preventDefault();
        if (window.location.hash !== link.hash) {
          history.pushState(null, '', link.hash);
        }
        setActiveLandingLink(target.id);
        target.classList.remove('nav-arrive');
        if (!reducedLandingMotion) {
          document.body.classList.remove('is-navigating');
          clearTimeout(navigationAnimationTimer);
          void document.body.offsetWidth;
          target.classList.add('nav-arrive');
          document.body.classList.add('is-navigating');
          navigationAnimationTimer = setTimeout(() => {
            document.body.classList.remove('is-navigating');
            target.classList.remove('nav-arrive');
          }, 760);
        }
        target.scrollIntoView({
          behavior: reducedLandingMotion ? 'auto' : 'smooth',
          block: 'start'
        });
      });
    });
    if (
      'IntersectionObserver' in window &&
      !reducedLandingMotion
    ) {
      const revealObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        });
      }, { threshold: 0.14 });
      revealTargets.forEach((element, index) => {
        element.classList.add('reveal');
        element.style.setProperty('--reveal-delay', `${(index % 3) * 80}ms`);
        revealObserver.observe(element);
      });
      document.documentElement.classList.add('motion-ready');
    }
    if ('IntersectionObserver' in window) {
      const activeSectionObserver = new IntersectionObserver(entries => {
        const visibleSections = entries
          .filter(entry => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio);
        if (visibleSections.length > 0) {
          setActiveLandingLink(visibleSections[0].target.id);
        }
      }, { rootMargin: '-18% 0px -65% 0px', threshold: [0, 0.1, 0.3, 0.6] });
      landingSections.forEach(section => activeSectionObserver.observe(section));
    }
    const turnstileSiteKey = <?= json_encode($turnstileSiteKey, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    const landingView = document.querySelector('#landingView');
    const loginView = document.querySelector('#loginView');
    const dashboard = document.querySelector('#dashboard');
    const tableBody = document.querySelector('#devices');
    let csrfToken = '';
    let fleetRole = '';
    let currentDevices = [];
    let selectedDeviceId = '';
    let refreshInProgress = false;
    let turnstileReady = false;
    const turnstileWidgets = {};
    let passwordResetToken = new URLSearchParams(window.location.search).get('reset') || '';
    let passwordResetMode = passwordResetToken !== '';
    let fleetMap;
    let fleetMarkerLayer;
    let fleetTileLayer;
    const mapStyles = {
      street: {
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 19
      },
      satellite: {
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 19
      },
      terrain: {
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 19
      }
    };
    const fleetMarkers = new Map();
    let fleetMapBoundsSignature = '';

    window.onTurnstileLoaded = () => {
      turnstileReady = true;
      if (!loginView.classList.contains('hidden')) {
        if (!document.querySelector('#loginForm').classList.contains('hidden')) renderTurnstile('login');
        if (!document.querySelector('#signupForm').classList.contains('hidden')) renderTurnstile('signup');
        if (!document.querySelector('#passwordResetRequestForm').classList.contains('hidden')) {
          renderTurnstile('resetRequest');
        }
      }
    };
    function renderTurnstile(formName) {
      if (!turnstileReady || !turnstileSiteKey) return;
      if (turnstileWidgets[formName] !== undefined) {
        window.turnstile.reset(turnstileWidgets[formName]);
        return;
      }
      turnstileWidgets[formName] = window.turnstile.render(
        '#' + formName + 'Turnstile',
        {
          sitekey: turnstileSiteKey,
          action: {
            login: 'fleet_login',
            signup: 'fleet_signup',
            resetRequest: 'fleet_password_reset'
          }[formName]
        }
      );
    }
    function turnstileToken(formName) {
      const widgetId = turnstileWidgets[formName];
      return widgetId === undefined ? '' : window.turnstile.getResponse(widgetId);
    }
    function resetTurnstile(formName) {
      const widgetId = turnstileWidgets[formName];
      if (widgetId !== undefined) window.turnstile.reset(widgetId);
    }

    const api = async (action, options = {}) => {
      const response = await fetch('/pb_fleet_api?action=' + action, {
        credentials: 'same-origin',
        cache: 'no-store',
        ...options
      });
      const body = await response.json();
      if (!response.ok) throw Object.assign(new Error(body.error || 'Request failed'), {
        status: response.status,
        providerStatus: body.providerStatus,
        providerCode: body.providerCode,
        providerDetail: body.providerDetail,
        providerPointer: body.providerPointer
      });
      return body;
    };
    const peso = value => '₱' + Number(value || 0).toLocaleString('en-PH');
    const timestamp = value => value ? new Date(value * 1000).toLocaleString() : '—';
    const metric = (label, value) => '<div class="detail"><small>' + label + '</small><strong>' + value + '</strong></div>';
    const sum = (devices, key) => devices.reduce((total, device) => total + Number(device.sales?.[key] || 0), 0);
    const formatCommandSummary = summary => {
      if (!summary) return '';
      const [command, state, ...messageParts] = String(summary).split(':');
      const message = messageParts.join(':');
      const commandLabel = {
        disable_kiosk: 'Disable kiosk mode',
        check_app_update: 'Check app update'
      }[command] || command.replaceAll('_', ' ');
      if (state === 'failed') {
        return commandLabel + ' failed' + (message ? ': ' + message : '');
      }
      if (message === 'kiosk_disabled') return 'Kiosk mode disabled successfully.';
      if (message === 'update_installer_opened') return 'Update found; Android installer opened.';
      const noUpdate = message.match(/^no_update_available_build_(\d+)$/);
      if (noUpdate) return 'No newer update available (installed build ' + noUpdate[1] + ').';
      return commandLabel + ': ' + [state, message].filter(Boolean).join(' · ');
    };
    const escapeHtml = value => {
      const node = document.createElement('span');
      node.textContent = String(value);
      return node.innerHTML;
    };
    const needsAttention = device => {
      if (!device.lastSeen) return false;
      const status = device.status || {};
      return !device.online || !status.cameraReady || !status.esp32Connected ||
        status.paused || (status.batteryPercent != null && status.batteryPercent <= 20) ||
        (status.printerHealth && status.printerHealth !== 'Ready' &&
          status.printerHealth !== 'Not configured');
    };

    function showLogin() {
      history.replaceState(null, '', '/login');
      currentDevices = [];
      selectedDeviceId = '';
      tableBody.replaceChildren();
      document.querySelector('#deviceDetail').classList.add('hidden');
      document.querySelector('#salesSection').classList.add('hidden');
      document.querySelector('#onlineCount').textContent = '0';
      document.querySelector('#deviceCount').textContent = '0';
      document.querySelector('#attentionCount').textContent = '0';
      document.querySelector('#totalSales').textContent = '₱0';
      document.querySelector('#signupForm').classList.add('hidden');
      document.querySelector('#passwordResetRequestForm').classList.add('hidden');
      document.querySelector('#passwordResetCompleteForm').classList.add('hidden');
      document.querySelector('#loginForm').classList.remove('hidden');
      document.querySelector('#showPasswordReset').classList.remove('hidden');
      document.querySelector('#showSignupLink').classList.remove('hidden');
      document.querySelector('#showPasswordReset').classList.remove('hidden');
      document.querySelector('#password').value = '';
      document.querySelector('#signupPassword').value = '';
      document.querySelector('#signupPasswordConfirm').value = '';
      landingView.classList.add('hidden');
      dashboard.classList.add('hidden');
      loginView.classList.remove('hidden');
      renderTurnstile('login');
    }
    function showDashboard(role) {
      history.replaceState(null, '', '/');
      fleetRole = role || 'admin';
      document.querySelector('#registerDeviceId').value = '';
      document.querySelector('#registerActivationCode').value = '';
      currentDevices = [];
      selectedDeviceId = '';
      tableBody.replaceChildren();
      document.querySelector('#deviceDetail').classList.add('hidden');
      document.querySelector('#salesSection').classList.add('hidden');
      document.querySelector('#onlineCount').textContent = '0';
      document.querySelector('#deviceCount').textContent = '0';
      document.querySelector('#attentionCount').textContent = '0';
      document.querySelector('#totalSales').textContent = '₱0';
      document.querySelector('#dashboardSubtitle').textContent = fleetRole === 'admin'
        ? 'Fleet-wide online status and sales'
        : 'Online status and sales for your booths';
      document.querySelector('#paymongoSection').classList.toggle('hidden', fleetRole !== 'user');
      document.querySelector('#welcomeEmailNotice').classList.add('hidden');
      document.querySelector('#registerActivationCode').required = fleetRole === 'user';
      landingView.classList.add('hidden');
      loginView.classList.add('hidden');
      dashboard.classList.remove('hidden');
      requestAnimationFrame(() => {
        if (fleetMap && window.google?.maps) {
          window.google.maps.event.trigger(fleetMap, 'resize');
        }
      });
    }
    function renderMetric(label, value) {
      return metric(escapeHtml(label), escapeHtml(value));
    }
    function renderDevice(device) {
      const status = device.status || {};
      const sales = device.sales || {};
      const battery = status.batteryPercent;
      const locationStatus = document.querySelector('#locationStatus');
      document.querySelector('#deviceTitle').textContent = 'Booth ' + device.deviceId;
      document.querySelector('#deviceBreakdown').innerHTML = [
        renderMetric('Connection', !device.lastSeen ? 'Waiting for first report' :
          device.online ? 'Online' : 'Offline'),
        renderMetric('First seen', timestamp(device.firstSeen)),
        renderMetric('Last report', timestamp(device.lastSeen)),
        renderMetric('ESP32', !device.lastSeen ? '—' : !device.online ? 'Unknown (stale)' :
          status.esp32Connected ? 'Connected' : 'Not detected'),
        renderMetric('Camera', !device.lastSeen ? '—' :
          status.cameraReady ? 'Ready' : 'Unavailable'),
        renderMetric('Kiosk mode', !device.lastSeen ? '—' :
          status.kioskActive ? 'Active' : 'Inactive'),
        renderMetric('Paused', !device.lastSeen ? '—' : status.paused ? 'Yes' : 'No'),
        renderMetric('Battery', battery == null ? '—' :
          battery + '%' + (status.charging === true ? ' · Charging' : '')),
        renderMetric('Charging', !device.lastSeen || typeof status.charging !== 'boolean'
          ? '—' : status.charging ? 'Yes' : 'No'),
        renderMetric('Free storage', status.storageFreeBytes == null ? '—' :
          (status.storageFreeBytes / 1073741824).toFixed(1) + ' GB'),
        renderMetric('Printer', status.printerHealth || '—'),
        renderMetric('All-time sales', peso(sales.totalSales)),
        renderMetric('Coin sales', peso(sales.totalCoinSales)),
        renderMetric('QR Ph sales', peso(sales.totalQrPhSales)),
        renderMetric('All-time transactions', Number(sales.totalTransactions || 0).toLocaleString()),
        renderMetric('Coin transactions', Number(sales.totalCoinTransactions || 0).toLocaleString()),
        renderMetric('QR Ph transactions', Number(sales.totalQrPhTransactions || 0).toLocaleString()),
        renderMetric('Sales today', peso(sales.salesToday)),
        renderMetric('Coin sales today', peso(sales.coinSalesToday)),
        renderMetric('QR Ph sales today', peso(sales.qrPhSalesToday)),
        renderMetric('Sales this week', peso(sales.salesThisWeek))
      ].join('');
      if (Number.isFinite(status.latitude) && Number.isFinite(status.longitude)) {
        const coordinates = status.latitude.toFixed(6) + ', ' + status.longitude.toFixed(6);
        const accuracy = Number.isFinite(status.locationAccuracyMeters)
          ? ' · accuracy ±' + Math.round(status.locationAccuracyMeters) + ' m'
          : '';
        locationStatus.textContent = coordinates + accuracy + ' · captured ' +
          timestamp(status.locationTimestamp || device.lastSeen);
      } else {
        locationStatus.textContent = device.online
          ? 'No location shared. Enable location sharing in the booth app’s Admin settings.'
          : 'Booth is offline or has not shared a location yet.';
      }
      const settings = device.remoteSettings || {};
      const currentSettings = { ...(status.appSettings || {}), ...settings };
      document.querySelector('#restartBoothApp').disabled =
        !device.online || status.appForeground !== true;
      document.querySelector('#rebootBoothDevice').disabled =
        !device.online || status.appForeground !== true;
      const onlineForeground = device.online && status.appForeground === true;
      document.querySelector('#pauseBooth').disabled =
        !onlineForeground || status.paused === true;
      document.querySelector('#resumeBooth').disabled =
        !onlineForeground || status.paused !== true;
      document.querySelector('#enableKiosk').disabled =
        !onlineForeground || status.kioskActive === true;
      document.querySelector('#disableKiosk').disabled =
        !onlineForeground || status.kioskActive !== true;
      document.querySelector('#checkBoothUpdate').disabled = !onlineForeground;
      document.querySelector('#testPrint').disabled =
        !onlineForeground || currentSettings.printerType === 'color' ||
        !(currentSettings.printerAddress || status.pairedPrinters?.length);
      document.querySelector('#remoteTheme').value = currentSettings.eventTheme || 'classic';
      document.querySelector('#remoteWelcome').value = currentSettings.welcomeMessage || 'TAKE HOME A MEMORY';
      document.querySelector('#remoteIdleTimeout').value = String(currentSettings.idleTimeoutSeconds || 30);
      const printerSelect = document.querySelector('#remotePrinter');
      printerSelect.replaceChildren(new Option('No printer selected', ''));
      for (const printer of status.pairedPrinters || []) {
        const option = new Option(printer.name + ' · ' + printer.address, printer.address);
        printerSelect.add(option);
      }
      printerSelect.value = currentSettings.printerAddress || '';
      const availableCounts = currentSettings.photoCounts || [1, 2, 3, 4, 5];
      document.querySelectorAll('input[name="photoCount"]').forEach(input => {
        input.checked = availableCounts.includes(Number(input.value));
      });
      document.querySelector('#remoteCamera').value = currentSettings.cameraDirection || 'back';
      document.querySelector('#remoteCountdown').value = String(currentSettings.countdownDuration || 3);
      document.querySelector('#remotePreview').value = String(currentSettings.previewDuration || 5);
      const remoteBorder = document.querySelector('#remoteBorder');
      remoteBorder.value = currentSettings.photoBorderStyle || 'none';
      if (!remoteBorder.value) remoteBorder.value = 'none';
      document.querySelector('#remoteEffect').value = currentSettings.liveEffect || 'original';
      document.querySelector('#remoteLogoAnimation').value = currentSettings.brandLogoAnimation || 'none';
      document.querySelector('#remotePrinterType').value = currentSettings.printerType || 'receipt';
      document.querySelector('#remotePaperWidth').value = String(currentSettings.receiptWidthDots || 576);
      document.querySelector('#remoteBrightness').value = String(Math.round((currentSettings.receiptBrightness ?? 0.35) * 100));
      document.querySelector('#remoteCutMode').value = currentSettings.receiptCutMode || 'full';
      document.querySelector('#remoteCopies').value = String(currentSettings.printCopies || 1);
      document.querySelector('#remoteCoinPrice').value = String(currentSettings.coinPricePesos || 20);
      document.querySelector('#remotePayMongoAmount').value = String(currentSettings.payMongoAmountPesos || 20);
      document.querySelector('#remoteChargeStart').value = String(currentSettings.chargeStartPercent ?? 20);
      document.querySelector('#remoteChargeStop').value = String(currentSettings.chargeStopPercent ?? 90);
      document.querySelector('#remoteVoiceGuidance').checked = currentSettings.voiceGuidanceEnabled === true;
      const walletPayments = document.querySelector('#remoteWalletPayments');
      walletPayments.checked = currentSettings.walletPaymentEnabled === true;
      walletPayments.disabled = currentSettings.walletPaymentsAvailable === false;
      const payMongoPayments = document.querySelector('#remotePayMongoPayments');
      payMongoPayments.checked = currentSettings.payMongoPaymentsEnabled === true;
      payMongoPayments.disabled = currentSettings.payMongoPaymentsAvailable === false;
      document.querySelector('#remoteLiveWallpaper').checked = currentSettings.liveWallpaperEnabled === true;
      document.querySelector('#remoteIdleVideoLoop').checked = currentSettings.idleVideoLoop !== false;
      document.querySelector('#remoteLocationSharing').checked = currentSettings.fleetLocationSharingEnabled === true;
      document.querySelector('#commandStatus').textContent = device.commandSummary
        ? 'Latest command: ' + formatCommandSummary(device.commandSummary)
        : '';
      document.querySelector('#unregisterDevice').dataset.deviceId = device.deviceId;
      document.querySelector('#deviceDetail').classList.remove('hidden');
    }
    function renderRows() {
      const search = document.querySelector('#deviceSearch').value.trim().toLowerCase();
      const filter = document.querySelector('#statusFilter').value;
      const visible = currentDevices.filter(device => {
        if (!device.deviceId.toLowerCase().includes(search)) return false;
        if (filter === 'online' && !device.online) return false;
        if (filter === 'offline' && device.online) return false;
        if (filter === 'attention' && !needsAttention(device)) return false;
        return true;
      });
      tableBody.innerHTML = visible.map(device => {
        const status = device.status || {};
        const battery = status.batteryPercent;
        const warning = needsAttention(device);
        return '<tr class="device-row" tabindex="0" role="button" aria-label="View booth ' +
          device.deviceId + '" data-device-id="' + device.deviceId + '">' +
          '<td><span class="badge ' + (!device.lastSeen ? '' :
            device.online ? 'online' : 'offline') +
          '"><i class="dot"></i>' + (!device.lastSeen ? 'Waiting for first report' :
            device.online ? 'Online' : 'Offline') + '</span></td>' +
          '<td>' + device.deviceId + (warning ? ' <span class="status-text status-warn">· Attention</span>' : '') + '</td>' +
          '<td>' + timestamp(device.lastSeen) + '</td>' +
          '<td class="status-text ' + (status.esp32Connected && device.online ? 'status-good' :
            device.lastSeen && device.online ? 'status-warn' : '') + '">' +
          (!device.lastSeen ? '—' : !device.online ? 'Unknown (stale)' :
            status.esp32Connected ? 'Connected' : 'Not detected') + '</td>' +
          '<td class="status-text ' + (status.cameraReady ? 'status-good' :
            device.lastSeen ? 'status-bad' : '') + '">' +
          (!device.lastSeen ? '—' : status.cameraReady ? 'Ready' : 'Unavailable') + '</td>' +
          '<td class="status-text ' + (battery != null && battery <= 20 ? 'status-warn' : '') + '">' +
          (battery == null ? '—' : battery + '%' +
            (status.charging === true ? ' · Charging' : '')) + '</td><td>' +
          peso(device.sales?.totalSales) + '</td></tr>';
      }).join('');
      document.querySelector('#deviceResultCount').textContent =
        visible.length + ' of ' + currentDevices.length + ' booths';
      document.querySelector('#empty').classList.toggle('hidden', currentDevices.length > 0);
      document.querySelector('#noMatches').classList.toggle('hidden',
        currentDevices.length === 0 || visible.length > 0);
    }
    function renderFleet() {
      const online = currentDevices.filter(device => device.online).length;
      const attention = currentDevices.filter(needsAttention).length;
      document.querySelector('#onlineCount').textContent = online;
      document.querySelector('#deviceCount').textContent = currentDevices.length;
      document.querySelector('#attentionCount').textContent = attention;
      document.querySelector('#totalSales').textContent = peso(sum(currentDevices, 'totalSales'));
      document.querySelector('#salesBreakdown').innerHTML = [
        renderMetric('Coin sales', peso(sum(currentDevices, 'totalCoinSales'))),
        renderMetric('QR Ph sales', peso(sum(currentDevices, 'totalQrPhSales'))),
        renderMetric('Coin transactions', sum(currentDevices, 'totalCoinTransactions').toLocaleString()),
        renderMetric('QR Ph transactions', sum(currentDevices, 'totalQrPhTransactions').toLocaleString()),
        renderMetric('Sales today', peso(sum(currentDevices, 'salesToday'))),
        renderMetric('Sales this week', peso(sum(currentDevices, 'salesThisWeek')))
      ].join('');
      document.querySelector('#salesSection').classList.toggle('hidden', currentDevices.length === 0);
      renderRows();
      renderFleetMap();
      if (selectedDeviceId) {
        const selected = currentDevices.find(device => device.deviceId === selectedDeviceId);
        if (selected) renderDevice(selected);
        else closeDetails();
      }
    }
    function ensureFleetMap() {
      if (fleetMap) return;
      fleetMap = window.L.map('fleetMap', { scrollWheelZoom: false })
        .setView([12.8797, 121.7740], 5);
      setFleetMapStyle(document.querySelector('#mapStyle').value);
      fleetMarkerLayer = window.L.layerGroup().addTo(fleetMap);
    }
    function setFleetMapStyle(styleName) {
      if (!fleetMap) return;
      const style = mapStyles[styleName] || mapStyles.street;
      const nextLayer = window.L.tileLayer(style.url, {
        maxZoom: style.maxZoom,
        attribution: 'Tiles &copy; <a href="https://www.esri.com/">Esri</a> &mdash; Sources: Esri, TomTom, Garmin, FAO, NOAA, USGS, &copy; OpenStreetMap contributors, and the GIS User Community'
      });
      if (fleetTileLayer) fleetMap.removeLayer(fleetTileLayer);
      fleetTileLayer = nextLayer.addTo(fleetMap);
    }
    function renderFleetMap() {
      ensureFleetMap();
      const locations = currentDevices.filter(device =>
        Number.isFinite(device.status?.latitude) &&
        Number.isFinite(device.status?.longitude) &&
        device.status.latitude >= -90 && device.status.latitude <= 90 &&
        device.status.longitude >= -180 && device.status.longitude <= 180
      );
      const locationIds = new Set(locations.map(device => device.deviceId));
      for (const [deviceId, record] of fleetMarkers) {
        if (!locationIds.has(deviceId)) {
          fleetMarkerLayer.removeLayer(record.marker);
          fleetMarkers.delete(deviceId);
        }
      }
      const coordinates = [];
      for (const device of locations) {
        const { latitude, longitude } = device.status;
        const coordinateKey = latitude + ',' + longitude;
        const online = device.online === true;
        const color = online ? '#36c98f' : '#9aa6b2';
        const popup = '<strong>Booth ' + escapeHtml(device.deviceId) + '</strong><br>' +
          (online ? 'Online' : 'Offline') + '<br>Last report: ' +
          escapeHtml(timestamp(device.lastSeen));
        let record = fleetMarkers.get(device.deviceId);
        if (!record) {
          const marker = window.L.circleMarker([latitude, longitude], {
            radius: 9,
            color: '#ffffff',
            weight: 2,
            fillColor: color,
            fillOpacity: 0.95
          }).addTo(fleetMarkerLayer);
          marker.bindPopup(popup);
          record = { marker, coordinateKey, online, popup };
          fleetMarkers.set(device.deviceId, record);
        } else {
          if (record.coordinateKey !== coordinateKey) {
            record.marker.setLatLng([latitude, longitude]);
            record.coordinateKey = coordinateKey;
          }
          if (record.online !== online) {
            record.marker.setStyle({ fillColor: color });
            record.online = online;
          }
          if (record.popup !== popup) {
            record.marker.setPopupContent(popup);
            record.popup = popup;
          }
        }
        coordinates.push([latitude, longitude]);
      }
      const count = locations.length;
      document.querySelector('#mapDeviceCount').textContent =
        count + (count === 1 ? ' location' : ' locations');
      document.querySelector('#fleetMapStatus').textContent = count
        ? 'Showing every booth with a reported location. Pins update without reloading the map.'
        : 'No booths have shared a location yet. Enable location sharing in each booth’s Admin settings.';
      const boundsSignature = locations
        .map(device => device.deviceId)
        .sort()
        .join('|');
      if (coordinates.length && boundsSignature !== fleetMapBoundsSignature) {
        fleetMapBoundsSignature = boundsSignature;
        if (coordinates.length === 1) {
          fleetMap.setView(coordinates[0], 14);
        } else {
          fleetMap.fitBounds(window.L.latLngBounds(coordinates).pad(0.15), { maxZoom: 14 });
        }
      } else if (!coordinates.length) {
        fleetMapBoundsSignature = '';
      }
      requestAnimationFrame(() => fleetMap.invalidateSize());
    }
    function closeDetails() {
      selectedDeviceId = '';
      document.querySelector('#deviceDetail').classList.add('hidden');
    }
    async function refresh() {
      if (refreshInProgress) return;
      refreshInProgress = true;
      const updated = document.querySelector('#updated');
      try {
        const data = await api('devices');
        csrfToken = data.csrfToken;
        currentDevices = data.devices || [];
        renderFleet();
        renderPaymongo(data.paymongo);
        updated.textContent = 'Updated ' + new Date().toLocaleTimeString();
      } catch (error) {
        if (error.status === 401) {
          showLogin();
        } else {
          updated.textContent = 'Refresh failed · retrying';
          console.error('Fleet refresh failed:', error);
        }
      } finally {
        refreshInProgress = false;
      }
    }
    function renderPaymongo(state) {
      if (fleetRole !== 'user') return;
      const accountStatus = state?.accountStatus || 'not_started';
      const identityStatus = state?.identityStatus || 'not_started';
      const profileSubmitted = state?.profileSubmitted === true;
      const activated = accountStatus === 'activated';
      const status = document.querySelector('#paymongoStatus');
      status.textContent = activated
        ? 'Your PayMongo merchant account is active and connected to your booths.'
        : accountStatus === 'not_started'
          ? 'Create your linked merchant account to start accepting QR Ph payments into your own PayMongo account.'
          : accountStatus === 'creating'
            ? 'Your PayMongo account is being created. Refresh in a few minutes if this does not change.'
            : identityStatus === 'pending' || identityStatus === 'in_progress'
              ? 'Identity verification is processing. This page will update when PayMongo sends the verification result.'
              : identityStatus === 'failed'
                ? 'Identity verification did not pass. Review PayMongo’s failure notice and submit a new verification.'
                : identityStatus === 'passed'
                  ? profileSubmitted
                    ? 'Identity verification passed. Send or update your merchant details, then activate the account.'
                    : 'Identity verification passed. Complete your merchant details to continue.'
                  : 'Your linked PayMongo account is created. Submit the representative’s ID and selfie for verification.';
      document.querySelector('#paymongoCreateAccount').classList.toggle('hidden',
        accountStatus !== 'not_started' && accountStatus !== 'creating');
      document.querySelector('#paymongoIdentityForm').classList.toggle('hidden',
        accountStatus !== 'pending' ||
        identityStatus === 'pending' ||
        identityStatus === 'in_progress' ||
        activated);
      document.querySelector('#paymongoProfileForm').classList.toggle('hidden',
        identityStatus !== 'passed' || activated);
      document.querySelector('#paymongoActivateAccount').classList.toggle('hidden',
        identityStatus !== 'passed' || !profileSubmitted || activated);
    }

    document.querySelector('#paymongoCreateAccount').addEventListener('click', async event => {
      const button = event.currentTarget;
      button.disabled = true;
      document.querySelector('#paymongoStatus').textContent = 'Creating your linked PayMongo merchant account…';
      try {
        await api('paymongo_create_account', {
          method: 'POST',
          headers: { 'X-CSRF-Token': csrfToken }
        });
        await refresh();
      } catch (error) {
        document.querySelector('#paymongoStatus').textContent =
          'Could not create the PayMongo account: ' + error.message;
      } finally {
        button.disabled = false;
      }
    });
    document.querySelector('#paymongoIdentityForm').addEventListener('submit', async event => {
      event.preventDefault();
      const form = event.currentTarget;
      const status = document.querySelector('#paymongoStatus');
      const submit = form.querySelector('button[type="submit"]');
      submit.disabled = true;
      status.textContent = 'Securely sending identity documents to PayMongo…';
      try {
        await api('paymongo_identity_verification', {
          method: 'POST',
          headers: { 'X-CSRF-Token': csrfToken },
          body: new FormData(form)
        });
        form.reset();
        await refresh();
      } catch (error) {
        status.textContent = error.message === 'unsupported_identity_image'
          ? 'Choose a JPEG or PNG image.'
          : error.message === 'invalid_identity_upload' || error.message === 'identity_upload_too_large'
            ? 'Each ID/selfie image must be valid and no larger than 10 MB.'
            : error.message === 'identity_verification_in_progress'
              ? 'PayMongo is already processing an identity verification.'
              : error.message === 'paymongo_request_failed'
                ? 'PayMongo rejected the verification request (HTTP ' +
                  (error.providerStatus || 'unknown') +
                  (error.providerCode ? ', code ' + error.providerCode : '') +
                  (error.providerPointer ? ', field ' + error.providerPointer : '') +
                  '). ' +
                  (error.providerDetail || 'Check the document type and image requirements.') +
                  ' Contact PayMongo support if the issue continues.'
                : error.message === 'paymongo_invalid_response'
                  ? 'PayMongo returned an unreadable response. Please try again later.'
                  : 'Could not submit identity verification: ' + error.message;
      } finally {
        submit.disabled = false;
      }
    });
    document.querySelector('#paymongoProfileForm').addEventListener('submit', async event => {
      event.preventDefault();
      const value = id => document.querySelector(id).value.trim();
      const address = prefix => ({
        line1: value('#' + prefix + 'Address'),
        city: value('#' + prefix + 'City'),
        state: value('#' + prefix + 'State'),
        country: 'PH',
        postal_code: value('#' + prefix + 'Postal')
      });
      const profile = {
        person: {
          first_name: value('#pmFirstName'),
          middle_name: value('#pmMiddleName'),
          last_name: value('#pmLastName'),
          mobile_number: value('#pmMobile'),
          email_address: value('#pmEmail'),
          date_of_birth: {
            day: Number(value('#pmBirthDay')),
            month: Number(value('#pmBirthMonth')),
            year: Number(value('#pmBirthYear'))
          },
          nationality: value('#pmNationality').toUpperCase(),
          nature_of_work: value('#pmNatureOfWork'),
          birth_city: value('#pmBirthCity'),
          source_of_funds: value('#pmSourceOfFunds'),
          source_of_funds_other: value('#pmSourceOther'),
          source_of_funds_salary: value('#pmSourceSalary'),
          tin: value('#pmPersonalTin'),
          address: address('pmHome')
        },
        business: {
          trade_name: value('#pmBusinessName'),
          description: value('#pmBusinessDescription'),
          industry: value('#pmIndustry'),
          age: value('#pmBusinessAge'),
          size: value('#pmBusinessSize'),
          estimated_monthly_volume: value('#pmMonthlyVolume'),
          physical_store: value('#pmPhysicalStore') === 'true',
          tin: value('#pmBusinessTin'),
          address: address('pmBusiness')
        }
      };
      const status = document.querySelector('#paymongoStatus');
      const submit = event.currentTarget.querySelector('button[type="submit"]');
      submit.disabled = true;
      status.textContent = 'Sending merchant details securely to PayMongo…';
      try {
        await api('paymongo_update_account', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
          body: JSON.stringify(profile)
        });
        await refresh();
      } catch (error) {
        status.textContent = 'Could not update PayMongo merchant details: ' + error.message;
      } finally {
        submit.disabled = false;
      }
    });
    const updatePaymongoFundsRequirements = () => {
      const source = document.querySelector('#pmSourceOfFunds').value;
      document.querySelector('#pmSourceOther').required = source === 'other';
      document.querySelector('#pmSourceSalary').required = source === 'salary';
    };
    document.querySelector('#pmSourceOfFunds').addEventListener(
      'change',
      updatePaymongoFundsRequirements
    );
    updatePaymongoFundsRequirements();
    document.querySelector('#paymongoActivateAccount').addEventListener('click', async event => {
      const button = event.currentTarget;
      button.disabled = true;
      document.querySelector('#paymongoStatus').textContent = 'Requesting PayMongo account activation…';
      try {
        await api('paymongo_activate_account', {
          method: 'POST',
          headers: { 'X-CSRF-Token': csrfToken }
        });
        await refresh();
      } catch (error) {
        document.querySelector('#paymongoStatus').textContent =
          'PayMongo could not activate the account: ' + error.message +
          '. Update the business details and try again.';
      } finally {
        button.disabled = false;
      }
    });

    tableBody.addEventListener('click', event => {
      const row = event.target.closest('tr[data-device-id]');
      if (!row) return;
      selectedDeviceId = row.dataset.deviceId;
      const selected = currentDevices.find(device => device.deviceId === selectedDeviceId);
      if (selected) renderDevice(selected);
    });
    tableBody.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        const row = event.target.closest('tr[data-device-id]');
        if (row) {
          event.preventDefault();
          row.click();
        }
      }
    });
    document.querySelector('#deviceSearch').addEventListener('input', renderRows);
    document.querySelector('#statusFilter').addEventListener('change', renderRows);
    document.querySelector('#closeDetail').addEventListener('click', closeDetails);
    document.querySelector('#refresh').addEventListener('click', refresh);
    document.querySelector('#mapStyle').addEventListener('change', event => {
      setFleetMapStyle(event.target.value);
    });
    async function sendRemoteCommand(command, description) {
      const selectedDevice = currentDevices.find(device => device.deviceId === selectedDeviceId);
      if (!selectedDevice?.online || selectedDevice.status?.appForeground !== true) {
        document.querySelector('#commandStatus').textContent =
          'This command requires the booth app to be online and open.';
        return;
      }
      if (!selectedDeviceId || !confirm(description + ' on booth ' + selectedDeviceId + '?')) return;
      const status = document.querySelector('#commandStatus');
      status.textContent = 'Sending command…';
      try {
        const result = await api('remote_command', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
          body: JSON.stringify({ deviceId: selectedDeviceId, command })
        });
        status.textContent = 'Command queued (#' + result.commandId +
          '). It will run when the booth checks in.';
        await refresh();
      } catch (error) {
        status.textContent = error.message === 'device_not_online'
          ? 'This command requires the booth app to be online and open.'
          : 'Could not send command: ' + error.message;
      }
    }
    document.querySelector('#restartBoothApp').addEventListener('click', () =>
      sendRemoteCommand('restart_app', 'Restart the booth app'));
    document.querySelector('#rebootBoothDevice').addEventListener('click', () =>
      sendRemoteCommand('reboot_device', 'Reboot the Android device'));
    document.querySelector('#pauseBooth').addEventListener('click', () =>
      sendRemoteCommand('pause_booth', 'Pause the booth'));
    document.querySelector('#resumeBooth').addEventListener('click', () =>
      sendRemoteCommand('resume_booth', 'Resume the booth'));
    document.querySelector('#enableKiosk').addEventListener('click', () =>
      sendRemoteCommand('enable_kiosk', 'Enable kiosk mode'));
    document.querySelector('#disableKiosk').addEventListener('click', () =>
      sendRemoteCommand('disable_kiosk', 'Disable kiosk mode'));
    document.querySelector('#checkBoothUpdate').addEventListener('click', () =>
      sendRemoteCommand('check_app_update', 'Check for and install an available app update'));
    document.querySelector('#testPrint').addEventListener('click', () =>
      sendRemoteCommand('test_print', 'Send a receipt-printer test page'));
    document.querySelector('#remoteSettingsForm').addEventListener('submit', async event => {
      event.preventDefault();
      if (!selectedDeviceId) return;
      const status = document.querySelector('#remoteSettingsStatus');
      const photoCounts = [...document.querySelectorAll('input[name="photoCount"]:checked')]
        .map(input => Number(input.value));
      if (photoCounts.length === 0) {
        status.textContent = 'Select at least one photo count.';
        return;
      }
      status.textContent = 'Saving remote settings…';
      try {
        await api('remote_settings', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
          body: JSON.stringify({
            deviceId: selectedDeviceId,
            settings: {
              eventTheme: document.querySelector('#remoteTheme').value,
              welcomeMessage: document.querySelector('#remoteWelcome').value.trim(),
              idleTimeoutSeconds: Number(document.querySelector('#remoteIdleTimeout').value),
              photoCounts,
              printerAddress: document.querySelector('#remotePrinter').value,
              cameraDirection: document.querySelector('#remoteCamera').value,
              countdownDuration: Number(document.querySelector('#remoteCountdown').value),
              previewDuration: Number(document.querySelector('#remotePreview').value),
              photoBorderStyle: document.querySelector('#remoteBorder').value,
              liveEffect: document.querySelector('#remoteEffect').value,
              voiceGuidanceEnabled: document.querySelector('#remoteVoiceGuidance').checked,
              brandLogoAnimation: document.querySelector('#remoteLogoAnimation').value,
              printerType: document.querySelector('#remotePrinterType').value,
              receiptWidthDots: Number(document.querySelector('#remotePaperWidth').value),
              receiptBrightness: Number(document.querySelector('#remoteBrightness').value) / 100,
              receiptCutMode: document.querySelector('#remoteCutMode').value,
              printCopies: Number(document.querySelector('#remoteCopies').value),
              walletPaymentEnabled: document.querySelector('#remoteWalletPayments').checked,
              payMongoPaymentsEnabled: document.querySelector('#remotePayMongoPayments').checked,
              coinPricePesos: Number(document.querySelector('#remoteCoinPrice').value),
              payMongoAmountPesos: Number(document.querySelector('#remotePayMongoAmount').value),
              liveWallpaperEnabled: document.querySelector('#remoteLiveWallpaper').checked,
              idleVideoLoop: document.querySelector('#remoteIdleVideoLoop').checked,
              fleetLocationSharingEnabled: document.querySelector('#remoteLocationSharing').checked,
              chargeStartPercent: Number(document.querySelector('#remoteChargeStart').value),
              chargeStopPercent: Number(document.querySelector('#remoteChargeStop').value)
            }
          })
        });
        status.textContent = 'Settings saved. The booth will apply them at its next online check-in. Passwords, payment credentials, and OS permissions remain local/secured.';
        await refresh();
      } catch (error) {
        status.textContent = 'Could not save settings: ' + error.message;
      }
    });
    document.querySelector('#registerForm').addEventListener('submit', async event => {
      event.preventDefault();
      const message = document.querySelector('#registerMessage');
      const deviceId = document.querySelector('#registerDeviceId').value.trim();
      const activationCode = document.querySelector('#registerActivationCode').value.trim();
      message.classList.remove('success');
      message.textContent = '';
      try {
        await api('register', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
          body: JSON.stringify({ deviceId, activationCode })
        });
        document.querySelector('#registerDeviceId').value = '';
        document.querySelector('#registerActivationCode').value = '';
        message.classList.add('success');
        message.textContent = 'Booth registered. Waiting for its first report; keep the activated app open and online.';
        await refresh();
      } catch (error) {
        message.textContent = error.status === 401 && error.message === 'activation_required'
          ? 'Activation code is invalid or does not match this Device ID.'
          : error.status === 409
            ? 'This booth is already registered to another account.'
            : error.message === 'server_ed25519_support_unavailable'
              ? 'The server is not configured to verify activation codes. Contact the site administrator.'
              : error.message === 'fleet_database_not_configured'
                ? 'Fleet MySQL is not configured. Contact the site administrator.'
                : error.message === 'fleet_database_unavailable'
                  ? 'The fleet database is unavailable. Contact the site administrator.'
                  : error.status === 401
                    ? 'Your session expired. Sign in again.'
                    : 'Could not register this booth. Check the Device ID and try again.';
      }
    });
    document.querySelector('#unregisterDevice').addEventListener('click', async event => {
      const deviceId = event.currentTarget.dataset.deviceId;
      if (!deviceId || !confirm('Unregister booth ' + deviceId + '? It will no longer appear or report to this dashboard.')) {
        return;
      }
      try {
        await api('unregister', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
          body: JSON.stringify({ deviceId })
        });
        closeDetails();
        await refresh();
      } catch (error) {
        document.querySelector('#updated').textContent = 'Could not unregister booth · retry';
        console.error('Fleet booth unregister failed:', error);
      }
    });
    document.querySelector('#loginForm').addEventListener('submit', async event => {
      event.preventDefault();
      const error = document.querySelector('#loginError');
      error.textContent = '';
      const challengeToken = turnstileToken('login');
      if (!challengeToken) {
        error.textContent = !turnstileSiteKey
          ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
          : 'Complete the Cloudflare security check, then try again.';
        return;
      }
      try {
        const result = await api('login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: document.querySelector('#loginEmail').value.trim(),
            password: document.querySelector('#password').value,
            turnstileToken: challengeToken
          })
        });
        csrfToken = result.csrfToken;
        document.querySelector('#password').value = '';
        showDashboard(result.role);
        await refresh();
      } catch (failure) {
        error.textContent = failure.message === 'fleet_database_not_configured'
          ? 'Fleet MySQL is not configured. Contact the site administrator.'
          : failure.message === 'fleet_database_unavailable'
            ? 'The fleet database is unavailable. Contact the site administrator.'
            : failure.message === 'turnstile_not_configured'
              ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
              : failure.message === 'turnstile_verification_unavailable'
                ? 'Cloudflare could not be reached. Please try again.'
                : failure.message === 'turnstile_verification_failed'
                  ? 'Cloudflare could not verify the check. Please try again.'
                  : failure.status === 429
                    ? 'Too many attempts. Try again in 15 minutes.'
                    : 'Sign-in failed. Check the password and try again.';
        resetTurnstile('login');
      }
    });
    const showPasswordResetRequest = () => {
      landingView.classList.add('hidden');
      dashboard.classList.add('hidden');
      loginView.classList.remove('hidden');
      document.querySelector('#loginForm').classList.add('hidden');
      document.querySelector('#signupForm').classList.add('hidden');
      document.querySelector('#passwordResetCompleteForm').classList.add('hidden');
      document.querySelector('#showPasswordReset').classList.add('hidden');
      document.querySelector('#showSignupLink').classList.add('hidden');
      document.querySelector('#passwordResetRequestForm').classList.remove('hidden');
      const requestMessage = document.querySelector('#passwordResetRequestMessage');
      requestMessage.classList.add('error');
      requestMessage.textContent = '';
      const email = document.querySelector('#loginEmail').value.trim();
      if (email) document.querySelector('#passwordResetEmail').value = email;
      renderTurnstile('resetRequest');
    };
    const showPasswordResetComplete = () => {
      landingView.classList.add('hidden');
      dashboard.classList.add('hidden');
      loginView.classList.remove('hidden');
      document.querySelector('#loginForm').classList.add('hidden');
      document.querySelector('#signupForm').classList.add('hidden');
      document.querySelector('#passwordResetRequestForm').classList.add('hidden');
      document.querySelector('#showPasswordReset').classList.add('hidden');
      document.querySelector('#showSignupLink').classList.add('hidden');
      document.querySelector('#passwordResetCompleteForm').classList.remove('hidden');
    };
    document.querySelector('#showPasswordReset').addEventListener('click', showPasswordResetRequest);
    document.querySelector('#backToLoginFromReset').addEventListener('click', showLogin);
    document.querySelector('#backToLoginFromComplete').addEventListener('click', showLogin);
    document.querySelector('#passwordResetRequestForm').addEventListener('submit', async event => {
      event.preventDefault();
      const message = document.querySelector('#passwordResetRequestMessage');
      message.textContent = '';
      const challengeToken = turnstileToken('resetRequest');
      if (!challengeToken) {
        message.textContent = !turnstileSiteKey
          ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
          : 'Complete the Cloudflare security check, then try again.';
        return;
      }
      try {
        const result = await api('password_reset_request', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: document.querySelector('#passwordResetEmail').value.trim(),
            turnstileToken: challengeToken
          })
        });
        message.classList.remove('error');
        message.textContent = result.message ||
          'If an owner account exists for that email, reset instructions will be sent.';
      } catch (failure) {
        message.classList.add('error');
        message.textContent = failure.message === 'turnstile_not_configured'
          ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
          : failure.message === 'turnstile_verification_unavailable'
            ? 'Cloudflare could not be reached. Please try again.'
            : failure.message === 'turnstile_verification_failed'
              ? 'Cloudflare could not verify the check. Please try again.'
              : failure.message === 'invalid_reset_request'
                ? 'Enter a valid email address.'
                : failure.status === 429
                  ? 'Too many reset attempts. Try again in 15 minutes.'
                  : failure.message === 'reset_email_unavailable'
                    ? 'The reset email could not be sent. Contact the site administrator.'
                    : 'Could not request a password reset. Please try again.';
        resetTurnstile('resetRequest');
      }
    });
    document.querySelector('#passwordResetCompleteForm').addEventListener('submit', async event => {
      event.preventDefault();
      const message = document.querySelector('#passwordResetCompleteMessage');
      message.textContent = '';
      const password = document.querySelector('#newPassword').value;
      if (password !== document.querySelector('#newPasswordConfirm').value) {
        message.textContent = 'The passwords do not match.';
        return;
      }
      if (!/^[a-f0-9]{64}$/i.test(passwordResetToken)) {
        message.textContent = 'This reset link is invalid or expired. Request a new one.';
        return;
      }
      try {
        await api('password_reset_complete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: passwordResetToken, password })
        });
        passwordResetToken = '';
        passwordResetMode = false;
        document.querySelector('#newPassword').value = '';
        document.querySelector('#newPasswordConfirm').value = '';
        history.replaceState(null, '', window.location.pathname);
        showLogin();
        document.querySelector('#loginError').textContent =
          'Password reset successfully. Sign in with your new password.';
      } catch (failure) {
        message.textContent = failure.message === 'invalid_or_expired_reset'
          ? 'This reset link is invalid or expired. Request a new one.'
          : failure.message === 'fleet_database_not_configured'
            ? 'Fleet MySQL is not configured. Contact the site administrator.'
            : failure.message === 'fleet_database_unavailable'
              ? 'The fleet database is unavailable. Contact the site administrator.'
              : failure.status === 429
                ? 'Too many reset attempts. Try again in 15 minutes.'
                : 'Could not reset the password. Please try again.';
      }
    });
    document.querySelector('#signupForm').addEventListener('submit', async event => {
      event.preventDefault();
      const error = document.querySelector('#signupError');
      const password = document.querySelector('#signupPassword').value;
      error.textContent = '';
      if (password !== document.querySelector('#signupPasswordConfirm').value) {
        error.textContent = 'The passwords do not match.';
        return;
      }
      const challengeToken = turnstileToken('signup');
      if (!challengeToken) {
        error.textContent = !turnstileSiteKey
          ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
          : 'Complete the Cloudflare security check, then try again.';
        return;
      }
      try {
        const result = await api('signup', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: document.querySelector('#signupEmail').value.trim(),
            password,
            turnstileToken: challengeToken
          })
        });
        csrfToken = result.csrfToken;
        document.querySelector('#signupPassword').value = '';
        document.querySelector('#signupPasswordConfirm').value = '';
        showDashboard(result.role);
        const welcomeEmailNotice = document.querySelector('#welcomeEmailNotice');
        const welcomeEmailError = result.welcomeEmailError;
        welcomeEmailNotice.textContent =
          welcomeEmailError === 'email_smtp_not_configured'
            ? 'Your account was created, but the email service is not configured correctly. Contact the site administrator.'
            : welcomeEmailError === 'email_dependency_unavailable'
              ? 'Your account was created, but the email service is missing a required server component. Contact the site administrator.'
              : result.welcomeEmailSent === false
                ? 'Your account was created, but SMTP could not deliver the welcome email. Check your spam folder or contact the site administrator.'
                : '';
        welcomeEmailNotice.classList.toggle('hidden', result.welcomeEmailSent !== false);
        await refresh();
      } catch (failure) {
        error.textContent = failure.message === 'fleet_database_not_configured'
          ? 'Fleet MySQL is not configured. Contact the site administrator.'
          : failure.message === 'fleet_database_unavailable'
            ? 'The fleet database is unavailable. Contact the site administrator.'
            : failure.message === 'turnstile_not_configured'
              ? 'Cloudflare Turnstile is not configured. Contact the site administrator.'
              : failure.message === 'turnstile_verification_unavailable'
                ? 'Cloudflare could not be reached. Please try again.'
                : failure.message === 'turnstile_verification_failed'
                  ? 'Cloudflare could not verify the check. Please try again.'
                  : failure.status === 409
                    ? 'An account with that email already exists. Sign in instead.'
                    : failure.status === 429
                      ? 'Too many attempts. Try again in 15 minutes.'
                      : failure.message === 'invalid_signup'
                        ? 'Enter a valid email and a password with at least 12 characters.'
                        : 'Account creation failed. Please try again.';
        resetTurnstile('signup');
      }
    });
    document.querySelector('#logout').addEventListener('click', async () => {
      try {
        await api('logout', { method: 'POST', headers: { 'X-CSRF-Token': csrfToken } });
      } finally {
        showLogin();
      }
    });
    if (/^[a-f0-9]{64}$/i.test(passwordResetToken)) {
      passwordResetMode = true;
      history.replaceState(null, '', window.location.pathname);
      showPasswordResetComplete();
    } else if (passwordResetToken !== '') {
      passwordResetToken = '';
      passwordResetMode = true;
      history.replaceState(null, '', window.location.pathname);
      showPasswordResetComplete();
      document.querySelector('#passwordResetCompleteMessage').textContent =
        'This reset link is invalid or expired. Request a new one.';
    }
    api('devices').then(data => {
      csrfToken = data.csrfToken;
      showDashboard(data.role);
      refresh();
    }).catch(error => {
      if (error.status === 503 && fleetPage !== 'home') {
        landingView.classList.add('hidden');
        loginView.classList.remove('hidden');
        document.querySelector('#loginError').textContent =
          error.message === 'fleet_database_not_configured'
            ? 'Fleet MySQL is not configured. Contact the site administrator.'
            : 'The fleet database is unavailable or its schema needs setup.';
      } else if (fleetPage === 'login' && !passwordResetMode) {
        showLogin();
      }
    });
    if (fleetPage === 'register') renderTurnstile('signup');
    setInterval(() => {
      if (!dashboard.classList.contains('hidden')) refresh();
    }, 5000);
  </script>
  <script nonce="<?= htmlspecialchars($cspNonce, ENT_QUOTES, 'UTF-8') ?>"
    src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoaded&amp;render=explicit"
    defer></script>
</body>

</html>