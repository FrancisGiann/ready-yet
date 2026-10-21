import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform/leave_gateway.dart';
import 'models.dart';

typedef IdFactory = String Function();

/// Owns the in-memory app state and serializes each snapshot to the gateway.
/// Mutations apply immediately; their returned futures complete after that
/// snapshot has been written (or leave a visible [saveError] on failure).
class AppController extends ChangeNotifier {
  // Keep the injectable dependency's public parameter name while the field
  // remains private to this library.
  // ignore: prefer_initializing_formals
  AppController({
    required LeaveGateway gateway,
    IdFactory? idFactory,
    DateTime Function()? now,
  })
    // ignore: prefer_initializing_formals
    : _gateway = gateway,
       _idFactory = idFactory ?? _randomId,
       _now = now ?? DateTime.now {
    _gateway.setExternalStateChangedHandler(_handleExternalStateChanged);
  }

  final LeaveGateway _gateway;
  final IdFactory _idFactory;
  final DateTime Function() _now;

  AppState _state = AppState.initial();
  AppState _canonicalState = AppState.initial();
  AppState _lastQueuedState = AppState.initial();
  Object? _saveError;
  Object? _loadError;
  bool _isReady = false;
  bool _disposed = false;
  int _revision = 0;
  int _nativeRevision = 0;
  String _storageEpoch = 'legacy-v1';
  String? _legacyUpgradeEpoch;
  int _resetGeneration = 0;
  final Set<String> _retiredStorageEpochs = {};
  bool _epochResetBarrier = false;
  String? _queuedExternalState;
  final Map<_ItemCheckKey, int> _checkGenerations = {};
  final Map<_ItemCheckKey, int> _ackedCheckGenerations = {};
  final Map<String, int> _lifecycleGenerations = {};
  final Map<String, int> _ackedLifecycleGenerations = {};
  Future<void>? _initialization;
  Future<void> _writeQueue = Future<void>.value();

  AppState get state => _state;
  AppState get canonicalState => _canonicalState;
  Object? get saveError => _saveError;
  Object? get loadError => _loadError;
  bool get isReady => _isReady;
  bool get canEdit => _isReady && _loadError == null;
  String get storageEpoch => _storageEpoch;
  int get nativeRevision => _nativeRevision;

  Future<void> initialize() => _initialization ??= _readInitialState();

  Future<void> _readInitialState() async {
    await _loadState();
    _isReady = true;
    if (canEdit) {
      try {
        await ensureScheduledToday();
      } catch (error) {
        _saveError = error;
      }
    }
    _notify();
  }

  Future<void> retryLoad() async {
    _requireReady();
    if (_loadError == null) {
      throw StateError('There is no saved-data error to retry');
    }
    await _loadState();
    _notify();
  }

  Future<void> _loadState() async {
    try {
      final json = await _gateway.readState();
      final envelope = json == null || json.isEmpty
          ? _StateEnvelope(AppState.initial(), 'legacy-v1', 0, const {})
          : _decodeEnvelope(json);
      final loadedState = envelope.state;
      _state = loadedState;
      _canonicalState = loadedState;
      _lastQueuedState = loadedState;
      _storageEpoch = envelope.epoch;
      _nativeRevision = envelope.nativeRevision;
      _legacyUpgradeEpoch = null;
      _resetGeneration++;
      _retiredStorageEpochs.clear();
      _epochResetBarrier = false;
      _checkGenerations.clear();
      _ackedCheckGenerations.clear();
      _lifecycleGenerations.clear();
      _ackedLifecycleGenerations.clear();
      _loadError = null;
      _saveError = null;
      final queued = _queuedExternalState;
      _queuedExternalState = null;
      if (queued != null) _reconcileExternal(queued);
    } catch (error) {
      // Keep unreadable data in storage until the user retries or explicitly
      // chooses to start fresh. Mutations are disabled while loadError exists.
      _state = AppState.initial();
      _loadError = error;
    }
  }

