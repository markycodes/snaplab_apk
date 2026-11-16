import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

enum AppLanguage { english, tagalog }

final appLanguageNotifier = ValueNotifier(AppLanguage.english);

String translateAppText(String text, AppLanguage language) {
  if (language == AppLanguage.english) return text;
  const installErrorPrefix = 'Could not install the update: ';
  if (text.startsWith(installErrorPrefix)) {
    return 'Hindi ma-install ang update: ${text.substring(installErrorPrefix.length)}';
  }
  const saveLanguageErrorPrefix = 'Could not save the language setting: ';
  if (text.startsWith(saveLanguageErrorPrefix)) {
    return 'Hindi ma-save ang setting ng wika: ${text.substring(saveLanguageErrorPrefix.length)}';
  }
  const includedPrefix = 'Included: ';
  if (text.startsWith(includedPrefix)) {
    return 'Kasama: ${text.substring(includedPrefix.length)}';
  }
  const cartoonProgressPrefix = 'Creating cartoon photo ';
  if (text.startsWith(cartoonProgressPrefix) && text.endsWith('...')) {
    final progress = text.substring(
      cartoonProgressPrefix.length,
      text.length - 3,
    );
    return 'Ginagawa ang cartoon na litrato $progress...';
  }
  if (text.startsWith('PHOTO ') && text.contains(' OF ')) {
    final separator = text.indexOf(' OF ');
    return 'LITRATO ${text.substring(6, separator)} SA ${text.substring(separator + 4)}';
  }
  const notPairedPrefix = 'Not paired · ';
  if (text.startsWith(notPairedPrefix)) {
    return 'Hindi nakapares · ${text.substring(notPairedPrefix.length)}';
  }
  const insertCoinsPrefix = 'OR INSERT ';
  if (text.startsWith(insertCoinsPrefix) &&
      text.endsWith(' PER SESSION TO START')) {
    final price = text.substring(
      insertCoinsPrefix.length,
      text.length - ' PER SESSION TO START'.length,
    );
    return 'O MAGHULOG NG $price BARYA PARA MAGSIMULA';
  }
  const insertedCreditsPrefix = 'INSERTED ₱';
  if (text.startsWith(insertedCreditsPrefix)) {
    return 'NAILAGAY NA ₱${text.substring(insertedCreditsPrefix.length)}';
  }
  const perSessionSuffix = ' per session';
  if (text.endsWith(perSessionSuffix)) {
    return '${text.substring(0, text.length - perSessionSuffix.length)} bawat sesyon';
  }
  if (text.endsWith(' · ONE SESSION PRICE')) {
    final count = text.substring(
      0,
      text.length - ' · ONE SESSION PRICE'.length,
    );
    return '$count LITRATO · PRESYO PARA SA ISANG SESYON';
  }
  if (text.endsWith(' seconds')) {
    return '${text.substring(0, text.length - ' seconds'.length)} segundo';
  }
  if (text.endsWith(' minutes')) {
    return '${text.substring(0, text.length - ' minutes'.length)} minuto';
  }
  if (text.endsWith(' copies')) {
    return '${text.substring(0, text.length - ' copies'.length)} kopya';
  }
  if (text.endsWith(' copy')) {
    return '${text.substring(0, text.length - ' copy'.length)} kopya';
  }
  if (text.startsWith('Please insert ₱') && text.endsWith(' more.')) {
    return 'Mangyaring maghulog pa ng ${text.substring('Please insert '.length)}';
  }
  if (text.startsWith('PAY ₱') && text.endsWith(' VIA QR PH · PER SESSION')) {
    final amount = text.substring(
      4,
      text.length - ' VIA QR PH · PER SESSION'.length,
    );
    return 'MAGBAYAD NG ₱$amount SA QR PH · BAWAT SESYON';
  }
  if (text.startsWith('New version ') && text.contains(' is available.')) {
    return text
        .replaceFirst('New version ', 'May bagong bersyon ')
        .replaceFirst(
          ' is available. Download and confirm installation to update.',
          ' na. I-download at kumpirmahin ang pag-install para mag-update.',
        );
  }
  return _tagalogTranslations[text] ?? text;
}

