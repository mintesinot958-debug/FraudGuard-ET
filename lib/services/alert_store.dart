import 'package:flutter/foundation.dart';

class AlertItem {
  final String type, desc;
  final int score;
  String status;
  final DateTime time;
  AlertItem(this.type, this.desc, this.score, this.status, this.time);
}

/// In-memory alert queue (replace with API/DB later).
class AlertStore extends ChangeNotifier {
  static final AlertStore i = AlertStore._();
  AlertStore._();

  static const statuses = ['Open', 'Investigating', 'Confirmed Fraud', 'False Positive'];

  final List<AlertItem> items = [
    AlertItem('Fake receipt', 'Telebirr +25191****67', 82, 'Open', DateTime.now()),
    AlertItem('Scam SMS', 'Prize / lottery bait', 71, 'Investigating', DateTime.now()),
    AlertItem('Risky transfer', 'New account, ETB 95,000, 02:00', 64, 'Open', DateTime.now()),
    AlertItem('Fake receipt', 'CBE +25192****10', 55, 'Confirmed Fraud', DateTime.now()),
    AlertItem('Scam SMS', 'Asks for OTP', 60, 'Open', DateTime.now()),
    AlertItem('Risky transfer', 'SIM change + ETB 30,000', 77, 'Open', DateTime.now()),
  ];

  void addIfRisky(String type, String desc, int score) {
    if (score < 30) return;
    items.insert(0, AlertItem(type, desc, score, 'Open', DateTime.now()));
    notifyListeners();
  }

  void setStatus(AlertItem a, String s) {
    a.status = s; // analyst label -> would feed the retraining feedback table
    notifyListeners();
  }
}
