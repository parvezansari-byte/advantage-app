// lib/models/crm_client.dart
//
// Data models for the CRM (client book), ported from the standalone
// advantage_crm app into the main Advantage app. Names are prefixed with
// Crm to avoid any clash with unrelated classes elsewhere in the app.

class CrmClient {
  final int? id;
  final String fullName;
  final String pan;
  final String? email;
  final String? phone;
  final String? dateOfBirth;
  final String? nseClientCode;
  final String kycStatus;
  final String? riskProfile;
  final String? notes;
  final String? createdAt;

  CrmClient({
    this.id,
    required this.fullName,
    required this.pan,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.nseClientCode,
    this.kycStatus = 'PENDING',
    this.riskProfile,
    this.notes,
    this.createdAt,
  });

  factory CrmClient.fromJson(Map<String, dynamic> j) => CrmClient(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}'),
        fullName: (j['full_name'] ?? '').toString(),
        pan: (j['pan'] ?? '').toString(),
        email: j['email']?.toString(),
        phone: j['phone']?.toString(),
        dateOfBirth: j['date_of_birth']?.toString(),
        nseClientCode: j['nse_client_code']?.toString(),
        kycStatus: (j['kyc_status'] ?? 'PENDING').toString(),
        riskProfile: j['risk_profile']?.toString(),
        notes: j['notes']?.toString(),
        createdAt: j['created_at']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'pan': pan,
        'email': email,
        'phone': phone,
        'date_of_birth': dateOfBirth,
        'nse_client_code': nseClientCode,
        'kyc_status': kycStatus,
        'risk_profile': riskProfile,
        'notes': notes,
      };

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class CrmInteraction {
  final int? id;
  final String note;
  final String? createdAt;

  CrmInteraction({this.id, required this.note, this.createdAt});

  factory CrmInteraction.fromJson(Map<String, dynamic> j) => CrmInteraction(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}'),
        note: (j['note'] ?? '').toString(),
        createdAt: j['created_at']?.toString(),
      );
}

class CrmHolding {
  final String schemeName;
  final String? folioNumber;
  final double units;
  final double nav;
  final double currentValue;
  final String? asOfDate;

  CrmHolding({
    required this.schemeName,
    this.folioNumber,
    required this.units,
    required this.nav,
    required this.currentValue,
    this.asOfDate,
  });

  factory CrmHolding.fromJson(Map<String, dynamic> j) => CrmHolding(
        schemeName: (j['scheme_name'] ?? '').toString(),
        folioNumber: j['folio_number']?.toString(),
        units: double.tryParse('${j['units'] ?? 0}') ?? 0,
        nav: double.tryParse('${j['nav'] ?? 0}') ?? 0,
        currentValue: double.tryParse('${j['current_value'] ?? 0}') ?? 0,
        asOfDate: j['as_of_date']?.toString(),
      );
}
