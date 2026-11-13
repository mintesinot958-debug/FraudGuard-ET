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
      _snack(L.t('unsafe_receipt_link'));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _snack(L.t('receipt_open_fail'));
  }

  Future<void> _pick(ImageSource source) async {
    if (kIsWeb) {
      _snack(L.t('ocr_unavailable_browser'));
      return;
    }
    final f = await ImagePicker()
        .pickImage(source: source, imageQuality: 60, maxWidth: 1280);
    if (f == null) return;
    setState(() => busy = true);
    try {
      final inputImage = InputImage.fromFilePath(f.path);

      // 1. Scan for Barcodes / QR Codes
      final barcodeScanner = BarcodeScanner();
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();

      // 2. Scan for Text (OCR)
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final p = FraudEngine.parseReceipt(recognizedText.text);

      setState(() {
        if (barcodes.isNotEmpty) {
          qrData.text =
              barcodes.first.displayValue ?? barcodes.first.rawValue ?? '';
          // If QR contains a link or ID, also put it in the TX field for convenience
          if (tx.text.isEmpty) tx.text = qrData.text;
        }
        if (p.txId != null) tx.text = p.txId!;
        if (p.amount != null) amt.text = p.amount!.toString();
      });

      if (barcodes.isEmpty && p.txId == null) {
        _snack(L.t('no_qr_receipt_id'));
      }
    } catch (e) {
      _snack(L.t('receipt_read_fail_manual'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(L.t('scan_with_camera')),
              subtitle: Text(L.t('point_qr_paper_receipt')),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(L.t('choose_screenshot')),
              subtitle: Text(L.t('select_gallery')),
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
      _snack(L.t('receipt_reference_validation'));
      return;
    }
    setState(() => busy = true);
    try {
      final result = await BackendApi.instance.verifyReceipt(
        bank: bank,
        reference: tx.text.trim(),
        amount: amount,
        accountNumber:
            (bank == 'boa' || bank == 'cbe') ? accountNumber.text.trim() : null,
        phoneNumber: bank == 'cbebirr' ? phoneNumber.text.trim() : null,
        qrData: qrData.text.trim(),
      );
      if (mounted) setState(() => res = result);
    } on ApiException catch (error) {
      _snack(error.message);
    } on FormatException {
      _snack(L.t('server_invalid_response'));
    } catch (_) {
      _snack(L.t('unexpected_error_retry'));
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
            verified ? L.t('verified') : L.t('unverified'),
            verified ? Colors.green : Colors.red
          );
    final reasons = r == null
        ? <String>[]
        : (r['reasons'] as List<dynamic>)
            .map((item) => L.reason(item.toString()))
            .toList();
    for (final field in const [
      ('amount', 'bank_amount'),
      ('senderName', 'sender'),
      ('receiverName', 'receiver'),
      ('date', 'receipt_date'),
      ('sourceUrl', 'bank_source'),
    ]) {
      final value = verificationDetails[field.$1];
      if (value != null && value.toString().isNotEmpty) {
        reasons.add('${L.t(field.$2)}: $value');
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            L.t('verify_payment_receipt'),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            L.t('verify_receipt_desc'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.wifi_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(L.t('receipt_verification_note')),
                  ),
                ],
              ),
            ),
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
                    Icon(Icons.qr_code_scanner,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      L.t('pick_image'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(L.t('point_camera_qr_receipt_text'),
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
          if (busy)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator()),
          const SizedBox(height: 24),
          Text(
            L.t('transaction_details'),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _banksFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L.t('bank_load_fail'),
                        style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: _reloadBanks,
                        icon: const Icon(Icons.refresh),
                        label: Text(L.t('retry'))),
                  ],
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final banks = snapshot.data!.where((item) {
                final formats = item['formats'];
                return item['status'] == 'live' &&
                    formats is List &&
                    formats.isNotEmpty;
              }).toList();
              if (banks.isEmpty) return Text(L.t('no_banks_supported'));
              if (!banks.any((item) => item['id'] == bank)) {
                bank = banks.first['id'] as String;
              }

              return DropdownButtonFormField<String>(
                initialValue: bank,
                decoration: InputDecoration(
                    labelText: L.t('bank_provider'),
                    prefixIcon: Icon(Icons.account_balance)),
                items: banks
                    .map((item) => DropdownMenuItem(
                        value: item['id'] as String,
                        child: Text('${item['name']}')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => bank = v);
                },
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
              controller: tx,
              decoration: InputDecoration(
                  labelText: L.t('receipt_id_link'),
                  prefixIcon: Icon(Icons.link))),
          const SizedBox(height: 16),
          if (qrData.text.isNotEmpty) ...[
            TextField(
                controller: qrData,
                decoration: InputDecoration(
                    labelText: L.t('scanned_qr_data'),
                    prefixIcon: Icon(Icons.qr_code))),
            const SizedBox(height: 16),
          ],
          TextField(
              controller: amt,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: '${L.t('amount')} (ETB)',
                  prefixIcon: Icon(Icons.payments_outlined))),
          if (bank == 'boa' || bank == 'cbe' || bank == 'cbebirr') ...[
            const SizedBox(height: 16),
            if (bank == 'cbebirr')
              TextField(
                  controller: phoneNumber,
                  decoration: InputDecoration(
                      labelText: L.t('payer_phone'),
                      prefixIcon: const Icon(Icons.phone)))
            else
              TextField(
                  controller: accountNumber,
                  decoration: InputDecoration(
                      labelText: L.t('partial_account_number'),
                      prefixIcon: Icon(Icons.numbers))),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
              onPressed: busy ? null : _check,
              icon: const Icon(Icons.verified),
              label: Text(L.t('check').toUpperCase())),
          const SizedBox(height: 24),
          if (r != null) ...[
            ResultCard(
              title: '$label • ${switch (r['risk_level']) {
                'low' => L.t('low'),
                'medium' => L.t('medium'),
                'high' => L.t('high'),
                _ => r['risk_level'],
              }}'
                  .toUpperCase(),
              color: color,
              score: riskScore,
              reasons: reasons,
              footer: verificationDetails['fallbackUrl'] is String
                  ? L.t('verification_link_available')
                  : null,
            ),
            if (verificationDetails['fallbackUrl'] is String)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _openOfficialReceipt(
                      verificationDetails['fallbackUrl'] as String),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(L.t('view_official_receipt')),
                ),
              ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
