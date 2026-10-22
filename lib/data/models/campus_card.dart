/// 校方门户返回的校园卡资料。状态与有效期保留学校原文。
class CampusCardInfo {
  const CampusCardInfo({
    required this.studentId,
    required this.name,
    required this.status,
    required this.balance,
    required this.validUntil,
  });

  factory CampusCardInfo.fromJson(Map<String, dynamic> json) => CampusCardInfo(
        studentId: _requiredText(json['PersonNumber']),
        name: _text(json['PersonName']),
        status: _text(json['CardStatus']),
        balance: _decimal(json['ZhangHYE']),
        validUntil: _text(json['YouXQ']),
      );

  final String studentId;
  final String name;
  final String status;
  final double balance;
  final String validUntil;
}

/// 金额保持接口原始符号；门户没有提供可靠的收支方向枚举。
class CampusCardBill {
  const CampusCardBill({
    required this.name,
    required this.payTime,
    required this.amount,
  });

  factory CampusCardBill.fromJson(Map<String, dynamic> json) => CampusCardBill(
        name: _requiredText(json['billname']),
        payTime: _requiredText(json['paytime']),
        amount: _decimal(json['amount']),
      );

  final String name;
  final String payTime;
  final double amount;
}

String _text(Object? value) {
  if (value == null) return '';
  if (value is! String && value is! num) {
    throw const FormatException('校园卡字段格式异常');
  }
  return value.toString().trim();
}

String _requiredText(Object? value) {
  final text = _text(value);
  if (text.isEmpty) throw const FormatException('校园卡字段缺失');
  return text;
}

double _decimal(Object? value) {
  final decimal = double.tryParse(_requiredText(value));
  if (decimal == null || !decimal.isFinite) {
    throw const FormatException('校园卡金额格式异常');
  }
  return decimal;
}
