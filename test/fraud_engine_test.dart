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

    group('payment SMS analysis', () {
      test('flags a payment claim that asks for money back', () {
        final result = FraudEngine.analyzePaymentSms(
          'Payment received ETB 1,000. Wrong transfer, send the money back.',
        );

        expect(result.isPaymentRelated, isTrue);
        expect(result.label, ScamLabel.scam);
        expect(
          result.reasons,
          contains('Requests money back after claiming a payment was sent.'),
        );
      });

      test(
          'recognizes a normal bank payment notice without declaring it verified',
          () {
        final result = FraudEngine.analyzePaymentSms(
          'You have received ETB 500.00 in your CBE account.',
        );

        expect(result.isPaymentRelated, isTrue);
        expect(result.label, ScamLabel.safe);
        expect(result.reasons.single, contains('verify the payment'));
      });

      test('ignores unrelated inbox messages', () {
        final result =
            FraudEngine.analyzePaymentSms('See you at lunch tomorrow.');

        expect(result.isPaymentRelated, isFalse);
        expect(result.score, 0);
      });
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