  _StateEnvelope _decodeEnvelope(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('Saved state must be a JSON object');
    }
    final raw = Map<String, Object?>.from(decoded);
    final epochValue = raw['_storageEpoch'];
    final revisionValue = raw['_nativeRevision'];
    final rejectedValue = raw['_rejectedFinishIds'];
    return _StateEnvelope(
      AppState.fromJson(raw),
      epochValue is String && epochValue.isNotEmpty ? epochValue : 'legacy-v1',
      revisionValue is int && revisionValue >= 0 ? revisionValue : 0,
      {
        if (rejectedValue is List)
          for (final value in rejectedValue)
            if (value is String) value,
      },
    );
  }

  /// Clears unreadable saved data only after an explicit user choice.
  Future<void> resetCorruptState() {
    _requireReady();
    if (_loadError == null) {
      throw StateError('There is no unreadable state to reset');
    }
    final resetState = AppState.initial();
    final revision = ++_revision;
    final json = jsonEncode(resetState.toJson());
    final widgetSummary = resetState.widgetSummary;
    final Future<void> resetFuture = _writeQueue.then<void>(
      (_) => _performExplicitReset(resetState, json, widgetSummary, revision),
      onError: (_, _) =>
          _performExplicitReset(resetState, json, widgetSummary, revision),
    );
    // Keep the shared queue usable if the explicitly requested reset fails;
    // return resetFuture itself so the recovery UI can report that failure.
    _writeQueue = resetFuture.then<void>((_) {}, onError: (_, _) {});
    return resetFuture;
  }

  Future<void> _performExplicitReset(
    AppState resetState,
    String json,
    Map<String, Object?> widgetSummary,
    int revision,
  ) async {
    try {
      final canonicalJson = await _gateway.resetState(
        targetJson: json,
        widgetSummary: widgetSummary,
      );
      if (revision == _revision) {
        final envelope = _decodeEnvelope(canonicalJson);
        final previousEpoch = _storageEpoch;
        _state = resetState;
        _canonicalState = envelope.state;
        _lastQueuedState = resetState;
        _storageEpoch = envelope.epoch;
        _nativeRevision = envelope.nativeRevision;
        _legacyUpgradeEpoch = null;
        _resetGeneration++;
        if (previousEpoch != envelope.epoch) {
          _retiredStorageEpochs.add(previousEpoch);
        }
        _epochResetBarrier = true;
        _checkGenerations.clear();
        _ackedCheckGenerations.clear();
        _lifecycleGenerations.clear();
        _ackedLifecycleGenerations.clear();
        _queuedExternalState = null;
        _loadError = null;
        _saveError = null;
        _notify();
      }
    } catch (error) {
      if (revision == _revision) {
        _loadError = error;
        _saveError = error;
        _notify();
      }
      rethrow;
    }
  }

  /// Rewrites the latest state after a transient storage error or corrupt file.
  Future<void> retrySave() {
    _requireWritable();
    return _queueSnapshot();
  }

  /// Waits until all snapshots currently queued have reached the gateway.
  Future<void> waitForSaves() => _writeQueue;

  /// Reads a one-shot action supplied by a cold native launch.
  Future<String?> getLaunchAction() => _gateway.getLaunchAction();

  /// Resolves one native widget launch into an existing or new outing. Request
  /// IDs are persisted with the state so duplicate Android intents can never
  /// create duplicate sessions after a restart.
  Future<String> handleWidgetLaunchAction(String actionJson) async {
    _requireWritable();
    final decoded = jsonDecode(actionJson);
    if (decoded is! Map) throw const FormatException('Invalid widget action');
    final action = Map<String, Object?>.from(decoded);
    final type = action['type'];
    if (_state.schedules.isNotEmpty ||
        type == 'schedule_outing' ||
        type == 'scheduled_widget_outing') {
      await refreshExternalState();
    }
    final requestId = action['requestId'];
    if (requestId is! String ||
        requestId.trim().isEmpty ||
        requestId.length > 160) {
      throw const FormatException('Invalid widget request ID');
    }
    String? scheduledWidgetOutingId;
    if (type == 'scheduled_widget_outing') {
      final id = action['outingId'];
      final scheduleId = action['scheduleId'];
      final epoch = action['storageEpoch'];
      final today = localDateKey(_now());
      final schedule = _state.schedules
          .where((value) => value.id == scheduleId)
          .firstOrNull;
      final outing = _state.outings
          .where((value) => value.id == id)
          .firstOrNull;
      if (id is! String ||
          scheduleId is! String ||
          epoch != _storageEpoch ||
          schedule == null ||
          !schedule.runsOn(_now()) ||
          outing == null ||
          outing.scheduleId != scheduleId ||
          outing.blueprintId != schedule.blueprintId ||
          outing.date != today ||
          outing.id != schedule.occurrenceId(today) ||
          (!outing.isActive && !outing.isComplete)) {
        throw const FormatException(
          'Scheduled widget checklist is no longer available',
        );
      }
      scheduledWidgetOutingId = outing.id;
    }
    final previouslyHandled = _state.widgetLaunchRequests[requestId];
    if (previouslyHandled != null) {
      if (type == 'scheduled_widget_outing' &&
          previouslyHandled != scheduledWidgetOutingId) {
        throw const FormatException(
          'Widget request does not match its original occurrence',
        );
      }
      final previous = _state.outings
          .where((o) => o.id == previouslyHandled)
          .firstOrNull;
      final oldScheduledList =
          type == 'widget_list' &&
          previous?.scheduleId != null &&
          previous?.date != localDateKey(_now());
      if (!oldScheduledList) return previouslyHandled;
    }

    String outingId;
    if (type == 'widget_list') {
      final blueprintId = action['blueprintId'];
      if (blueprintId is! String) {
        throw const FormatException('Widget list action is missing a list ID');
      }
      _blueprintIndex(blueprintId);
      final active =
          _state.outings
              .where(
                (outing) =>
                    outing.isActive &&
                    outing.blueprintId == blueprintId &&
                    (outing.scheduleId == null ||
                        outing.date == localDateKey(_now())),
              )
              .toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final today = localDateKey(_now());
      final scheduled =
          _state.outings
              .where(
                (outing) =>
                    outing.scheduleId != null &&
                    outing.blueprintId == blueprintId &&
                    outing.date == today &&
                    _state.schedules.any(
                      (s) => s.id == outing.scheduleId && s.enabled,
                    ),
              )
              .toList()
            ..sort((a, b) {
              final activeOrder = (a.isActive ? 0 : 1).compareTo(
                b.isActive ? 0 : 1,
              );
              return activeOrder != 0
                  ? activeOrder
                  : a.startedAt.compareTo(b.startedAt);
            });
      if (scheduled.isNotEmpty) {
        outingId = scheduled.first.id;
      } else if (active.isNotEmpty) {
        outingId = active.first.id;
      } else {
        final created = _createOuting(blueprintId, date: localDateKey(_now()));
        outingId = created.id;
        _state = _state.copyWith(outings: [..._state.outings, created]);
      }
    } else if (type == 'scheduled_widget_outing') {
      outingId = scheduledWidgetOutingId!;
    } else if (type == 'schedule_outing') {
      final id = action['outingId'];
      final scheduleId = action['scheduleId'];
      final outing = _state.outings
          .where((outing) => outing.id == id)
          .firstOrNull;
      if (outing == null ||
          !outing.isActive ||
          outing.scheduleId != scheduleId ||
          outing.id != 'scheduled:$scheduleId:${outing.date}') {
        throw const FormatException(
          'Scheduled checklist is no longer available',
        );
      }
      outingId = outing.id;
    } else if (type == 'widget_outing') {
      final rawOutingId = action['outingId'];
      final rawBlueprintId = action['blueprintId'];
      if (rawOutingId is! String || rawBlueprintId is! String) {
        throw const FormatException('Widget outing action is missing its IDs');
      }
      final outingIndex = _outingIndex(rawOutingId);
      final outing = _state.outings[outingIndex];
      if (outing.blueprintId != rawBlueprintId) {
        throw const FormatException('Widget outing does not match its list');
      }
      outingId = outing.id;
    } else {
      throw const FormatException('Unsupported widget action');
    }

    final requestMap = Map<String, String>.from(_state.widgetLaunchRequests)
      ..[requestId] = outingId;
    while (requestMap.length > 64) {
      requestMap.remove(requestMap.keys.first);
    }
    _state = _state.copyWith(widgetLaunchRequests: requestMap);
    final result = await _queueSnapshotResult();
    if (result.error != null) throw result.error!;
    return outingId;
  }

  /// Reads native state on app resume and reconciles only native-owned checks
  /// and lifecycle fields, keeping dirty local intent overlays intact.
  Future<void> refreshExternalState() async {
    _requireWritable();
    await _writeQueue;
    final json = await _gateway.readState();
    if (json == null || json.isEmpty) return;
    _reconcileExternal(json);
    await ensureScheduledToday();
    _notify();
  }

  Future<Map<String, Object?>> widgetSnapshot({
    required int? widgetId,
    required String kind,
  }) => _gateway.widgetSnapshot(widgetId: widgetId, kind: kind);

  Future<bool> requestPinWidget({required String kind}) =>
      _gateway.requestPinWidget(kind: kind);

  /// Receives actions delivered while the app is already running.
  void setLaunchActionHandler(void Function(String action)? handler) =>
      _gateway.setLaunchActionHandler(handler);

  void _handleExternalStateChanged(String json) {
    if (!_isReady || _loadError != null) {
      _queuedExternalState = json;
      return;
    }
    _reconcileExternal(json);
    _notify();
  }

  void _reconcileExternal(String json) {
    try {
      _acceptCanonicalEnvelope(_decodeEnvelope(json));
    } catch (error) {
      // A malformed event is not authoritative. Preserve the last usable
      // snapshot and let resume read or the next transaction repair the view.
      _saveError = error;
    }
  }

  void _acceptCanonicalEnvelope(_StateEnvelope envelope) {
    final previouslySavedIds = _canonicalState.outings
        .map((outing) => outing.id)
        .toSet();
    if (envelope.epoch == _storageEpoch) {
      if (envelope.nativeRevision >= _nativeRevision) {
        _nativeRevision = envelope.nativeRevision;
        _canonicalState = envelope.state;
      }
    } else if (!_epochResetBarrier &&
        _storageEpoch == 'legacy-v1' &&
        envelope.epoch != 'legacy-v1' &&
        !_retiredStorageEpochs.contains(envelope.epoch)) {
      // A normal first native write upgrades a pre-metadata file to an epoch.
      // Other epoch transitions are only authorized by load/reset barriers.
      _retiredStorageEpochs.add(_storageEpoch);
      _storageEpoch = envelope.epoch;
      _nativeRevision = envelope.nativeRevision;
      _canonicalState = envelope.state;
    }
    // Successful older acknowledgements still resolve their captured intent
    // generations. Always rebase the now-clean UI from the newest cached
    // canonical state, not the potentially older response body.
    _mergeCanonicalFieldsIntoCurrent(_canonicalState, previouslySavedIds);
    _lastQueuedState = _state;
  }

  void _mergeCanonicalFieldsIntoCurrent(
    AppState canonical,
    Set<String> previouslySavedIds,
  ) {
    final canonicalOutings = {
      for (final outing in canonical.outings) outing.id: outing,
    };
    final mergedOutings = _state.outings.map((requested) {
      final remote = canonicalOutings[requested.id];
      if (remote == null) return requested;
      final local =
          remote.scheduleId != null && !previouslySavedIds.contains(remote.id)
          ? remote
          : requested;
      final mergedItems = local.items.map((localItem) {
        final key = _ItemCheckKey(local.id, localItem.id);
        if ((_checkGenerations[key] ?? 0) >
            (_ackedCheckGenerations[key] ?? 0)) {
          final pending = requested.items
              .where((item) => item.id == localItem.id)
              .firstOrNull;
          return pending == null
              ? localItem
              : localItem.copyWith(checked: pending.checked);
        }
        final remoteItem = remote.items
            .where((item) => item.id == localItem.id)
            .firstOrNull;
        return remoteItem == null
            ? localItem
            : localItem.copyWith(checked: remoteItem.checked);
      }).toList();
      final lifecycleIsDirty =
          (_lifecycleGenerations[local.id] ?? 0) >
          (_ackedLifecycleGenerations[local.id] ?? 0);
      return local.copyWith(
        items: mergedItems,
        completedAt: lifecycleIsDirty
            ? requested.completedAt
            : remote.completedAt,
        dismissedAtUTC: lifecycleIsDirty
            ? requested.dismissedAtUTC
            : remote.dismissedAtUTC,
      );
    }).toList();
    final localIds = mergedOutings.map((outing) => outing.id).toSet();
    mergedOutings.addAll(
      canonical.outings.where(
        (outing) => outing.scheduleId != null && !localIds.contains(outing.id),
      ),
    );
    _state = _state.copyWith(outings: mergedOutings);
  }

  Future<void> _queueSnapshot() {
    return _queueSnapshotResult().then((_) {});
  }

  Future<_SnapshotResult> _queueSnapshotResult({
    void Function(Object error)? onError,
  }) {
    _requireWritable();
    final revision = ++_revision;
    final capturedEpoch = _storageEpoch;
    final capturedResetGeneration = _resetGeneration;
    final base = _lastQueuedState;
    final target = _state;
    _lastQueuedState = target;
    final capturedChecks = <_ItemCheckKey, _CapturedIntent>{};
    for (final entry in _checkGenerations.entries) {
      if (entry.value <= (_ackedCheckGenerations[entry.key] ?? 0)) continue;
      final outing = target.outings
          .where((value) => value.id == entry.key.outingId)
          .firstOrNull;
      final item = outing?.items
          .where((value) => value.id == entry.key.itemId)
          .firstOrNull;
      if (item != null) {
        capturedChecks[entry.key] = _CapturedIntent(
          generation: entry.value,
          value: item.checked,
        );
      }
    }
    final capturedLifecycles = <String, _CapturedLifecycle>{};
    for (final entry in _lifecycleGenerations.entries) {
      if (entry.value <= (_ackedLifecycleGenerations[entry.key] ?? 0)) {
        continue;
      }
      final outing = target.outings
          .where((value) => value.id == entry.key)
          .firstOrNull;
      if (outing != null) {
        capturedLifecycles[entry.key] = _CapturedLifecycle(
          generation: entry.value,
          completedAt: outing.completedAt,
          dismissedAtUTC: outing.dismissedAtUTC,
        );
      }
    }
    _notify();
    final previousQueue = _writeQueue;
    final operation = previousQueue.then<_SnapshotResult>(
      (_) => _persistSnapshot(
        revision: revision,
        base: base,
        target: target,
        capturedEpoch: capturedEpoch,
        capturedResetGeneration: capturedResetGeneration,
        checks: capturedChecks,
        lifecycles: capturedLifecycles,
        onError: onError,
      ),
      onError: (_, _) => _persistSnapshot(
        revision: revision,
        base: base,
        target: target,
        capturedEpoch: capturedEpoch,
        capturedResetGeneration: capturedResetGeneration,
        checks: capturedChecks,
        lifecycles: capturedLifecycles,
        onError: onError,
      ),
    );
    _writeQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<_SnapshotResult> _persistSnapshot({
    required int revision,
    required AppState base,
    required AppState target,
    required String capturedEpoch,
    required int capturedResetGeneration,
    required Map<_ItemCheckKey, _CapturedIntent> checks,
    required Map<String, _CapturedLifecycle> lifecycles,
    void Function(Object error)? onError,
  }) async {
    final isQueuedResetStale = capturedResetGeneration != _resetGeneration;
    final isFirstWriteEpochUpgrade =
        capturedEpoch == 'legacy-v1' &&
        _legacyUpgradeEpoch != null &&
        _legacyUpgradeEpoch == _storageEpoch;
    final isEpochStale =
        capturedEpoch != _storageEpoch && !isFirstWriteEpochUpgrade;
    if (isQueuedResetStale || isEpochStale) {
      final error = StateError(
        'Saved data changed before this update could be written. Reload saved data before continuing.',
      );
      _saveError = error;
      _loadError = error;
      _notify();
      onError?.call(error);
      return _SnapshotResult(error: error);
    }

    final checkIntents = <Map<String, Object?>>[];
    for (final entry in checks.entries) {
      final currentGeneration = _checkGenerations[entry.key] ?? 0;
      final ackedGeneration = _ackedCheckGenerations[entry.key] ?? 0;
      if (entry.value.generation <= ackedGeneration ||
          currentGeneration < entry.value.generation ||
          !_containsItem(_state, entry.key)) {
        continue;
      }
      checkIntents.add(
        OutingCheckIntent(
          outingId: entry.key.outingId,
          itemId: entry.key.itemId,
          checked: entry.value.value,
        ).toJson(),
      );
    }
    final lifecycleIntents = <Map<String, Object?>>[];
    for (final entry in lifecycles.entries) {
      final currentGeneration = _lifecycleGenerations[entry.key] ?? 0;
      final ackedGeneration = _ackedLifecycleGenerations[entry.key] ?? 0;
      if (entry.value.generation <= ackedGeneration ||
          currentGeneration < entry.value.generation ||
          !_containsOuting(_state, entry.key)) {
        continue;
      }
      lifecycleIntents.add(
        OutingLifecycleIntent(
          outingId: entry.key,
          completedAt: entry.value.completedAt,
          dismissedAtUTC: entry.value.dismissedAtUTC,
        ).toJson(),
      );
    }

    try {
      final canonicalJson = await _gateway.writeState(
        baseJson: jsonEncode({
          ...base.toJson(),
          '_storageEpoch': _storageEpoch,
          '_nativeRevision': _nativeRevision,
        }),
        targetJson: jsonEncode(target.toJson()),
        checkIntents: checkIntents,
        lifecycleIntents: lifecycleIntents,
      );
      final envelope = _decodeEnvelope(canonicalJson);
      for (final entry in checks.entries) {
        if (entry.value.generation > (_ackedCheckGenerations[entry.key] ?? 0)) {
          _ackedCheckGenerations[entry.key] = entry.value.generation;
        }
      }
      for (final entry in lifecycles.entries) {
        if (entry.value.generation >
            (_ackedLifecycleGenerations[entry.key] ?? 0)) {
          _ackedLifecycleGenerations[entry.key] = entry.value.generation;
        }
      }
      if (_storageEpoch == 'legacy-v1' && envelope.epoch != 'legacy-v1') {
        // Only an acknowledged local write may authorize queued snapshots
        // captured before the first native metadata was created.
        _legacyUpgradeEpoch = envelope.epoch;
      }
      _acceptCanonicalEnvelope(envelope);
      final rejected = envelope.rejectedFinishIds;
      if (revision == _revision) {
        _saveError = null;
      }
      // A stale write can still resolve the last dirty local generation and
      // expose a newer widget canonical value. Notify even while later queued
      // structural writes are pending.
      _notify();
      return _SnapshotResult(
        canonicalState: envelope.state,
        rejectedFinishIds: rejected,
      );
    } catch (error) {
      _saveError = error;
      _notify();
      _rollbackFailedFinish(target, lifecycles, error);
      onError?.call(error);
      return _SnapshotResult(error: error);
    }
  }

  void _rollbackFailedFinish(
    AppState target,
    Map<String, _CapturedLifecycle> lifecycles,
    Object error,
  ) {
    for (final entry in lifecycles.entries) {
      if (entry.value.completedAt == null ||
          _lifecycleGenerations[entry.key] != entry.value.generation) {
        continue;
      }
      final index = _state.outings.indexWhere(
        (outing) => outing.id == entry.key,
      );
      if (index < 0 || _state.outings[index].completedAt == null) continue;
      // Retire this failed optimistic finish before any already-captured
      // unrelated snapshot can dispatch. The next generation is the explicit
      // null rollback and remains retryable if its own save fails.
      final failedGeneration = entry.value.generation;
      if (failedGeneration > (_ackedLifecycleGenerations[entry.key] ?? 0)) {
        _ackedLifecycleGenerations[entry.key] = failedGeneration;
      }
      final outings = [..._state.outings];
      outings[index] = outings[index].copyWith(completedAt: null);
      _state = _state.copyWith(outings: outings);
      _markLifecycleIntent(entry.key);
      _lastQueuedState = target;
      _notify();
      // Queue a null lifecycle intent after the failed write. The best-effort
      // rollback remains retryable if storage is still unavailable.
      unawaited(_queueSnapshot());
    }
    _saveError = error;
  }

  /// Creates only today's occurrences. Missed past days are not backfilled.
  Future<void> ensureScheduledToday() async {
    _requireWritable();
    final now = _now();
    final date = localDateKey(now);
    final existing = _state.outings.map((outing) => outing.id).toSet();
    final created = <Outing>[];
    for (final schedule in _state.schedules) {
      final blueprint = _state.blueprints
          .where((b) => b.id == schedule.blueprintId)
          .firstOrNull;
      if (!schedule.runsOn(now) ||
          blueprint == null ||
          existing.contains(schedule.occurrenceId(date))) {
        continue;
      }
      final items = <OutingItem>[
        ...blueprint.items.map(
          (i) => OutingItem(id: i.id, label: i.label, iconKey: i.iconKey),
        ),
        ..._state.extras
            .where((e) => e.blueprintId == blueprint.id && e.date == date)
            .map(
              (e) => OutingItem(
                id: 'extra:${e.id}',
                label: e.label,
                iconKey: e.iconKey,
              ),
            ),
      ];
      created.add(
        Outing(
          id: schedule.occurrenceId(date),
          scheduleId: schedule.id,
          blueprintId: blueprint.id,
          blueprintName: blueprint.name,
          date: date,
          startedAt: now,
          items: items,
        ),
      );
      existing.add(schedule.occurrenceId(date));
    }
    if (created.isEmpty) return;
    _state = _state.copyWith(outings: [..._state.outings, ...created]);
    final result = await _queueSnapshotResult();
    if (result.error != null) throw result.error!;
  }

  Future<void> saveSchedule(ChecklistSchedule schedule) async {
    _requireWritable();
    _blueprintIndex(schedule.blueprintId);
    if (_state.schedules.length >= 32 &&
        !_state.schedules.any((s) => s.id == schedule.id)) {
      throw StateError('You can keep up to 32 schedules');
    }
    _state = _state.copyWith(
      schedules: [
        ..._state.schedules.where((s) => s.id != schedule.id),
        schedule,
      ],
    );
    final result = await _queueSnapshotResult();
    if (result.error != null) throw result.error!;
    await ensureScheduledToday();
  }

  Future<bool> openNotificationSettings() async {
    final gateway = _gateway;
    try {
      return gateway is SchedulePermissionGateway
          ? await (gateway as SchedulePermissionGateway)
                .openNotificationSettings()
          : false;
    } catch (_) {
      return false;
    }
  }

  String newScheduleId() => _newId();

  Future<void> deleteSchedule(String id) async {
    _requireWritable();
    _state = _state.copyWith(
      schedules: _state.schedules.where((s) => s.id != id),
    );
    final result = await _queueSnapshotResult();
    if (result.error != null) throw result.error!;
  }

  Future<bool> openPreciseReminderSettings() async {
    final gateway = _gateway;
    return gateway is SchedulePermissionGateway
        ? (gateway as SchedulePermissionGateway).openPreciseReminderSettings()
        : false;
  }

  Future<String> createBlueprint({
    required String name,
    String iconKey = 'bag',
    int colorIndex = 0,
    Iterable<ChecklistItem> items = const [],
  }) async {
    _requireWritable();
    final cleanName = _requireLabel(name);
    final id = _newId();
    _state = _state.copyWith(
      blueprints: [
        ..._state.blueprints,
        Blueprint(
          id: id,
          name: cleanName,
          iconKey: iconKey,
          colorIndex: colorIndex,
          items: items,
        ),
      ],
    );
    await _queueSnapshot();
    return id;
  }

  Future<void> updateBlueprint(
    String blueprintId, {
    String? name,
    String? iconKey,
    int? colorIndex,
  }) => _updateBlueprint(
    blueprintId,
    (blueprint) => blueprint.copyWith(
      name: name == null ? null : _requireLabel(name),
      iconKey: iconKey,
      colorIndex: colorIndex,
    ),
  );

  Future<void> _updateBlueprint(
    String blueprintId,
    Blueprint Function(Blueprint) update,
  ) {
    _requireWritable();
    final index = _blueprintIndex(blueprintId);
    final blueprints = [..._state.blueprints];
    blueprints[index] = update(blueprints[index]);
    _state = _state.copyWith(blueprints: blueprints);
    return _queueSnapshot();
  }

  Future<void> deleteBlueprint(String blueprintId) {
    _requireWritable();
    _blueprintIndex(blueprintId);
    _state = _state.copyWith(
      blueprints: _state.blueprints.where(
        (blueprint) => blueprint.id != blueprintId,
      ),
      extras: _state.extras.where((extra) => extra.blueprintId != blueprintId),
    );
    return _queueSnapshot();
  }

  Future<String> addBlueprintItem(
    String blueprintId, {
    required String label,
    String iconKey = 'spark',
  }) async {
    _requireWritable();
    final item = ChecklistItem(
      id: _newId(),
      label: _requireLabel(label),
      iconKey: iconKey,
    );
    await _updateBlueprint(
      blueprintId,
      (blueprint) => blueprint.copyWith(items: [...blueprint.items, item]),
    );
    return item.id;
  }

  Future<void> updateBlueprintItem(
    String blueprintId,
    String itemId, {
    String? label,
    String? iconKey,
  }) => _updateBlueprint(blueprintId, (blueprint) {
    final index = blueprint.items.indexWhere((item) => item.id == itemId);
    if (index < 0) throw StateError('Checklist item not found');
    final items = [...blueprint.items];
    items[index] = items[index].copyWith(
      label: label == null ? null : _requireLabel(label),
      iconKey: iconKey,
    );
    return blueprint.copyWith(items: items);
  });

  Future<void> removeBlueprintItem(String blueprintId, String itemId) =>
      _updateBlueprint(blueprintId, (blueprint) {
        if (!blueprint.items.any((item) => item.id == itemId)) {
          throw StateError('Checklist item not found');
        }
        return blueprint.copyWith(
          items: blueprint.items.where((item) => item.id != itemId),
        );
      });

  /// Uses ReorderableListView's `oldIndex` and `newIndex` convention.
  Future<void> reorderBlueprintItems(
    String blueprintId,
    int oldIndex,
    int newIndex,
  ) => _updateBlueprint(
    blueprintId,
    (blueprint) => blueprint.copyWith(
      items: _reorder(blueprint.items, oldIndex, newIndex),
    ),
  );

  Future<String> addDatedExtra(
    String blueprintId, {
    required String label,
    required String date,
    String iconKey = 'spark',
  }) async {
    _requireWritable();
    _blueprintIndex(blueprintId);
    final extra = DatedExtra(
      id: _newId(),
      blueprintId: blueprintId,
      date: requireCalendarDate(date),
      label: _requireLabel(label),
      iconKey: iconKey,
    );
    _state = _state.copyWith(extras: [..._state.extras, extra]);
    await _queueSnapshot();
    return extra.id;
  }

  Future<void> removeDatedExtra(String extraId) {
    _requireWritable();
    if (!_state.extras.any((extra) => extra.id == extraId)) {
      throw StateError('Dated extra not found');
    }
    _state = _state.copyWith(
      extras: _state.extras.where((extra) => extra.id != extraId),
    );
    return _queueSnapshot();
  }

  /// Creates an independent session from a blueprint and extras for [date].
  /// Starting is the only operation that copies extras, so previews and
  /// cancelled start sheets never consume them.
  Future<String> startOuting(String blueprintId, {String? date}) async {
    _requireWritable();
    final outing = _createOuting(blueprintId, date: date);
    _state = _state.copyWith(outings: [..._state.outings, outing]);
    await _queueSnapshot();
    return outing.id;
  }

  Outing _createOuting(String blueprintId, {String? date}) {
    final blueprint = _state.blueprints[_blueprintIndex(blueprintId)];
    final startedAt = _now();
    final outingDate = requireCalendarDate(date ?? localDateKey(startedAt));
    final extraItems = _state.extras.where(
      (extra) => extra.blueprintId == blueprintId && extra.date == outingDate,
    );
    final items = [
      ...blueprint.items.map(
        (item) =>
            OutingItem(id: _newId(), label: item.label, iconKey: item.iconKey),
      ),
      ...extraItems.map(
        (extra) => OutingItem(
          id: _newId(),
          label: extra.label,
          iconKey: extra.iconKey,
        ),
      ),
    ];
    if (items.isEmpty) {
      throw StateError('Add an item before starting this checklist');
    }
    return Outing(
      id: _newId(),
      blueprintId: blueprintId,
      blueprintName: blueprint.name,
      date: outingDate,
      startedAt: startedAt,
      items: items,
    );
  }

  Future<String> addOutingItem(
    String outingId, {
    required String label,
    String iconKey = 'spark',
  }) async {
    final itemId = _newId();
    await _updateOuting(
      outingId,
      (outing) => outing.copyWith(
        items: [
          ...outing.items,
          OutingItem(id: itemId, label: _requireLabel(label), iconKey: iconKey),
        ],
      ),
    );
    return itemId;
  }

  Future<void> toggleOutingItem(String outingId, String itemId) =>
      _setOutingItem(outingId, itemId, checked: null);

  Future<void> setOutingItemChecked(
    String outingId,
    String itemId, {
    required bool checked,
  }) => _setOutingItem(outingId, itemId, checked: checked);

  Future<void> _setOutingItem(
    String outingId,
    String itemId, {
    required bool? checked,
  }) {
    _requireWritable();
    final outingIndex = _outingIndex(outingId);
    final outing = _state.outings[outingIndex];
    if (outing.isComplete) {
      throw StateError('Reopen this outing before editing it');
    }
    if (outing.isDismissed) {
      throw StateError('Restore this outing before editing it');
    }
    final index = outing.items.indexWhere((item) => item.id == itemId);
    if (index < 0) throw StateError('Outing item not found');
    final items = [...outing.items];
    final item = items[index];
    items[index] = item.copyWith(checked: checked ?? !item.checked);
    final outings = [..._state.outings];
    outings[outingIndex] = outing.copyWith(items: items);
    _state = _state.copyWith(outings: outings);
    _markCheckIntent(outingId, itemId);
    return _queueSnapshot();
  }

  Future<void> removeOutingItem(String outingId, String itemId) =>
      _updateOuting(outingId, (outing) {
        if (!outing.items.any((item) => item.id == itemId)) {
          throw StateError('Outing item not found');
        }
        return outing.copyWith(
          items: outing.items.where((item) => item.id != itemId),
        );
      });

  Future<void> updateOutingItem(
    String outingId,
    String itemId, {
    String? label,
    String? iconKey,
  }) => _updateOuting(outingId, (outing) {
    final index = outing.items.indexWhere((item) => item.id == itemId);
    if (index < 0) throw StateError('Outing item not found');
    final items = [...outing.items];
    items[index] = items[index].copyWith(
      label: label == null ? null : _requireLabel(label),
      iconKey: iconKey,
    );
    return outing.copyWith(items: items);
  });

  /// Uses ReorderableListView's `oldIndex` and `newIndex` convention.
  Future<void> reorderOutingItems(
    String outingId,
    int oldIndex,
    int newIndex,
  ) => _updateOuting(
    outingId,
    (outing) =>
        outing.copyWith(items: _reorder(outing.items, oldIndex, newIndex)),
  );

  Future<void> finishOuting(String outingId) async {
    _requireWritable();
    final index = _outingIndex(outingId);
    final outing = _state.outings[index];
    if (outing.isDismissed) {
      throw StateError('Restore this outing before finishing it');
    }
    if (outing.isComplete) return Future<void>.value();
    if (!outing.canFinish) {
      throw StateError('Check every item before finishing');
    }
    final outings = [..._state.outings];
    outings[index] = outing.copyWith(completedAt: _now());
    _state = _state.copyWith(outings: outings);
    _markLifecycleIntent(outingId);
    final result = await _queueSnapshotResult();
    if (result.error != null) throw result.error!;
    final canonical = _canonicalState.outings
        .where((value) => value.id == outingId)
        .firstOrNull;
    final latest = _state.outings
        .where((value) => value.id == outingId)
        .firstOrNull;
    if (result.rejectedFinishIds.contains(outingId) ||
        canonical?.isComplete != true ||
        latest?.isComplete != true) {
      // A concurrent native uncheck can invalidate a finish after Flutter's
      // optimistic check. The native demotion is a resolved business outcome,
      // not a storage error or retryable completed snapshot.
      throw StateError('Check every item before finishing');
    }
  }

  Future<void> undoFinish(String outingId) async {
    _requireWritable();
    final index = _outingIndex(outingId);
    final outing = _state.outings[index];
    if (!outing.isComplete) return Future<void>.value();
    final outings = [..._state.outings];
    outings[index] = outing.copyWith(completedAt: null);
    _state = _state.copyWith(outings: outings);
    _markLifecycleIntent(outingId);
    final generation = _lifecycleGenerations[outingId]!;
    final resetGeneration = _resetGeneration;
    final result = await _queueSnapshotResult(
      onError: (error) => _rollbackFailedUndoFinish(
        outingId,
        generation,
        resetGeneration,
        error,
      ),
    );
    if (result.error != null) {
      throw result.error!;
    }
    final canonical = _canonicalState.outings
        .where((value) => value.id == outingId)
        .firstOrNull;
    final latest = _state.outings
        .where((value) => value.id == outingId)
        .firstOrNull;
    if (canonical?.isActive != true || latest?.isActive != true) {
      final error = StateError('This outing is still finished.');
      if (latest?.isActive == true) {
        _rollbackFailedUndoFinish(outingId, generation, resetGeneration, error);
      }
      throw error;
    }
  }

  void _rollbackFailedUndoFinish(
    String outingId,
    int generation,
    int resetGeneration,
    Object error,
  ) {
    if (_resetGeneration != resetGeneration ||
        _lifecycleGenerations[outingId] != generation ||
        generation <= (_ackedLifecycleGenerations[outingId] ?? 0)) {
      return;
    }
    _ackedLifecycleGenerations[outingId] = generation;
    final index = _state.outings.indexWhere((outing) => outing.id == outingId);
    if (index < 0) {
      _lastQueuedState = _state;
      _saveError = error;
      _notify();
      return;
    }

    final current = _state.outings[index];
    final canonical = _canonicalState.outings
        .where((outing) => outing.id == outingId)
        .firstOrNull;
    if (canonical == null) {
      _lastQueuedState = _state;
      _saveError = error;
      _notify();
      return;
    }

    final outings = [..._state.outings];
    outings[index] = current.copyWith(
      completedAt: canonical.completedAt,
      dismissedAtUTC: canonical.dismissedAtUTC,
    );
    _state = _state.copyWith(outings: outings);
    _lastQueuedState = _state;
    _notify();
    _saveError = error;
  }

  /// Hides an unfinished session from active surfaces while keeping its exact
  /// snapshot available in history. Dismissal never edits its blueprint/items.
  Future<void> dismissOuting(String outingId) {
    _requireWritable();
    final index = _outingIndex(outingId);
    final outing = _state.outings[index];
    if (outing.isComplete) {
      throw StateError('Completed outings cannot be dismissed');
    }
    if (outing.isDismissed) return Future<void>.value();
    return _replaceOuting(
      index,
      outing.copyWith(dismissedAtUTC: _now().toUtc()),
      lifecycleChange: true,
    );
  }

  /// Restores a dismissed session with its existing identity and check state.
  Future<void> restoreOuting(String outingId) {
    _requireWritable();
    final index = _outingIndex(outingId);
    final outing = _state.outings[index];
    if (!outing.isDismissed) return Future<void>.value();
    return _replaceOuting(
      index,
      outing.copyWith(dismissedAtUTC: null),
      lifecycleChange: true,
    );
  }

  Future<void> _updateOuting(String outingId, Outing Function(Outing) update) {
    _requireWritable();
    final index = _outingIndex(outingId);
    final outing = _state.outings[index];
    if (outing.isComplete) {
      throw StateError('Reopen this outing before editing it');
    }
    if (outing.isDismissed) {
      throw StateError('Restore this outing before editing it');
    }
    final updated = update(outing);
    _pruneRemovedCheckIntents(outing, updated);
    return _replaceOuting(index, updated);
  }

  Future<void> _replaceOuting(
    int index,
    Outing outing, {
    bool lifecycleChange = false,
  }) {
    final outings = [..._state.outings];
    outings[index] = outing;
    _state = _state.copyWith(outings: outings);
    if (lifecycleChange) _markLifecycleIntent(outing.id);
    return _queueSnapshot();
  }

  Future<void> updateSettings(AppSettings settings) {
    _requireWritable();
    if (!const {'system', 'light', 'dark'}.contains(settings.appearance)) {
      throw ArgumentError.value(settings.appearance, 'appearance');
    }
    if (!const {'lime', 'sky', 'lilac'}.contains(settings.accent)) {
      throw ArgumentError.value(settings.accent, 'accent');
    }
    if (settings.reminderHour < 0 || settings.reminderHour > 23) {
      throw ArgumentError.value(settings.reminderHour, 'reminderHour');
    }
    if (settings.reminderMinute < 0 || settings.reminderMinute > 59) {
      throw ArgumentError.value(settings.reminderMinute, 'reminderMinute');
    }
    _state = _state.copyWith(settings: settings);
    return _queueSnapshot();
  }

  Future<Map<String, Object?>> reminderStatus() => _gateway.reminderStatus();

  Future<bool> requestNotifications() => _gateway.requestNotifications();

  Future<Map<String, Object?>> setReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    _requireWritable();
    if (hour < 0 || hour > 23) throw ArgumentError.value(hour, 'hour');
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(minute, 'minute');
    }
    var permissionGranted = true;
    if (enabled) permissionGranted = await _gateway.requestNotifications();
    if (!permissionGranted) {
      await updateSettings(
        _state.settings.copyWith(
          reminderEnabled: false,
          reminderHour: hour,
          reminderMinute: minute,
        ),
      );
      return {
        'permissionGranted': false,
        'enabled': false,
        'hour': hour,
        'minute': minute,
        'scheduled': false,
        'reason': 'permission_required',
      };
    }
    final result = await _gateway.scheduleReminder(
      hour: hour,
      minute: minute,
      enabled: enabled,
    );
    final scheduled = result['scheduled'] != false;
    final effectiveEnabled = enabled && scheduled;
    await updateSettings(
      _state.settings.copyWith(
        reminderEnabled: effectiveEnabled,
        reminderHour: hour,
        reminderMinute: minute,
      ),
    );
    return {
      ...result,
      'permissionGranted': permissionGranted,
      'enabled': effectiveEnabled,
      'hour': hour,
      'minute': minute,
      'scheduled': scheduled,
    };
  }

  void _markCheckIntent(String outingId, String itemId) {
    final key = _ItemCheckKey(outingId, itemId);
    _checkGenerations[key] = (_checkGenerations[key] ?? 0) + 1;
  }

  void _markLifecycleIntent(String outingId) {
    _lifecycleGenerations[outingId] =
        (_lifecycleGenerations[outingId] ?? 0) + 1;
  }

  void _pruneRemovedCheckIntents(Outing before, Outing after) {
    final retained = after.items.map((item) => item.id).toSet();
    final removed = before.items
        .where((item) => !retained.contains(item.id))
        .map((item) => _ItemCheckKey(before.id, item.id));
    for (final key in removed) {
      _checkGenerations.remove(key);
      _ackedCheckGenerations.remove(key);
    }
  }

  bool _containsItem(AppState state, _ItemCheckKey key) => state.outings
      .where((outing) => outing.id == key.outingId)
      .any((outing) => outing.items.any((item) => item.id == key.itemId));

  bool _containsOuting(AppState state, String outingId) =>
      state.outings.any((outing) => outing.id == outingId);

  int _blueprintIndex(String id) {
    final index = _state.blueprints.indexWhere(
      (blueprint) => blueprint.id == id,
    );
    if (index < 0) throw StateError('Checklist not found');
    return index;
  }

  int _outingIndex(String id) {
    final index = _state.outings.indexWhere((outing) => outing.id == id);
    if (index < 0) throw StateError('Outing not found');
    return index;
  }

  String _newId() {
    final ids = <String>{
      for (final blueprint in _state.blueprints) ...[
        blueprint.id,
        ...blueprint.items.map((item) => item.id),
      ],
      for (final extra in _state.extras) extra.id,
      for (final schedule in _state.schedules) schedule.id,
      for (final outing in _state.outings) ...[
        outing.id,
        ...outing.items.map((item) => item.id),
      ],
    };
    for (var attempt = 0; attempt < 20; attempt++) {
      final id = _idFactory();
      if (id.trim().isNotEmpty && !ids.contains(id)) return id;
    }
    throw StateError('ID factory returned duplicate identifiers');
  }

  void _requireReady() {
    if (!_isReady) throw StateError('Initialize the controller first');
  }

  void _requireWritable() {
    _requireReady();
    if (_loadError != null) {
      throw StateError(
        'Saved data could not be loaded. Retry loading or explicitly start fresh.',
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gateway.setLaunchActionHandler(null);
    super.dispose();
  }
}

List<T> _reorder<T>(List<T> source, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= source.length) {
    throw RangeError.index(oldIndex, source, 'oldIndex');
  }
  final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
  if (adjustedNewIndex < 0 || adjustedNewIndex > source.length - 1) {
    throw RangeError.index(newIndex, source, 'newIndex');
  }
  final items = [...source];
  final item = items.removeAt(oldIndex);
  items.insert(adjustedNewIndex, item);
  return items;
}

class _StateEnvelope {
  const _StateEnvelope(
    this.state,
    this.epoch,
    this.nativeRevision,
    this.rejectedFinishIds,
  );

  final AppState state;
  final String epoch;
  final int nativeRevision;
  final Set<String> rejectedFinishIds;
}

class _SnapshotResult {
  const _SnapshotResult({
    this.canonicalState,
    this.rejectedFinishIds = const {},
    this.error,
  });

  final AppState? canonicalState;
  final Set<String> rejectedFinishIds;
  final Object? error;
}

class _CapturedIntent {
  const _CapturedIntent({required this.generation, required this.value});

  final int generation;
  final bool value;
}

class _CapturedLifecycle {
  const _CapturedLifecycle({
    required this.generation,
    required this.completedAt,
    required this.dismissedAtUTC,
  });

  final int generation;
  final DateTime? completedAt;
  final DateTime? dismissedAtUTC;
}

class _ItemCheckKey {
  const _ItemCheckKey(this.outingId, this.itemId);

  final String outingId;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is _ItemCheckKey &&
      other.outingId == outingId &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(outingId, itemId);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

String _requireLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(label, 'label', 'Cannot be empty');
  }
  return trimmed;
}

String _randomId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
