import 'package:flutter/foundation.dart';

@immutable
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.label,
    this.iconKey = 'spark',
  });

  final String id;
  final String label;
  final String iconKey;

  ChecklistItem copyWith({String? id, String? label, String? iconKey}) =>
      ChecklistItem(
        id: id ?? this.id,
        label: label ?? this.label,
        iconKey: iconKey ?? this.iconKey,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'iconKey': iconKey,
  };

  factory ChecklistItem.fromJson(Map<String, Object?> json) => ChecklistItem(
    id: _requiredString(json, 'id'),
    label: _requiredString(json, 'label'),
    iconKey: _stringOr(json['iconKey'], 'spark'),
  );
}

@immutable
class Blueprint {
  Blueprint({
    required this.id,
    required this.name,
    this.iconKey = 'bag',
    this.colorIndex = 0,
    Iterable<ChecklistItem> items = const [],
  }) : items = List.unmodifiable(items);

  final String id;
  final String name;
  final String iconKey;
  final int colorIndex;
  final List<ChecklistItem> items;

  Blueprint copyWith({
    String? id,
    String? name,
    String? iconKey,
    int? colorIndex,
    Iterable<ChecklistItem>? items,
  }) => Blueprint(
    id: id ?? this.id,
    name: name ?? this.name,
    iconKey: iconKey ?? this.iconKey,
    colorIndex: colorIndex ?? this.colorIndex,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'iconKey': iconKey,
    'colorIndex': colorIndex,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory Blueprint.fromJson(Map<String, Object?> json) => Blueprint(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    iconKey: _stringOr(json['iconKey'], 'bag'),
    colorIndex: _intOr(json['colorIndex'], 0),
    items: _objectList(
      json['items'],
      'blueprint.items',
    ).map(ChecklistItem.fromJson),
  );
}

@immutable
class DatedExtra {
  const DatedExtra({
    required this.id,
    required this.blueprintId,
    required this.date,
    required this.label,
    this.iconKey = 'spark',
  });

  final String id;
  final String blueprintId;
  final String date;
  final String label;
  final String iconKey;

  Map<String, Object?> toJson() => {
    'id': id,
    'blueprintId': blueprintId,
    'date': date,
    'label': label,
    'iconKey': iconKey,
  };

  factory DatedExtra.fromJson(Map<String, Object?> json) => DatedExtra(
    id: _requiredString(json, 'id'),
    blueprintId: _requiredString(json, 'blueprintId'),
    date: requireCalendarDate(_requiredString(json, 'date')),
    label: _requiredString(json, 'label'),
    iconKey: _stringOr(json['iconKey'], 'spark'),
  );
}

@immutable
class OutingItem {
  const OutingItem({
    required this.id,
    required this.label,
    this.iconKey = 'spark',
    this.checked = false,
  });

  final String id;
  final String label;
  final String iconKey;
  final bool checked;

  OutingItem copyWith({
    String? id,
    String? label,
    String? iconKey,
    bool? checked,
  }) => OutingItem(
    id: id ?? this.id,
    label: label ?? this.label,
    iconKey: iconKey ?? this.iconKey,
    checked: checked ?? this.checked,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'iconKey': iconKey,
    'checked': checked,
  };

  factory OutingItem.fromJson(Map<String, Object?> json) => OutingItem(
    id: _requiredString(json, 'id'),
    label: _requiredString(json, 'label'),
    iconKey: _stringOr(json['iconKey'], 'spark'),
    checked: _boolOr(json['checked'], false),
  );
}

/// An explicit Flutter checklist check/uncheck intent sent with a storage
/// transaction. This distinguishes a deliberate set-to-the-current-value from
/// an untouched item when a native widget has changed the persisted check.
@immutable
class OutingCheckIntent {
  const OutingCheckIntent({
    required this.outingId,
    required this.itemId,
    required this.checked,
  });

  final String outingId;
  final String itemId;
  final bool checked;

  Map<String, Object?> toJson() => {
    'outingId': outingId,
    'itemId': itemId,
    'checked': checked,
  };
}

/// A Dart-owned outing lifecycle intent. Native widget edits may only change
/// checked flags; this payload lets storage preserve finish/dismiss/restore
/// changes that have not yet been acknowledged by Flutter.
@immutable
class OutingLifecycleIntent {
  const OutingLifecycleIntent({
    required this.outingId,
    required this.completedAt,
    required this.dismissedAtUTC,
  });

