import 'package:eth_fraud_guard/services/fraud_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scam message checker', () {
    test('prize + PIN + short link is flagged as scam', () {
      final r = FraudEngine.checkMessage(
          'Congratulations! You won a prize. Send your PIN at http://bit.ly/x');
      expect(r.label, ScamLabel.scam);
      expect(r.reasons, isNotEmpty);
    });

    test('Amharic lottery + PIN message is flagged', () {
      final r = FraudEngine.checkMessage('ሎተሪ አሸንፈዋል ፒን ያስገቡ');
      expect(r.label, ScamLabel.scam);
    });

    test('ordinary message is safe', () {
      final r = FraudEngine.checkMessage('See you at lunch tomorrow');
      expect(r.label, ScamLabel.safe);
      expect(r.score, 0);
    });
  });

  group('receipt OCR parsing', () {
    test('extracts id, amount and phone', () {
      final p = FraudEngine.parseReceipt(
          'Telebirr receipt CE12ABC3XY amount ETB 1,500.00 to 0911234567');
      expect(p.txId, 'CE12ABC3XY');
      expect(p.amount, 1500.0);
      expect(p.phones, ['0911234567']);
    });
  });

  group('phone masking', () {
    test('hides the middle digits', () {
      expect(FraudEngine.maskPhone('+251911234567'), '+25191****67');
    });
  });

  group('transfer rules', () {
    test('new account + SIM change + big night transfer is blocked', () {
      final r = FraudEngine.scoreTransaction(TxInput(
        amount: 95000,
        hour: 2,
        accountAgeDays: 3,
        txCount24h: 1,
        newRecipient: false,
        simChanged: true,
      ));
      expect(r.level, RiskLevel.high);
      expect(r.action, Action.block);
    });

    test('small daytime transfer is allowed', () {
      final r = FraudEngine.scoreTransaction(TxInput(
        amount: 500,
        hour: 14,
        accountAgeDays: 400,
        txCount24h: 1,
        newRecipient: false,
        simChanged: false,
      ));
      expect(r.action, Action.allow);
    });
  });
}
