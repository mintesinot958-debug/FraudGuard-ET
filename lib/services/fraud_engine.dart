import 'dart:math';

enum Verdict { verified, suspicious, likelyFake }
enum RiskLevel { low, medium, high }
enum Action { allow, stepUp, hold, block }
enum ScamLabel { safe, suspicious, scam }

class VerifyInput {
  final String provider, txId, sender, receiver;
  final double amount;
  final String? imageHash;
  VerifyInput({required this.provider, required this.txId, required this.amount,
      this.sender = '', this.receiver = '', this.imageHash});
}

class VerifyResult {
  final Verdict verdict;
  final int score;
  final List<String> reasons;
  VerifyResult(this.verdict, this.score, this.reasons);
}

class TxInput {
  final double amount;
  final int hour, accountAgeDays, txCount24h;
  final bool newRecipient, simChanged;
  TxInput({required this.amount, required this.hour, required this.accountAgeDays,
      required this.txCount24h, required this.newRecipient, required this.simChanged});
}

class TxResult {
  final int score;
  final RiskLevel level;
  final Action action;
  final List<String> rules;
  TxResult(this.score, this.level, this.action, this.rules);
}

class ScamResult {
  final int score;
  final ScamLabel label;
  final List<String> reasons;
  ScamResult(this.score, this.label, this.reasons);
}

class ParsedReceipt {
  final String? txId;
  final double? amount;
  final List<String> phones;
  ParsedReceipt(this.txId, this.amount, this.phones);
}

class _K {
  final int w;
  final String why;
  const _K(this.w, this.why);
}

class FraudEngine {
  // ASSUMED ID formats - replace with real provider formats.
  static const formats = {
    'Telebirr': r'^[A-Z0-9]{10}$',
    'CBE': r'^FT[A-Z0-9]{10}$',
    'M-Pesa': r'^[A-Z0-9]{10}$',
  };
  static final _phoneRe = RegExp(r'^(\+251|251|0)?[79]\d{8}$');

  // MOCK provider ledger. Swap with a real VerificationProvider API call later.
  static const Map<String, Map<String, double>> _ledger = {
    'Telebirr': {'CE12ABC3XY': 1500.0, 'DEMO000001': 2500.0},
    'CBE': {'FT24100ABCDE': 5000.0},
    'M-Pesa': {'QK12345678': 800.0},
  };
  static final Set<String> _seenTx = {};
  static final Set<String> _seenImg = {};

  static String maskPhone(String p) {
    final cleaned = p.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return '-';

    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return cleaned;

    if (cleaned.startsWith('+251')) {
      final local = digits.substring(3);
      if (local.length <= 4) return cleaned;
      return '+251${local.substring(0, 2)}****${local.substring(local.length - 2)}';
    }

    if (cleaned.startsWith('251')) {
      final local = digits.substring(3);
      if (local.length <= 4) return cleaned;
      return '251${local.substring(0, 2)}****${local.substring(local.length - 2)}';
    }

    if (cleaned.startsWith('0')) {
      final local = digits.substring(1);
      if (local.length <= 4) return cleaned;
      return '0${local.substring(0, 2)}****${local.substring(local.length - 2)}';
    }

    return '${digits.substring(0, 2)}****${digits.substring(digits.length - 2)}';
  }

  // ---------- Receipt OCR parsing ----------
  static ParsedReceipt parseReceipt(String text) {
    final up = text.toUpperCase();
    String? id;
    for (final m in RegExp(r'\b[A-Z0-9]{10,12}\b').allMatches(up)) {
      final s = m.group(0)!;
      if (RegExp(r'[A-Z]').hasMatch(s) && RegExp(r'\d').hasMatch(s)) {
        id = s;
        break;
      }
    }
    double? amt;
    final am = RegExp(
            r'(?:ETB|BIRR|ብር)\s*([\d,]+(?:\.\d+)?)|([\d,]+(?:\.\d+)?)\s*(?:ETB|BIRR|ብር)')
        .firstMatch(up);
    if (am != null) {
      amt = double.tryParse((am.group(1) ?? am.group(2))!.replaceAll(',', ''));
    }
    final phones =
        RegExp(r'(?:\+251|0)[79]\d{8}').allMatches(text).map((m) => m.group(0)!).toList();
    return ParsedReceipt(id, amt, phones);
  }

  // ---------- Module 1: receipt verification ----------
  static VerifyResult verifyReceipt(VerifyInput v) {
    int s = 0;
    final r = <String>[];
    final id = v.txId.trim().toUpperCase();
    final key = '${v.provider}:$id';

    if (!RegExp(formats[v.provider]!).hasMatch(id)) {
      s += 35;
      r.add('Transaction ID format does not match ${v.provider}.');
    }
    final rec = _ledger[v.provider]?[id];
    if (rec == null) {
      s += 40;
      r.add('Transaction not found at provider (mock lookup).');
    } else if ((rec - v.amount).abs() > 0.01) {
      s += 45;
      r.add('Amount differs from provider record (ETB ${rec.toStringAsFixed(2)}).');
    } else {
      r.add('Provider record matches ID and amount.');
    }
    if (_seenTx.contains(key)) {
      s += 50;
      r.add('This transaction ID was already used to claim a payment.');
    }
    if (v.imageHash != null && _seenImg.contains(v.imageHash)) {
      s += 30;
      r.add('Same receipt image was submitted before.');
    }
    for (final p in [v.sender, v.receiver]) {
      if (p.trim().isNotEmpty && !_phoneRe.hasMatch(p.replaceAll(' ', ''))) {
        s += 10;
        r.add('Phone number "${maskPhone(p)}" is not a valid Ethiopian mobile number.');
      }
    }
    if (v.amount <= 0) {
      s += 20;
      r.add('Amount must be positive.');
    }
    _seenTx.add(key);
    if (v.imageHash != null) _seenImg.add(v.imageHash!);

    s = min(s, 100);
    final verdict = s < 30 ? Verdict.verified : (s < 60 ? Verdict.suspicious : Verdict.likelyFake);
    return VerifyResult(verdict, s, r);
  }