  final String outingId;
  final DateTime? completedAt;
  final DateTime? dismissedAtUTC;

  Map<String, Object?> toJson() => {
    'outingId': outingId,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'dismissedAtUTC': dismissedAtUTC?.toUtc().toIso8601String(),
  };
}

@immutable
class Outing {
  Outing({
    required this.id,
    required this.blueprintId,
    required this.blueprintName,
    required String date,
    required this.startedAt,
    required Iterable<OutingItem> items,
    this.completedAt,
    DateTime? dismissedAtUTC,
  }) : date = requireCalendarDate(date),
       dismissedAtUTC = dismissedAtUTC?.toUtc(),
       items = List.unmodifiable(items);

  final String id;
  final String blueprintId;
  final String blueprintName;
  final String date;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// UTC instant when this unfinished session was dismissed from active lists.
  /// Completed sessions remain in history and are never dismissed.
  final DateTime? dismissedAtUTC;
  final List<OutingItem> items;

  bool get isComplete => completedAt != null;
  bool get isDismissed => !isComplete && dismissedAtUTC != null;
  bool get isActive => !isComplete && !isDismissed;
  int get checkedCount => items.where((item) => item.checked).length;
  bool get canFinish => items.isNotEmpty && checkedCount == items.length;

  Outing copyWith({
    String? id,
    String? blueprintId,
    String? blueprintName,
    String? date,
    DateTime? startedAt,
    Object? completedAt = _unchanged,
    Object? dismissedAtUTC = _unchanged,
    Iterable<OutingItem>? items,
  }) => Outing(
    id: id ?? this.id,
    blueprintId: blueprintId ?? this.blueprintId,
    blueprintName: blueprintName ?? this.blueprintName,
    date: date ?? this.date,
    startedAt: startedAt ?? this.startedAt,
    completedAt: identical(completedAt, _unchanged)
        ? this.completedAt
        : completedAt as DateTime?,
    dismissedAtUTC: identical(dismissedAtUTC, _unchanged)
        ? this.dismissedAtUTC
        : dismissedAtUTC as DateTime?,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'blueprintId': blueprintId,
    'blueprintName': blueprintName,
    'date': date,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'dismissedAtUTC': dismissedAtUTC?.toUtc().toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory Outing.fromJson(Map<String, Object?> json) {
    // Legacy no-zone values remain parseable, but their original timezone
    // cannot be inferred after the device timezone changes.
    final startedAt = DateTime.tryParse(_requiredString(json, 'startedAt'));
    final rawCompleted = json['completedAt'];
    final completedAt = rawCompleted == null
        ? null
        : DateTime.tryParse(_stringOr(rawCompleted, ''));
    final rawDismissed = json['dismissedAtUTC'];
    final dismissedAtUTC = rawDismissed == null
        ? null
        : DateTime.tryParse(_stringOr(rawDismissed, ''));
    if (startedAt == null ||
        (rawCompleted != null && completedAt == null) ||
        (rawDismissed != null && dismissedAtUTC == null)) {
      throw const FormatException('Invalid outing timestamp');
    }
    return Outing(
      id: _requiredString(json, 'id'),
      blueprintId: _requiredString(json, 'blueprintId'),
      blueprintName: _requiredString(json, 'blueprintName'),
      date: requireCalendarDate(_requiredString(json, 'date')),
      startedAt: startedAt,
      completedAt: completedAt,
      dismissedAtUTC: dismissedAtUTC,
      items: _objectList(
        json['items'],
        'outing.items',
      ).map(OutingItem.fromJson),
    );
  }
}

@immutable
class AppSettings {
  const AppSettings({
    this.appearance = 'system',
    this.accent = 'lime',
    this.haptics = true,
    this.reducedMotion = false,
    this.onboarded = false,
    this.reminderEnabled = false,
    this.reminderHour = 18,
    this.reminderMinute = 0,
  });

  final String appearance;
  final String accent;
  final bool haptics;
  final bool reducedMotion;
  final bool onboarded;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;

