import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import '../services/fraud_engine.dart';
import '../widgets/result_card.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  String bank = 'cbe';
  final tx = TextEditingController(), amt = TextEditingController();
  final accountNumber = TextEditingController();
  final phoneNumber = TextEditingController();
  final qrData = TextEditingController();
  bool busy = false;
  Map<String, dynamic>? res;
  late Future<List<Map<String, dynamic>>> _banksFuture;

  @override
  void initState() {
    super.initState();
    _banksFuture = BackendApi.instance.chekiBanks();
  }

  @override
  void dispose() {
    tx.dispose();
    amt.dispose();
    accountNumber.dispose();
    phoneNumber.dispose();
    qrData.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _reloadBanks() {
    setState(() => _banksFuture = BackendApi.instance.chekiBanks());
  }

  Future<void> _openOfficialReceipt(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _snack('This receipt link looks unsafe, so it was not opened.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _snack('Could not open the receipt page.');
  }

  Future<void> _pick(ImageSource source) async {
    if (kIsWeb) {
      _snack('Receipt OCR is unavailable in the browser. Enter the details manually.');
      return;
    }
    final f = await ImagePicker().pickImage(
        source: source, imageQuality: 60, maxWidth: 1280);
    if (f == null) return;
    setState(() => busy = true);
    try {
      final inputImage = InputImage.fromFilePath(f.path);
      
      // 1. Scan for Barcodes / QR Codes
      final barcodeScanner = BarcodeScanner();
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();

      // 2. Scan for Text (OCR)
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      
      final p = FraudEngine.parseReceipt(recognizedText.text);

      setState(() {
        if (barcodes.isNotEmpty) {
          qrData.text = barcodes.first.displayValue ?? barcodes.first.rawValue ?? '';
          // If QR contains a link or ID, also put it in the TX field for convenience
          if (tx.text.isEmpty) tx.text = qrData.text;
        }
        if (p.txId != null) tx.text = p.txId!;
        if (p.amount != null) amt.text = p.amount!.toString();
      });

      if (barcodes.isEmpty && p.txId == null) {
        _snack('No QR code or receipt ID found. Please try a clearer photo.');
      }
    } catch (e) {
      _snack('Could not read the receipt. Enter the details manually.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan with Camera'),
              subtitle: const Text('Point at a QR code or paper receipt'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose Screenshot'),
              subtitle: const Text('Select from your gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _check() async {
    final amountText = amt.text.trim().replaceAll(',', '');
    final amount = amountText.isEmpty ? null : double.tryParse(amountText);
    if ((tx.text.trim().isEmpty && qrData.text.trim().isEmpty) ||
        (amountText.isNotEmpty && (amount == null || amount <= 0))) {
      _snack('Enter a receipt reference or QR data, and a valid optional amount.');
      return;
    }
    setState(() => busy = true);
    try {
      final result = await BackendApi.instance.verifyReceipt(
        bank: bank,
        reference: tx.text.trim(),
        amount: amount,
        accountNumber: (bank == 'boa' || bank == 'cbe')
            ? accountNumber.text.trim()
            : null,
        phoneNumber: bank == 'cbebirr' ? phoneNumber.text.trim() : null,
        qrData: qrData.text.trim(),
      );
      if (mounted) setState(() => res = result);
    } on ApiException catch (error) {
      _snack(error.message);
    } on FormatException {
      _snack('The server returned an invalid response.');
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = res;
    final verified = r?['verification_status'] == 'verified';
    final riskScore = r == null ? 0 : (r['risk_score'] as num).toInt();
    final verificationDetails =
        r?['verification_details'] as Map<String, dynamic>? ?? {};
    
    final (label, color) = r == null
        ? ('', Colors.grey)
        : (
            verified ? L.t('verified') : 'Unverified',
            verified ? Colors.green : Colors.red
          );
    final reasons = r == null
        ? <String>[]
        : (r['reasons'] as List<dynamic>)
            .map((item) => item.toString())
            .toList();
    for (final field in const [
      ('amount', 'Bank amount (ETB)'),
      ('senderName', 'Sender'),
      ('receiverName', 'Receiver'),
      ('date', 'Receipt date'),
      ('sourceUrl', 'Bank source'),
    ]) {
      final value = verificationDetails[field.$1];
      if (value != null && value.toString().isNotEmpty) {
        reasons.add('${field.$2}: $value');
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verify Payment Receipt',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan QR or enter receipt details to detect fraud.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: InkWell(
              onTap: busy ? null : _showPickerOptions,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.qr_code_scanner, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Scan QR or Receipt',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Point your camera at the QR code or receipt text', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
          
          if (busy)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
          
          const SizedBox(height: 24),
          Text(
            'Transaction Details',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _banksFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Could not load banks.', style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: _reloadBanks, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ],
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final banks = snapshot.data!.where((item) {
                final formats = item['formats'];
                return item['status'] == 'live' && formats is List && formats.isNotEmpty;
              }).toList();
              if (banks.isEmpty) return const Text('No banks supported.');
              if (!banks.any((item) => item['id'] == bank)) bank = banks.first['id'] as String;

              return DropdownButtonFormField<String>(
                initialValue: bank,
                decoration: const InputDecoration(labelText: 'Bank / Provider', prefixIcon: Icon(Icons.account_balance)),
                items: banks.map((item) => DropdownMenuItem(value: item['id'] as String, child: Text('${item['name']}'))).toList(),
                onChanged: (v) { if (v != null) setState(() => bank = v); },
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(controller: tx, decoration: const InputDecoration(labelText: 'Receipt ID / Link', prefixIcon: Icon(Icons.link))),
          const SizedBox(height: 16),
          if (qrData.text.isNotEmpty) ...[
            TextField(controller: qrData, decoration: const InputDecoration(labelText: 'Scanned QR Data', prefixIcon: Icon(Icons.qr_code))),
            const SizedBox(height: 16),
          ],
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (ETB)', prefixIcon: Icon(Icons.payments_outlined))),
          
          if (bank == 'boa' || bank == 'cbe' || bank == 'cbebirr') ...[
             const SizedBox(height: 16),
             if (bank == 'cbebirr')
              TextField(controller: phoneNumber, decoration: const InputDecoration(labelText: 'Payer Phone', prefixIcon: Icon(Icons.phone)))
             else
              TextField(controller: accountNumber, decoration: const InputDecoration(labelText: 'Partial Account No.', prefixIcon: Icon(Icons.numbers))),
          ],
          
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: busy ? null : _check, icon: const Icon(Icons.verified), label: Text(L.t('check').toUpperCase())),
          
          const SizedBox(height: 24),
          if (r != null) ...[
            ResultCard(
              title: '$label • ${r['risk_level']}'.toUpperCase(),
              color: color,
              score: riskScore,
              reasons: reasons,
              footer: verificationDetails['fallbackUrl'] is String ? 'Verification link available' : null,
            ),
            if (verificationDetails['fallbackUrl'] is String)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _openOfficialReceipt(verificationDetails['fallbackUrl'] as String),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View Official Receipt'),
                ),
              ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
