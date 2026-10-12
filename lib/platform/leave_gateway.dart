import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models.dart';

/// Boundary for private state storage and the small set of Android features.
///
/// State writes are transactions: the host merges explicit Flutter check and
/// lifecycle intents into the latest native snapshot and returns that
/// canonical snapshot. Widget changes can therefore race a running Flutter
/// process without either side blindly replacing the other's work.
abstract interface class LeaveGateway {
  Future<String?> readState();

  Future<String?> getLaunchAction();

  void setLaunchActionHandler(void Function(String action)? handler);

  void setExternalStateChangedHandler(void Function(String json)? handler);

  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  });

  /// Replaces unreadable state after an explicit user reset, preserving
  /// damaged platform state in a recoverable copy.
  Future<String> resetState({
    required String targetJson,
    Map<String, Object?>? widgetSummary,
  });

  Future<Map<String, Object?>> widgetSnapshot({
    required int? widgetId,
    required String kind,
  });

  Future<bool> requestPinWidget({required String kind});

  Future<Map<String, Object?>> reminderStatus();

  Future<Map<String, Object?>> scheduleReminder({
    required int hour,
    required int minute,
    required bool enabled,
  });

  Future<bool> requestNotifications();
}

/// Android platform implementation. The channel is intentionally the only
/// native boundary used by the domain controller.
class MethodChannelLeaveGateway implements LeaveGateway {
  MethodChannelLeaveGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const channelName = 'dev.giann.before_i_leave/native';
  final MethodChannel _channel;
  void Function(String action)? _launchActionHandler;
  void Function(String json)? _externalStateChangedHandler;
  String? _queuedLaunchAction;
  String? _queuedExternalState;

  @override
  Future<String?> readState() => _channel.invokeMethod<String?>('readState');

  @override
  Future<String?> getLaunchAction() =>
      _channel.invokeMethod<String?>('getLaunchAction');

  @override
  void setLaunchActionHandler(void Function(String action)? handler) {
    _launchActionHandler = handler;
    final queued = _queuedLaunchAction;
    if (handler != null && queued != null) {
      _queuedLaunchAction = null;
      handler(queued);
    }
  }

  @override
  void setExternalStateChangedHandler(void Function(String json)? handler) {
    _externalStateChangedHandler = handler;
    final queued = _queuedExternalState;
    if (handler != null && queued != null) {
      _queuedExternalState = null;
      handler(queued);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'launchAction' && call.arguments is String) {
      final action = call.arguments as String;
      final handler = _launchActionHandler;
      if (handler == null) {
        _queuedLaunchAction = action;
      } else {
        handler(action);
      }
      return;
    }
    if (call.method == 'externalStateChanged' && call.arguments is String) {
      final json = call.arguments as String;
      final handler = _externalStateChangedHandler;
      if (handler == null) {
        _queuedExternalState = json;
      } else {
        handler(json);
      }
    }
  }

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    final canonical = await _channel.invokeMethod<String>('writeState', {
      'baseJson': baseJson,
      'targetJson': targetJson,
      'checkIntents': checkIntents,
      'lifecycleIntents': lifecycleIntents,
    });
    if (canonical == null) {
      throw StateError('Native storage returned no canonical state');
    }
    return canonical;
  }

  @override
  Future<String> resetState({
    required String targetJson,
    Map<String, Object?>? widgetSummary,
  }) async {
    final canonical = await _channel.invokeMethod<String>('resetState', {
      'targetJson': targetJson,
      'widgetSummary': ?widgetSummary,
    });
    if (canonical == null) {
      throw StateError('Native storage returned no reset state');
    }
    return canonical;
  }

  @override
  Future<Map<String, Object?>> widgetSnapshot({
    required int? widgetId,
    required String kind,
  }) async => _stringKeyMap(
    await _channel.invokeMapMethod<dynamic, dynamic>('widgetSnapshot', {
      'widgetId': widgetId,
      'kind': kind,
    }),
  );

  @override
  Future<bool> requestPinWidget({required String kind}) async =>
      await _channel.invokeMethod<bool>('requestPinWidget', {'kind': kind}) ??
      false;

  @override
  Future<Map<String, Object?>> reminderStatus() async => _stringKeyMap(
    await _channel.invokeMapMethod<dynamic, dynamic>('reminderStatus'),
  );

  @override
  Future<Map<String, Object?>> scheduleReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async => _stringKeyMap(
    await _channel.invokeMapMethod<dynamic, dynamic>('scheduleReminder', {
      'hour': hour,
      'minute': minute,
      'enabled': enabled,
    }),
  );

  @override
  Future<bool> requestNotifications() async =>
      await _channel.invokeMethod<bool>('requestNotifications') ?? false;
}