  AppSettings copyWith({
    String? appearance,
    String? accent,
    bool? haptics,
    bool? reducedMotion,
    bool? onboarded,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    accent: accent ?? this.accent,
    haptics: haptics ?? this.haptics,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    onboarded: onboarded ?? this.onboarded,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
  );

  Map<String, Object?> toJson() => {
    'appearance': appearance,
    'accent': accent,
    'haptics': haptics,
    'reducedMotion': reducedMotion,
    'onboarded': onboarded,
    'reminderEnabled': reminderEnabled,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final hour = _intOr(json['reminderHour'], 18);
    final minute = _intOr(json['reminderMinute'], 0);
    return AppSettings(
      appearance: const {'system', 'light', 'dark'}.contains(json['appearance'])
          ? json['appearance']! as String
          : 'system',
      accent: const {'lime', 'sky', 'lilac'}.contains(json['accent'])
          ? json['accent']! as String
          : 'lime',
      haptics: _boolOr(json['haptics'], true),
      reducedMotion: _boolOr(json['reducedMotion'], false),
      onboarded: _boolOr(json['onboarded'], false),
      reminderEnabled: _boolOr(json['reminderEnabled'], false),
      reminderHour: hour >= 0 && hour <= 23 ? hour : 18,
      reminderMinute: minute >= 0 && minute <= 59 ? minute : 0,
    );
  }
}

@immutable
class AppState {
  AppState({
    Iterable<Blueprint> blueprints = const [],
    Iterable<DatedExtra> extras = const [],
    Iterable<Outing> outings = const [],
    Map<String, String> widgetLaunchRequests = const {},
    this.settings = const AppSettings(),
  }) : blueprints = List.unmodifiable(blueprints),
       extras = List.unmodifiable(extras),
       outings = List.unmodifiable(outings),
       widgetLaunchRequests = Map.unmodifiable(widgetLaunchRequests);

  final List<Blueprint> blueprints;
  final List<DatedExtra> extras;
  final List<Outing> outings;
  final Map<String, String> widgetLaunchRequests;
  final AppSettings settings;

  AppState copyWith({
    Iterable<Blueprint>? blueprints,
    Iterable<DatedExtra>? extras,
    Iterable<Outing>? outings,
    Map<String, String>? widgetLaunchRequests,
    AppSettings? settings,
  }) => AppState(
    blueprints: blueprints ?? this.blueprints,
    extras: extras ?? this.extras,
    outings: outings ?? this.outings,
    widgetLaunchRequests: widgetLaunchRequests ?? this.widgetLaunchRequests,
    settings: settings ?? this.settings,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'blueprints': blueprints.map((item) => item.toJson()).toList(),
    'extras': extras.map((item) => item.toJson()).toList(),
    'outings': outings.map((item) => item.toJson()).toList(),
    'widgetLaunchRequests': widgetLaunchRequests,
    'settings': settings.toJson(),
  };

  factory AppState.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported saved state version');
    }
    final rawSettings = json['settings'];
    if (rawSettings != null && rawSettings is! Map) {
      throw const FormatException('Invalid saved settings');
    }
    final rawWidgetLaunchRequests = json['widgetLaunchRequests'];
    if (rawWidgetLaunchRequests != null && rawWidgetLaunchRequests is! Map) {
      throw const FormatException('Invalid saved widget launch requests');
    }
    final widgetLaunchRequests = <String, String>{};
    if (rawWidgetLaunchRequests is Map) {
      for (final entry in rawWidgetLaunchRequests.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Invalid saved widget launch request');
        }
        widgetLaunchRequests[entry.key as String] = entry.value as String;
      }
    }
    return AppState(
      blueprints: _objectList(
        json['blueprints'],
        'blueprints',
      ).map(Blueprint.fromJson),
      extras: _objectList(json['extras'], 'extras').map(DatedExtra.fromJson),
      outings: _objectList(json['outings'], 'outings').map(Outing.fromJson),
      widgetLaunchRequests: widgetLaunchRequests,
      settings: AppSettings.fromJson(
        rawSettings == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(rawSettings as Map),
      ),
    );
  }

  Map<String, Object?> get widgetSummary {
    final active = outings.where((outing) => outing.isActive).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (active.isEmpty) {
      final latest = outings.where((outing) => !outing.isDismissed).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final completed = latest.isEmpty ? null : latest.first;
      return {
        'title': completed?.blueprintName,
        'checked': completed?.checkedCount ?? 0,
        'total': completed?.items.length ?? 0,
        'completed': completed?.isComplete ?? false,
      };
    }
    final outing = active.first;
    return {
      'title': outing.blueprintName,
      'checked': outing.checkedCount,
      'total': outing.items.length,
      'completed': false,
    };
  }