  // ---------- Module 2: transaction risk scoring (rules) ----------
  static TxResult scoreTransaction(TxInput t) {
    int s = 0;
    final r = <String>[];
    void add(int p, String why) {
      s += p;
      r.add(why);
    }

    if (t.amount >= 50000) add(25, 'High amount (>= ETB 50,000)');
    if (t.accountAgeDays < 7 && t.amount >= 10000) add(25, 'New account with large transfer');
    if (t.hour < 5 || t.hour >= 23) add(10, 'Night-time activity');
    if (t.txCount24h >= 10) add(20, 'High velocity: 10+ transfers in 24h');
    if (t.amount >= 90000 && t.amount < 100000) add(15, 'Amount just under assumed limit (structuring)');
    if (t.simChanged && t.amount >= 5000) add(30, 'Recent SIM change + sizeable transfer (SIM-swap risk)');
    if (t.newRecipient && t.amount >= 20000) add(10, 'Large transfer to new recipient');

    s = min(s, 100);
    final level = s < 30 ? RiskLevel.low : (s < 60 ? RiskLevel.medium : RiskLevel.high);
    final action = s < 30
        ? Action.allow
        : s < 60
            ? Action.stepUp
            : s < 80
                ? Action.hold
                : Action.block;
    return TxResult(s, level, action, r);
  }

  // ---------- Module 3: scam message checker ----------
  static const Map<String, _K> _kw = {
    // English
    'you won': _K(25, 'Prize / lottery bait'),
    'congratulations': _K(15, 'Prize / lottery bait'),
    'prize': _K(20, 'Prize / lottery bait'),
    'lottery': _K(25, 'Prize / lottery bait'),
    'account blocked': _K(30, 'Threatens account suspension'),
    'has been suspended': _K(30, 'Threatens account suspension'),
    'verify your account': _K(30, 'Asks you to verify your account'),
    'otp': _K(30, 'Asks for OTP / PIN / password'),
    'your pin': _K(30, 'Asks for OTP / PIN / password'),
    'password': _K(30, 'Asks for OTP / PIN / password'),
    'urgent': _K(15, 'Creates false urgency'),
    'send back': _K(30, 'Wrong-transfer reversal scam'),
    'wrong number': _K(25, 'Wrong-transfer reversal scam'),
    'by mistake': _K(20, 'Wrong-transfer reversal scam'),
    'bit.ly': _K(20, 'Shortened link'),
    // Amharic
    'አሸንፈዋል': _K(25, 'Prize / lottery bait'),
    'ሽልማት': _K(20, 'Prize / lottery bait'),
    'ሎተሪ': _K(25, 'Prize / lottery bait'),
    'አካውንትዎ ታግዷል': _K(30, 'Threatens account suspension'),
    'ፒን': _K(30, 'Asks for OTP / PIN / password'),
    'ኦቲፒ': _K(30, 'Asks for OTP / PIN / password'),
    'የይለፍ ቃል': _K(30, 'Asks for OTP / PIN / password'),
    'በአስቸኳይ': _K(15, 'Creates false urgency'),
    'ገንዘብ መልሱ': _K(30, 'Wrong-transfer reversal scam'),
    'በስህተት': _K(20, 'Wrong-transfer reversal scam'),
    // Afan Oromo
    'injifatteetta': _K(25, 'Prize / lottery bait'),
    'badhaasa': _K(20, 'Prize / lottery bait'),
    'cufameera': _K(30, 'Threatens account suspension'),
    'ariifachiisaa': _K(15, 'Creates false urgency'),
    'icciitii': _K(30, 'Asks for OTP / PIN / password'),
    'maallaqa deebisi': _K(30, 'Wrong-transfer reversal scam'),
    // Tigrinya
    'ሕሳብካ ተዓጽዩ': _K(30, 'Threatens account suspension'),
    'ቀልጢፍካ': _K(15, 'Creates false urgency'),
    'ሚስጥራዊ ቁጽሪ': _K(30, 'Asks for OTP / PIN / password'),
  };

  static ScamResult checkMessage(String text) {
    final low = text.toLowerCase();
    int s = 0;
    final why = <String>{};
    _kw.forEach((k, v) {
      if (low.contains(k)) {
        s += v.w;
        why.add(v.why);
      }
    });
    if (RegExp(r'https?://|www\.').hasMatch(low)) {
      s += 15;
      why.add('Contains a link');
    }
    s = min(s, 100);
    final label = s < 25 ? ScamLabel.safe : (s < 55 ? ScamLabel.suspicious : ScamLabel.scam);
    return ScamResult(s, label, why.toList());
  }
}
