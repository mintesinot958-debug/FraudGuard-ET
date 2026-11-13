import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PaymentSmsMessage {
  final String sender;
  final String body;
  final DateTime receivedAt;

  const PaymentSmsMessage({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });
}

class SmsMonitorService {
  SmsMonitorService._();

  static const _channel = MethodChannel('et.fraudguard/sms');

  static Future<bool> requestReadPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('requestReadPermission') ?? false;
  }

  static Future<List<PaymentSmsMessage>> readRecentMessages() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
          'SMS inbox scanning is available on Android only.');
    }

    final messages = await _channel.invokeListMethod<Object?>('readRecentSms');
    return (messages ?? []).map((item) {
      final message = Map<Object?, Object?>.from(item! as Map);
      final timestamp = (message['date']! as num).toInt();
      return PaymentSmsMessage(
        sender: message['sender'] as String? ?? '',
        body: message['body'] as String? ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }).toList();
  }
}