  factory AppState.initial() => AppState(
    blueprints: [
      Blueprint(
        id: 'school',
        name: 'School',
        iconKey: 'book',
        colorIndex: 0,
        items: const [
          ChecklistItem(id: 'school-bag', label: 'Bag', iconKey: 'bag'),
          ChecklistItem(id: 'school-book', label: 'Book', iconKey: 'book'),
          ChecklistItem(
            id: 'school-notebook',
            label: 'Notebook',
            iconKey: 'notebook',
          ),
          ChecklistItem(id: 'school-pen', label: 'Pen', iconKey: 'pen'),
          ChecklistItem(
            id: 'school-water',
            label: 'Water bottle',
            iconKey: 'water',
          ),
          ChecklistItem(id: 'school-keys', label: 'Keys', iconKey: 'keys'),
        ],
      ),
      Blueprint(
        id: 'work',
        name: 'Work',
        iconKey: 'briefcase',
        colorIndex: 1,
        items: const [
          ChecklistItem(id: 'work-laptop', label: 'Laptop', iconKey: 'laptop'),
          ChecklistItem(
            id: 'work-charger',
            label: 'Charger',
            iconKey: 'charger',
          ),
          ChecklistItem(id: 'work-badge', label: 'Badge', iconKey: 'badge'),
          ChecklistItem(id: 'work-phone', label: 'Phone', iconKey: 'phone'),
          ChecklistItem(id: 'work-wallet', label: 'Wallet', iconKey: 'wallet'),
          ChecklistItem(id: 'work-keys', label: 'Keys', iconKey: 'keys'),
        ],
      ),
      Blueprint(
        id: 'gym',
        name: 'Gym',
        iconKey: 'dumbbell',
        colorIndex: 2,
        items: const [
          ChecklistItem(
            id: 'gym-shoes',
            label: 'Training shoes',
            iconKey: 'shoes',
          ),
          ChecklistItem(
            id: 'gym-water',
            label: 'Water bottle',
            iconKey: 'water',
          ),
          ChecklistItem(id: 'gym-towel', label: 'Towel', iconKey: 'towel'),
          ChecklistItem(
            id: 'gym-clothes',
            label: 'Change of clothes',
            iconKey: 'clothes',
          ),
          ChecklistItem(
            id: 'gym-headphones',
            label: 'Headphones',
            iconKey: 'headphones',
          ),
        ],
      ),
      Blueprint(
        id: 'trip',
        name: 'Trip',
        iconKey: 'suitcase',
        colorIndex: 3,
        items: const [
          ChecklistItem(id: 'trip-wallet', label: 'Wallet', iconKey: 'wallet'),
          ChecklistItem(id: 'trip-phone', label: 'Phone', iconKey: 'phone'),
          ChecklistItem(
            id: 'trip-charger',
            label: 'Charger',
            iconKey: 'charger',
          ),
          ChecklistItem(id: 'trip-ticket', label: 'Ticket', iconKey: 'ticket'),
          ChecklistItem(
            id: 'trip-passport',
            label: 'Passport',
            iconKey: 'passport',
          ),
          ChecklistItem(
            id: 'trip-medicine',
            label: 'Medicine',
            iconKey: 'medicine',
          ),
        ],
      ),
    ],
  );
}

const Object _unchanged = Object();

String requireCalendarDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw ArgumentError.value(value, 'date', 'Expected YYYY-MM-DD');
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw ArgumentError.value(value, 'date', 'Invalid calendar date');
  }
  return value;
}

String localDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key"');
  }
  return value;
}

String _stringOr(Object? value, String fallback) =>
    value is String ? value : fallback;

int _intOr(Object? value, int fallback) => value is int ? value : fallback;

bool _boolOr(Object? value, bool fallback) => value is bool ? value : fallback;

List<Map<String, Object?>> _objectList(Object? value, String field) {
  if (value is! List) throw FormatException('Invalid "$field" list');
  return value.map((entry) {
    if (entry is! Map) throw FormatException('Invalid entry in "$field"');
    return Map<String, Object?>.from(entry);
  }).toList();
}