const _tagalogTranslations = <String, String>{
  'START PHOTO SESSION': 'SIMULAN ANG SESYON NG LITRATO',
  'Start Photo Session': 'Simulan ang Sesyon ng Litrato',
  'Make it yours': 'Gawin itong iyo',
  'Customize your photos': 'Ayusin ang iyong mga litrato',
  'Review your finished photo': 'Suriin ang natapos mong litrato',
  'Choose filters, stickers, and a layout':
      'Pumili ng filter, sticker, at layout',
  'Your memory is ready': 'Handa na ang iyong alaala',
  'YOUR PHOTO IS PRINTING': 'INI-PRINT ANG IYONG LITRATO',
  'PHOTO SENT TO PRINTER': 'IPINADALA NA SA PRINTER',
  'Please wait while your photo comes out.':
      'Pakihintay habang inilalabas ang iyong litrato.',
  'Your print request was accepted.':
      'Tinanggap na ang kahilingan mong mag-print.',
  'Your photo is ready': 'Handa na ang iyong litrato',
  'Review the full-quality preview. Go back if you want to make an adjustment.':
      'Suriin ang malinaw na preview. Bumalik kung may nais kang baguhin.',
  'Choose the original photo or create an AI cartoon version. Your original stays available.': 'Piliin ang orihinal na litrato o gumawa ng AI cartoon. Mananatiling available ang orihinal.',
  'Use original photo': 'Gamitin ang orihinal na litrato',
  'Original photo selected': 'Napili ang orihinal na litrato',
  'Creating cartoon...': 'Ginagawa ang cartoon...',
  'AI cartoon selected': 'Napili ang AI cartoon',
  'Create AI cartoon': 'Gumawa ng AI cartoon',
  'Use AI cartoon': 'Gamitin ang AI cartoon',
  'Are you sure you want to convert this image into a cartoon?':
      'Sigurado ka bang gusto mong gawing cartoon ang larawang ito?',
  'Creating cartoon photos can take a few minutes.':
      'Maaaring umabot ng ilang minuto ang paggawa ng mga cartoon na litrato.',
  'Your photo is ready.': 'Handa na ang iyong litrato.',
  'Choose your photos': 'Pumili ng mga litrato',
  'Choose a photo count to begin': 'Pumili ng dami ng litrato para magsimula',
  'Choose your session': 'Piliin ang iyong sesyon',
  'Select the number of photos': 'Piliin ang dami ng mga litrato',
  'HOW MANY PHOTOS?': 'ILANG LITRATO?',
  'No classic templates are currently available.':
      'Walang available na classic na template sa ngayon.',
  'Tap a layout to choose your photo count. You can customize your frame after capturing.': 'Pumili ng layout para itakda ang dami ng litrato. Maaari mong ayusin ang frame pagkatapos kumuha.',
  'Quick session': 'Mabilis na sesyon',
  'Most popular': 'Pinakapaborito',
  'More memories': 'Mas maraming alaala',
  'PHOTOS': 'LITRATO',
  'PAYMENT METHOD': 'PARAAN NG PAGBABAYAD',
  'CHOOSE PAYMENT METHOD': 'PUMILI NG PARAAN NG PAGBABAYAD',
  'Insert Coins': 'Maghulog ng Barya',
  'Scan QR PH': 'I-scan ang QR PH',
  'No payment method is available right now. Please contact the booth attendant.': 'Walang magagamit na paraan ng pagbabayad sa ngayon. Makipag-ugnayan sa attendant ng booth.',
  'or': 'o',
  'Scan with QR PH': 'Mag-scan gamit ang QR PH',
  'Preparing your secure QR PH payment…':
      'Inihahanda ang ligtas mong bayad sa QR PH…',
  'Open your QR PH app and scan the code above.':
      'Buksan ang iyong QR PH app at i-scan ang code sa itaas.',
  'QR image could not load.': 'Hindi ma-load ang QR image.',
  'COINS': 'BARYA',
  'QR PAY': 'BAYAD QR',
  'CONTINUE': 'MAGPATULOY',
  'TAP TO BEGIN': 'PINDUTIN PARA MAGSIMULA',
  'TAP TO START': 'PINDUTIN PARA MAGSIMULA',
  'ACTIVATE DEVICE': 'I-ACTIVATE ANG DEVICE',
  'APP UPDATES': 'MGA UPDATE NG APP',
  'APPLY CODE': 'ILAPAT ANG CODE',
  'Activate Photobooth': 'I-activate ang Photobooth',
  'Allow PayMongo QR Ph payments': 'Payagan ang bayad gamit ang PayMongo QR Ph',
  'Android installer opened. Confirm the installation to update Snap Lab.': 'Binuksan ang Android installer. Kumpirmahin ang pag-install para i-update ang Snap Lab.',
  'Attendant: tap the top-left corner five times for admin diagnostics.': 'Attendant: pindutin nang limang beses ang kaliwang sulok sa itaas para sa admin diagnostics.',
  'BOOTH LOGO': 'LOGO NG BOOTH',
  'BOOTH UPDATE AVAILABLE': 'MAY AVAILABLE NA UPDATE NG BOOTH',
  'Booth temporarily unavailable': 'Pansamantalang hindi magagamit ang booth',
  'Border preview unavailable': 'Hindi available ang preview ng border',
  'CUSTOMER DECORATIONS': 'MGA DEKORASYON NG CUSTOMER',
  'CUSTOMER PNG FRAME GALLERY': 'GALLERY NG PNG FRAME NG CUSTOMER',
  'Checkout requires the Ganap project UUID and signing secret to be set in the private Hostinger configuration.': 'Kailangan ang Ganap project UUID at signing secret sa pribadong configuration ng Hostinger para makapag-checkout.',
  'Choose how the logo moves on the home screen and photo-count page.': 'Piliin kung paano gagalaw ang logo sa home screen at pahina ng pagpili ng dami ng litrato.',
  'Coin-slot pricing is separate from QR payment pricing. Ganap QRPh retains its existing ₱20 checkout amount.': 'Hiwalay ang presyo ng hulog-barya sa bayad sa QR. Nananatili sa ₱20 ang checkout ng Ganap QRPh.',
  'Coins are counted at ₱1 per credit':
      'Bawat credit ay katumbas ng ₱1 na barya',
  'Controls QR Ph payments only. Coin-slot sessions use the separate coin-slot price above.': 'QR Ph payment lang ang naaapektuhan nito. Hiwalay ang presyo para sa hulog-barya.',
  'Could not create the photo preview. Please try another look.':
      'Hindi nagawa ang preview ng litrato. Subukan ang ibang itsura.',
  'Create an AI cartoon?': 'Gumawa ng AI cartoon?',
  'Custom borders need a transparent center so the photo remains visible.': 'Kailangang transparent ang gitna ng custom border para makita ang litrato.',
  'ESP32 AND COIN PAYMENT BYPASSED': 'NALAKTAWAN ANG ESP32 AT BAYAD SA BARYA',
  'ESP32 connection:': 'Koneksyon sa ESP32:',
  'Enable Bluetooth and power on the ESP32. Requires the PhotoboothSmartChargeServer sketch for smart charging.': 'I-on ang Bluetooth at ESP32. Kailangan ang PhotoboothSmartChargeServer sketch para sa smart charging.',
  'Enable full-screen live wallpaper':
      'Paganahin ang full-screen na live wallpaper',
  'Guests choose when to print by tapping “Print my photo”. The selected copy count is used.': 'Pipili ang mga bisita kung kailan magpi-print sa pamamagitan ng pagpindot sa “I-print ang litrato ko”. Gagamitin ang napiling dami ng kopya.',
  'Home image preview unavailable': 'Hindi available ang preview ng home image',
  'IDLE HOME SCREEN': 'IDLE NA HOME SCREEN',
  'After 10 minutes without activity, hide the home screen and show only the selected wallpaper. Tapping it opens photo selection.': 'Pagkalipas ng 10 minutong walang aktibidad, itago ang home screen at ipakita lang ang napiling wallpaper. Pindutin ito para pumili ng litrato.',
  'Drag the photo left or right to adjust the crop; edges may be cropped': 'I-drag pakaliwa o pakanan ang litrato para ayusin ang crop; maaaring maputol ang mga gilid.',
  'GANAP QRPH PAYMENT': 'BAYAD GAMIT ANG GANAP QRPH',
  'Preconfigured for activated booths. The app requests a short-lived upload credential from the secure server; no upload token needs to be entered or stored on this device. Download links expire after 7 days.': 'Naka-configure na para sa mga activated na booth. Humihingi ang app ng panandaliang upload credential mula sa secure server; hindi kailangang maglagay o mag-imbak ng upload token sa device na ito. Mag-e-expire ang mga download link pagkalipas ng 7 araw.',
  'Start': 'Simulan',
  'Upload a transparent PNG with 1–5 enclosed photo openings. The app detects the photo count and fits each photo into its opening.': 'Mag-upload ng transparent na PNG na may 1–5 saradong butas para sa litrato. Tutukuyin ng app ang dami ng litrato at iaangkop ang bawat isa sa butas nito.',
  'Upload transparent PNG or WebP stickers customers can drag, resize, and add to their photos. Up to 50 images, 12 MB each.': 'Mag-upload ng transparent na PNG o WebP sticker na maaaring ilipat, palakihin, paliitin, at idagdag ng mga customer sa kanilang litrato. Hanggang 50 larawan, 12 MB bawat isa.',
  'Use only on a trusted private Wi-Fi network. Browser traffic is not encrypted.': 'Gamitin lamang sa pinagkakatiwalaang pribadong Wi-Fi. Hindi naka-encrypt ang trapiko ng browser.',
  'Increase brightness if photo prints look too dark. This affects receipt printers only.': 'Dagdagan ang liwanag kung masyadong madilim ang print. Para lang ito sa receipt printer.',
  'LATER': 'MAMAYA',
  'Logo preview unavailable': 'Hindi available ang preview ng logo',
  'Mirror captured photos': 'I-mirror ang mga nakuhang litrato',
  'ONLINE PHOTO DOWNLOAD': 'ONLINE NA PAG-DOWNLOAD NG LITRATO',
  'Open one of these addresses on a device connected to the same Wi-Fi. Sign in with this admin password.': 'Buksan ang isa sa mga address na ito sa device na nakakonekta sa parehong Wi-Fi. Mag-sign in gamit ang admin password na ito.',
  'PAYMONGO QRPH PAYMENT': 'BAYAD GAMIT ANG PAYMONGO QRPH',
  'PHOTO BORDER': 'BORDER NG LITRATO',
  'Please ask the attendant for assistance.': 'Humingi ng tulong sa attendant.',
  'Please wait a moment...': 'Mangyaring maghintay sandali...',
  'Please wait — your full-quality photo is being prepared.':
      'Pakihintay — inihahanda ang malinaw na kopya ng iyong litrato.',
  'Payment Successful!': 'Matagumpay ang pagbabayad!',
  'Photo preview could not be displayed.':
      'Hindi maipakita ang preview ng litrato.',
  'PRINTER SETUP': 'SETUP NG PRINTER',
  'Paste the replacement code issued for this device. Its signed license determines which payment providers this booth can use.': 'I-paste ang pamalit na code para sa device na ito. Tinutukoy ng lisensya kung aling payment provider ang magagamit ng booth.',
  'PayMongo API keys are kept on the Hostinger server. Upload paymongo_common.php, paymongo_checkout.php, and paymongo_status.php after configuring the private server keys.': 'Nasa Hostinger server ang mga PayMongo API key. I-upload ang paymongo_common.php, paymongo_checkout.php, at paymongo_status.php matapos i-configure ang pribadong server key.',
  'Refresh paired devices': 'I-refresh ang mga nakapares na device',
  'Requires the PhotoboothSmartChargeServer sketch on the ESP32. Charging starts below the start level and stops when the battery reaches the stop level.': 'Kailangan ang PhotoboothSmartChargeServer sketch sa ESP32. Magsisimula ang pag-charge kapag mababa sa panimulang antas at hihinto sa itinakdang antas ng baterya.',
  'Scan to download': 'I-scan para i-download',
  'Sends the standard ESC/POS cut command after each copy. Automatic cutting requires a built-in cutter; if one mode does not work, try the other. Color-printer cutting is controlled by its Android printer service.': 'Nagpapadala ng karaniwang ESC/POS cut command pagkatapos ng bawat kopya. Kailangan ng built-in cutter para sa automatic na pagputol. Kung hindi gumana ang isang mode, subukan ang isa pa. Kinokontrol ng Android printer service ang pagputol sa color printer.',
  'Share booth location with SnapLab Fleet':
      'Ibahagi ang lokasyon ng booth sa SnapLab Fleet',
  'Shares approximate coordinates only while the app is open. Location permission is required.': 'Ibinabahagi lamang ang tinatayang lokasyon habang bukas ang app. Kailangan ang pahintulot sa lokasyon.',
  'Shown on the idle home screen and customer photo-count screen.': 'Ipinapakita sa idle home screen at screen ng pagpili ng dami ng litrato.',
  'Shown while nobody is using the booth. Customers tap anywhere to begin.': 'Ipinapakita kapag walang gumagamit ng booth. Pindutin kahit saan para magsimula.',
  'Some uploaded frames could not be loaded.':
      'May ilang na-upload na frame na hindi ma-load.',
  'Speak photo and ready prompts aloud.':
      'Bigkasin nang malakas ang mga prompt para sa litrato at paghahanda.',
  'Supports MP4, M4V, MOV, and WebM videos up to 100 MB. The video plays over the uploaded home image; the image remains as a fallback.': 'Tumatanggap ng MP4, M4V, MOV, at WebM na video hanggang 100 MB. Ipe-play ito sa ibabaw ng na-upload na home image; mananatili ang larawan bilang fallback.',
  'The update link is built into this app. Update the public manifest online when you release a new version.': 'Naka-built in sa app ang update link. I-update ang public manifest online kapag naglabas ng bagong bersyon.',
  'The update notice was hidden for now but may return after restart.': 'Itinago muna ang abiso ng update pero maaaring bumalik pagkatapos i-restart.',
  'Touch and drag a photo to reposition · use +/− to zoom': 'Pindutin at i-drag ang litrato para ilipat · gamitin ang +/− para mag-zoom',
  'Waiting for payment…': 'Naghihintay ng bayad…',
  'You can now take your photo.': 'Maaari ka nang kumuha ng litrato.',
  'Your photo is almost ready.': 'Malapit nang matapos ang iyong litrato.',
  'BACK': 'BUMALIK',
  'CANCEL': 'KANSELAHIN',
  'CHECK PAYMENT': 'SURIIN ANG BAYAD',
  'CLOSE': 'ISARA',
  'RETRY': 'SUBUKAN MULI',
  'QR PH': 'QR PH',
  'Bluetooth Low Energy': 'Bluetooth Low Energy',
  'Exit': 'Lumabas',
  'Tap anywhere to start': 'Pindutin kahit saan para magsimula',
  'A moment worth keeping.': 'Alaalang dapat ingatan.',
  'Your moment, beautifully captured.': 'Gandang alaala, kuhang-kuha.',
  'Gather your people. We will take care of the rest.':
      'Isama ang iyong mga mahal sa buhay. Kami na ang bahala.',
  'Get ready to make something worth keeping.':
      'Humanda sa paglikha ng alaalang iingatan.',
  'A few easy steps to your keepsake.':
      'Ilang madaling hakbang para sa iyong alaala.',
  'No experience needed': 'Hindi kailangan ng karanasan',
  'Your photo booth, made effortless.':
      'Mas pinadali ang paggamit ng photo booth.',
  'A few finishing touches': 'Ilang huling ayos',
  'Look at the camera': 'Tumingin sa kamera',
  'Photo': 'Litrato',
  'Smile!': 'Ngumiti!',
  'GET READY': 'MAGHANDA',
  'TAP TO TAKE YOUR PHOTO': 'PINDUTIN PARA KUHANAN ANG IYONG LITRATO',
  'Tap the shutter to take this photo.':
      'Pindutin ang shutter para kunan ang litrato.',
  'photos': 'litrato',
  'Ready': 'Handa na',
  'Please wait a moment.': 'Mangyaring maghintay sandali.',
  'Preparing your keepsake': 'Inihahanda ang iyong alaala',
  'We are preparing your print.': 'Inihahanda ang iyong ipa-print.',
  'PRINTING': 'NAGPI-PRINT',
  'Reset': 'I-reset',
  'Retake': 'Kuhanan muli',
  'Back to editing': 'Bumalik sa pag-edit',
  'SAVE PHOTO': 'I-SAVE ANG LITRATO',
  'SAVE MY PHOTO': 'I-SAVE ANG LITRATO KO',
  'USE THIS PHOTO': 'GAMITIN ANG LITRATONG ITO',
  'PREPARING PHOTO': 'INIAHANDA ANG LITRATO',
  'Print photo': 'I-print ang litrato',
  'Download photo QR': 'QR para i-download ang litrato',
  'Download GIF QR': 'QR para i-download ang GIF',
  'Start over': 'Magsimula muli',
  'Settings saved.': 'Na-save ang mga setting.',
  'Photobooth settings': 'Mga setting ng photobooth',
  'Create admin password': 'Gumawa ng password ng admin',
  'Admin login': 'Pag-login ng admin',
  'Exit admin settings': 'Lumabas sa mga setting ng admin',
  'General': 'Pangkalahatan',
  'Device & Fleet': 'Device at Fleet',
  'Payments': 'Mga Bayad',
  'Customer Experience': 'Karanasan ng Customer',
  'Photo Design': 'Disenyo ng Litrato',
  'Printer': 'Printer',
  'App Updates': 'Mga Update ng App',
  'Cancel': 'Kanselahin',
  'Continue': 'Magpatuloy',
  'Convert': 'I-convert',
  'Close': 'Isara',
  'Back': 'Bumalik',
  'Sign in': 'Mag-sign in',
  'Create password': 'Gumawa ng password',
  'Password': 'Password',
  'Confirm password': 'Kumpirmahin ang password',
  'New password (8+ characters)': 'Bagong password (8+ character)',
  'New activation code': 'Bagong activation code',
  'Activation code': 'Activation code',
  'Paste the full code exactly as provided.':
      'I-paste nang eksakto ang buong code na ibinigay.',
  'Camera': 'Kamera',
  'Coin-slot price per session (₱)':
      'Presyo bawat sesyon para sa hulog-barya (₱)',
  'Whole pesos, ₱1–₱100,000. The ESP32 must report the same number of credits (1 credit per ₱1).': 'Buong piso lamang, ₱1–₱100,000. Dapat tumugma ang bilang ng credit na ipinapadala ng ESP32 (1 credit bawat ₱1).',
  'PayMongo QR Ph amount (₱)': 'Halaga ng PayMongo QR Ph (₱)',
  'Whole pesos, ₱1–₱100,000. This is separate from the coin-slot price.':
      'Buong piso lamang, ₱1–₱100,000. Hiwalay ito sa presyo ng hulog-barya.',
  'Logo animation': 'Galaw ng logo',
  'Booth background design': 'Disenyo ng background ng booth',
  'Printer type': 'Uri ng printer',
  'Receipt paper width': 'Lapad ng papel ng resibo',
  'Automatic paper cut': 'Awtomatikong pagputol ng papel',
  'Make selected sticker smaller': 'Paliitin ang napiling sticker',
  'Make selected sticker larger': 'Palakihin ang napiling sticker',
  'Remove selected sticker': 'Alisin ang napiling sticker',
  'Zoom out': 'Mag-zoom out',
  'Zoom in': 'Mag-zoom in',
  'Copy address': 'Kopyahin ang address',
  'Language': 'Wika',
  'App language': 'Wika ng app',
  'Choose the language used throughout the app.':
      'Piliin ang wikang gagamitin sa buong app.',
  'English': 'English',
  'Tagalog': 'Tagalog',
  'Language updated.': 'Na-update ang wika.',
  'Could not save the language setting.': 'Hindi ma-save ang setting ng wika.',
  'Enable free test mode': 'Paganahin ang libreng test mode',
  'Enable rent mode': 'Paganahin ang rent mode',
  'Do not collect payment. The customer can start a session after choosing photos.': 'Huwag maningil. Maaaring magsimula ang customer pagkatapos pumili ng mga litrato.',
  'Allow Ganap QRPh payments': 'Payagan ang bayad gamit ang Ganap QRPh',
  'Enable Ganap QR Ph payments for this booth.':
      'Paganahin ang bayad gamit ang Ganap QR Ph para sa booth na ito.',
  'Customer welcome message': 'Mensahe ng pagbati sa customer',
  'Displayed on the customer screen': 'Ipapakita sa screen ng customer',
  'Countdown before each photo': 'Countdown bago ang bawat litrato',
  'Photo preview duration': 'Tagal ng preview ng litrato',
  'Return to attract screen after inactivity':
      'Bumalik sa attract screen kapag walang gumagamit',
  'Full classic session': 'Buong classic na sesyon',
  'Live camera preview effect': 'Epekto sa live preview ng kamera',
  'Voice guidance': 'Gabay na boses',
  'Photo border': 'Border ng litrato',
  'Add customer PNG frame': 'Magdagdag ng PNG frame para sa customer',
  'Loop idle video': 'Ulit-ulitin ang idle na video',
  'Select a printer': 'Pumili ng printer',
  'Print test page': 'Mag-print ng pahina para sa pagsubok',
  'Paired Bluetooth printer': 'Ipinaris na Bluetooth printer',
  'Print copies': 'Bilang ng kopya',
  '58 mm (384 dots)': '58 mm (384 tuldok)',
  '80 mm (576 dots)': '80 mm (576 tuldok)',
  'Full cut': 'Buong hiwa',
  'Partial cut': 'Bahagyang hiwa',
  'Back camera': 'Likurang kamera',
  'Front camera': 'Harapang kamera',
  'Use default': 'Gamitin ang default',
  'Remove video': 'Alisin ang video',
  'Operator setup & diagnostics': 'Setup at pagsusuri para sa operator',
  'Update activation features': 'I-update ang mga feature ng activation',
  'Check Fleet connection now': 'Suriin ang koneksyon sa Fleet',
  'Dashboard address copied.': 'Nakopya ang address ng dashboard.',
  'Downloading and verifying the update APK…':
      'Dina-download at sinusuri ang update APK…',
};

class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final material.TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: appLanguageNotifier,
    builder: (context, language, _) {
      final translatedText = translateAppText(data, language);
      final isHeading =
          style?.fontFamily == 'DancingScript' || (style?.fontSize ?? 0) >= 20;
      final resolvedStyle = isHeading
          ? (style ?? const material.TextStyle()).copyWith(
              fontFamily: 'DancingScript',
              fontWeight: material.FontWeight.w700,
            )
          : style;
      return material.Text(
        translatedText,
        style: resolvedStyle,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    },
  );
}
