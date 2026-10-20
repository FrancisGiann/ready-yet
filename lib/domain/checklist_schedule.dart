/// A recurring departure in the device's local timezone. No location is used.
class ChecklistSchedule {
  ChecklistSchedule({
    required this.id,
    required this.blueprintId,
    required Iterable<int> weekdays,
    required this.departureMinute,
    this.leadMinutes = 15,
    this.enabled = true,
  }) : weekdays = List.unmodifiable(weekdays.toSet().toList()..sort()) {
    if (id.trim().isEmpty ||
        blueprintId.trim().isEmpty ||
        this.weekdays.isEmpty ||
        this.weekdays.any((day) => day < 1 || day > 7) ||
        departureMinute < 0 ||
        departureMinute >= 1440 ||
        leadMinutes < 0 ||
        leadMinutes > 1440) {
      throw const FormatException('Invalid checklist schedule');
    }
  }

  final String id;
  final String blueprintId;

  /// ISO weekdays: Monday = 1, Sunday = 7.
  final List<int> weekdays;
  final int departureMinute;
  final int leadMinutes;
  final bool enabled;

  bool runsOn(DateTime date) => enabled && weekdays.contains(date.weekday);
  String occurrenceId(String date) => 'scheduled:$id:$date';
  DateTime departureOn(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
    departureMinute ~/ 60,
    departureMinute % 60,
  );

  ChecklistSchedule copyWith({
    String? blueprintId,
    Iterable<int>? weekdays,
    int? departureMinute,
    int? leadMinutes,
    bool? enabled,
  }) => ChecklistSchedule(
    id: id,
    blueprintId: blueprintId ?? this.blueprintId,
    weekdays: weekdays ?? this.weekdays,
    departureMinute: departureMinute ?? this.departureMinute,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'blueprintId': blueprintId,
    'weekdays': weekdays,
    'departureMinute': departureMinute,
    'leadMinutes': leadMinutes,
    'enabled': enabled,
  };

  factory ChecklistSchedule.fromJson(Map<String, Object?> value) {
    if (value['id'] is! String ||
        value['blueprintId'] is! String ||
        value['weekdays'] is! List ||
        value['departureMinute'] is! int ||
        value['leadMinutes'] is! int ||
        value['enabled'] is! bool) {
      throw const FormatException('Invalid saved schedule');
    }
    final days = value['weekdays']! as List;
    if (days.any((day) => day is! int)) {
      throw const FormatException('Invalid saved weekdays');
    }
    return ChecklistSchedule(
      id: value['id']! as String,
      blueprintId: value['blueprintId']! as String,
      weekdays: days.cast<int>(),
      departureMinute: value['departureMinute']! as int,
      leadMinutes: value['leadMinutes']! as int,
      enabled: value['enabled']! as bool,
    );
  }
}