/// In-memory transaction gateway for tests and widget previews. Its merge
/// behavior mirrors the native lock-protected transaction.
class FakeLeaveGateway implements LeaveGateway {
  FakeLeaveGateway({this.storedJson}) {
    final raw = storedJson;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _storageEpoch = 'legacy-v1';
          final epoch = decoded['_storageEpoch'];
          final revision = decoded['_nativeRevision'];
          if (epoch is String && epoch.isNotEmpty) _storageEpoch = epoch;
          if (revision is int && revision >= 0) _nativeRevision = revision;
        }
      } on FormatException {
        // Corrupt-state recovery uses resetState; malformed content must not
        // prevent construction of the in-memory test gateway.
      }
    }
  }

  String? storedJson;
  String? damagedJson;
  String? pendingLaunchAction;
  String? readStateOverride;
  void Function(String action)? _launchActionHandler;
  void Function(String json)? _externalStateChangedHandler;
  bool failReads = false;
  bool failWrites = false;
  bool notificationsGranted = true;
  bool pinWidgetAccepted = true;
  Map<String, Object?> currentReminderStatus = const {};
  Map<String, Object?> currentWidgetSnapshot = const {};
  Future<void> Function()? beforeReadReply;
  Future<void> Function()? beforeWriteCommit;
  Future<void> Function(String committedJson)? beforeWriteReply;
  final List<String> writes = [];
  final List<Map<String, Object?>> writeTransactions = [];
  final List<Map<String, Object?>> widgetSummaries = [];
  final List<Map<String, Object?>> reminderSchedules = [];
  final List<String> pinWidgetRequests = [];
  int _nativeRevision = 0;
  String _storageEpoch = 'fake-native-epoch';

  @override
  Future<String?> readState() async {
    if (failReads) throw StateError('Injected state read failure');
    final value = readStateOverride ?? storedJson;
    readStateOverride = null;
    final callback = beforeReadReply;
    if (callback != null) {
      beforeReadReply = null;
      await callback();
    }
    return value;
  }

  @override
  Future<String?> getLaunchAction() async {
    final action = pendingLaunchAction;
    pendingLaunchAction = null;
    return action;
  }

  @override
  void setLaunchActionHandler(void Function(String action)? handler) {
    _launchActionHandler = handler;
  }

  @override
  void setExternalStateChangedHandler(void Function(String json)? handler) {
    _externalStateChangedHandler = handler;
  }

  void emitLaunchAction(String action) {
    final handler = _launchActionHandler;
    if (handler == null) {
      pendingLaunchAction = action;
    } else {
      handler(action);
    }
  }

  void emitExternalStateChange(String json) =>
      _externalStateChangedHandler?.call(json);

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    if (failWrites) throw StateError('Injected state write failure');
    final beforeCommit = beforeWriteCommit;
    if (beforeCommit != null) {
      beforeWriteCommit = null;
      await beforeCommit();
    }
    if (storedJson != null) {
      final baseRoot = jsonDecode(baseJson) as Map;
      final currentRoot = jsonDecode(storedJson!) as Map;
      final baseEpoch = baseRoot['_storageEpoch'] as String? ?? 'legacy-v1';
      final currentEpoch =
          currentRoot['_storageEpoch'] as String? ?? 'legacy-v1';
      if (baseEpoch != currentEpoch) {
        throw StateError('Base state belongs to a stale storage epoch');
      }
    }
    final base = _decodeState(baseJson);
    final target = _decodeState(targetJson);
    final current = storedJson == null ? base : _decodeState(storedJson!);
    final checkMap = {
      for (final intent in checkIntents)
        _itemKey(intent['outingId'] as String, intent['itemId'] as String):
            intent['checked'] as bool,
    };
    final lifecycleMap = {
      for (final intent in lifecycleIntents)
        intent['outingId'] as String: intent,
    };
    final currentOutings = {
      for (final outing in current.outings) outing.id: outing,
    };
    final canonicalOutings = target.outings.map((targetOuting) {
      final currentOuting = currentOutings[targetOuting.id];
      final items = targetOuting.items.map((targetItem) {
        final key = _itemKey(targetOuting.id, targetItem.id);
        final currentItem = currentOuting?.items
            .where((item) => item.id == targetItem.id)
            .firstOrNull;
        final checked =
            checkMap[key] ?? currentItem?.checked ?? targetItem.checked;
        return targetItem.copyWith(checked: checked);
      }).toList();
      final life = lifecycleMap[targetOuting.id];
      final hasLifecycleIntent = life != null;
      var canonical = targetOuting.copyWith(
        items: items,
        completedAt: hasLifecycleIntent
            ? _parseNullableDate(life['completedAt'])
            : currentOuting != null
            ? currentOuting.completedAt
            : targetOuting.completedAt,
        dismissedAtUTC: hasLifecycleIntent
            ? _parseNullableDate(life['dismissedAtUTC'])
            : currentOuting != null
            ? currentOuting.dismissedAtUTC
            : targetOuting.dismissedAtUTC,
      );
      if (canonical.completedAt != null && !canonical.canFinish) {
        canonical = canonical.copyWith(completedAt: null);
      }
      return canonical;
    }).toList();
    final canonical = target.copyWith(outings: canonicalOutings);
    _nativeRevision++;
    final envelope = _withMetadata(canonical, _storageEpoch, _nativeRevision);
    final result = <String, Object?>{...envelope};
    final rejected = <String>[
      for (final targetOuting in target.outings)
        if (targetOuting.completedAt != null &&
            canonicalOutings
                    .firstWhere((outing) => outing.id == targetOuting.id)
                    .completedAt ==
                null)
          targetOuting.id,
    ];
    if (rejected.isNotEmpty) result['_rejectedFinishIds'] = rejected;
    final canonicalJson = jsonEncode(result);
    storedJson = canonicalJson;
    writes.add(targetJson);
    writeTransactions.add(
      Map.unmodifiable({
        'baseJson': baseJson,
        'targetJson': targetJson,
        'checkIntents': List.unmodifiable(checkIntents),
        'lifecycleIntents': List.unmodifiable(lifecycleIntents),
      }),
    );
    final callback = beforeWriteReply;
    if (callback != null) {
      beforeWriteReply = null;
      await callback(canonicalJson);
    }
    return canonicalJson;
  }

  @override
  Future<String> resetState({
    required String targetJson,
    Map<String, Object?>? widgetSummary,
  }) async {
    if (failWrites) throw StateError('Injected state write failure');
    damagedJson = storedJson;
    storedJson = targetJson;
    writes.add(targetJson);
    if (widgetSummary != null) {
      widgetSummaries.add(Map.unmodifiable(widgetSummary));
    }
    _nativeRevision = 1;
    _storageEpoch = 'fake-reset-${DateTime.now().microsecondsSinceEpoch}';
    final canonical = _withMetadata(
      _decodeState(targetJson),
      _storageEpoch,
      _nativeRevision,
    );
    storedJson = jsonEncode(canonical);
    return storedJson!;
  }

  /// Simulates a native widget check transaction and sends its canonical state
  /// to a live controller, if one is registered.
  Future<String> setWidgetCheck({
    required String outingId,
    required String itemId,
    required bool checked,
  }) async {
    final currentJson = storedJson;
    if (currentJson == null) throw StateError('No native state');
    final current = _decodeState(currentJson);
    final outingIndex = current.outings.indexWhere(
      (outing) => outing.id == outingId && outing.isActive,
    );
    if (outingIndex < 0) return currentJson;
    final outing = current.outings[outingIndex];
    final itemIndex = outing.items.indexWhere((item) => item.id == itemId);
    if (itemIndex < 0) return currentJson;
    final items = [...outing.items];
    items[itemIndex] = items[itemIndex].copyWith(checked: checked);
    final outings = [...current.outings];
    outings[outingIndex] = outing.copyWith(items: items);
    final canonical = _withMetadata(
      current.copyWith(outings: outings),
      _storageEpoch,
      ++_nativeRevision,
    );
    storedJson = jsonEncode(canonical);
    _externalStateChangedHandler?.call(storedJson!);
    return storedJson!;
  }

  @override
  Future<Map<String, Object?>> widgetSnapshot({
    required int? widgetId,
    required String kind,
  }) async => Map.unmodifiable(currentWidgetSnapshot);

  @override
  Future<bool> requestPinWidget({required String kind}) async =>
      _recordPinRequest(kind);

  Future<bool> _recordPinRequest(String kind) async {
    pinWidgetRequests.add(kind);
    return pinWidgetAccepted;
  }

  @override
  Future<Map<String, Object?>> reminderStatus() async =>
      Map.unmodifiable(currentReminderStatus);

  @override
  Future<Map<String, Object?>> scheduleReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    final schedule = <String, Object?>{
      'hour': hour,
      'minute': minute,
      'enabled': enabled,
    };
    reminderSchedules.add(Map.unmodifiable(schedule));
    return Map.unmodifiable(schedule);
  }

  @override
  Future<bool> requestNotifications() async => notificationsGranted;
}

AppState _decodeState(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) throw const FormatException('Invalid state JSON');
  return AppState.fromJson(Map<String, Object?>.from(decoded));
}

Map<String, Object?> _withMetadata(
  AppState state,
  String epoch,
  int revision,
) => {...state.toJson(), '_storageEpoch': epoch, '_nativeRevision': revision};

DateTime? _parseNullableDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String _itemKey(String outingId, String itemId) => '$outingId\u0000$itemId';

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic>? value) =>
    value?.map((key, value) => MapEntry(key.toString(), value)) ?? {};

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
