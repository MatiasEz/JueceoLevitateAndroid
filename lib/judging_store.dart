import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'supabase_api.dart';

enum SyncState { localOnly, connecting, online, syncing, pending, offline }

const bundledAppDataAsset = 'assets/data/app_data.json';
const androidAdminUserEnabled = false;
const androidAdminJudgeIds = {'admin', 'ati'};
const feedbackMaxLength = 350;
const _legacyScoresKey = 'scores';
const _legacyFeedbackKey = 'feedback';
const _legacyPenaltiesKey = 'penalties';
const _legacyFavoriteSelectionsKey = 'favoriteSelections';
const _scoresPendingKey = 'scores.pending.v2';
const _feedbackPendingKey = 'feedback.pending.v2';
const _penaltiesPendingKey = 'penalties.pending.v2';
const _favoriteSelectionsPendingKey = 'favoriteSelections.pending.v2';
const _deviceIDKey = 'deviceId.v1';

void _loadLog(String message) {
  if (kDebugMode) {
    debugPrint('[LevitateLoad] $message');
  }
}

class ExcelImportSummary {
  ExcelImportSummary({
    required this.fileName,
    required this.eventName,
    required this.eventSlug,
    required this.fileSize,
  });

  final String fileName;
  final String eventName;
  final String eventSlug;
  final int fileSize;
}

class JudgingStore extends ChangeNotifier {
  JudgingStore(this.api);

  final SupabaseApi api;
  SharedPreferences? _prefs;

  List<EventSummary> events = [];
  EventSummary? selectedEvent;
  AppData? appData;
  Map<String, List<DanceBlock>> programBlocksByEventId = {};
  String selectedJudge = '';
  String selectedRoutineId = '';
  String? selectedBlockId;
  String? adminScoringJudge;
  SyncState syncState = SyncState.localOnly;
  String syncMessage = '';
  final Map<String, double> scores = {};
  final Map<String, String> feedback = {};
  final Map<String, double> penalties = {};
  final Map<String, String> favoriteSelections = {};
  final Set<String> pendingScoreKeys = {};
  final Set<String> pendingFeedbackKeys = {};
  final Set<String> pendingPenaltyKeys = {};
  final Set<String> pendingFavoriteKeys = {};
  bool _syncInProgress = false;
  bool _syncRequested = false;
  String _deviceID = 'android-tablet';

  int get pendingCount =>
      pendingScoreKeys.length +
      pendingFeedbackKeys.length +
      pendingPenaltyKeys.length +
      pendingFavoriteKeys.length;
  List<Routine> get routines => appData?.routines ?? const [];
  List<DanceBlock> get blocks => appData?.blocks ?? const [];
  List<String> get judges {
    final source = appData?.judges ?? const <String>[];
    if (androidAdminUserEnabled) return source;
    return source.where((judge) => !_isAdminJudge(judge)).toList();
  }

  List<String> get editableJudges =>
      judges.where((judge) => roleFor(judge) == UserRole.judge).toList();
  bool get isAdmin =>
      androidAdminUserEnabled && roleFor(selectedJudge) == UserRole.admin;
  bool get isAdminEditingAsJudge =>
      isAdmin &&
      adminScoringJudge != null &&
      adminScoringJudge != selectedJudge;
  bool get isLoadingBackendData =>
      api.isConfigured && syncState == SyncState.connecting;
  String get scoringJudge =>
      isAdmin ? (adminScoringJudge ?? selectedJudge) : selectedJudge;
  List<EventSummary> get availablePrograms {
    if (events.isNotEmpty) return events;
    final sourceName = selectedEvent?.name ?? appData?.sourceName ?? 'Programa';
    return [
      EventSummary(
        id: selectedEvent?.id ?? stableRemoteId(sourceName),
        slug: stableRemoteId(sourceName),
        name: sourceName,
        sourceName: sourceName,
        isActive: true,
      ),
    ];
  }

  DanceBlock? get selectedBlock {
    if (blocks.isEmpty) return null;
    if (selectedBlockId != null) {
      for (final block in blocks) {
        if (block.blockId == selectedBlockId || block.name == selectedBlockId) {
          return block;
        }
      }
    }
    for (final block in blocks) {
      if (block.isActive) return block;
    }
    return blocks.first;
  }

  List<Routine> get visibleRoutines {
    final block = selectedBlock;
    if (block == null) return routines;
    final routineIds = block.routines.map((routine) => routine.id).toSet();
    final visible = routines.where((routine) {
      return routineIds.contains(routine.id) ||
          routine.blockId == block.blockId ||
          routine.block == block.name;
    }).toList();
    return visible.isEmpty ? routines : visible;
  }

  List<DanceBlock> blocksForProgram(EventSummary event) {
    if (events.isEmpty || selectedEvent?.id == event.id) return blocks;
    return programBlocksByEventId[event.id] ?? const [];
  }

  Routine? get selectedRoutine {
    final source = visibleRoutines.isEmpty ? routines : visibleRoutines;
    if (source.isEmpty) return null;
    return source.firstWhere(
      (routine) => routine.id == selectedRoutineId,
      orElse: () => source.first,
    );
  }

  List<FavoriteSelectionSummary> get favoriteSummaries {
    final currentEventKey =
        selectedEvent?.id ?? stableRemoteId(appData?.sourceName ?? '');
    final routinesByID = {for (final routine in routines) routine.id: routine};
    final summaries = <FavoriteSelectionSummary>[];
    final seenSelections = <String>{};
    for (final entry in favoriteSelections.entries) {
      final parsed = _parseFavoriteKey(entry.key);
      final routineId = parsed?.routineId ?? entry.value;
      final routine = routinesByID[routineId];
      if (parsed == null ||
          parsed.eventId != currentEventKey ||
          routine == null) {
        continue;
      }
      final selectionId =
          '${parsed.eventId}::${parsed.blockId}::${parsed.judgeKey}::${parsed.category.id}::${routine.id}';
      if (!seenSelections.add(selectionId)) continue;
      summaries.add(FavoriteSelectionSummary(
        id: selectionId,
        category: parsed.category,
        judge: _judgeNameForKey(parsed.judgeKey) ?? parsed.judgeKey,
        blockName: _blockNameFor(parsed.blockId),
        routine: routine,
      ));
    }
    summaries.sort((left, right) {
      final blockCompare = _blockSortOrder(left.blockName)
          .compareTo(_blockSortOrder(right.blockName));
      if (blockCompare != 0) return blockCompare;
      final categoryCompare = FavoriteCategory.values
          .indexOf(left.category)
          .compareTo(FavoriteCategory.values.indexOf(right.category));
      if (categoryCompare != 0) return categoryCompare;
      final judgeCompare = left.judge.compareTo(right.judge);
      if (judgeCompare != 0) return judgeCompare;
      return (int.tryParse(left.routine.id) ?? 1 << 30)
          .compareTo(int.tryParse(right.routine.id) ?? 1 << 30);
    });
    return summaries;
  }

  List<FavoriteRankingBlock> get favoriteRankingBlocks {
    final groupedByBlock = <String, List<FavoriteSelectionSummary>>{};
    for (final favorite in favoriteSummaries) {
      groupedByBlock.putIfAbsent(favorite.blockName, () => []).add(favorite);
    }

    final blocks = groupedByBlock.entries
        .map((blockEntry) {
          final categories = FavoriteCategory.values.map((category) {
            final favoritesForCategory = blockEntry.value
                .where((favorite) => favorite.category == category)
                .toList();
            final groupedByRoutine = <String, List<FavoriteSelectionSummary>>{};
            for (final favorite in favoritesForCategory) {
              groupedByRoutine
                  .putIfAbsent(favorite.routine.id, () => [])
                  .add(favorite);
            }
            final ranked = groupedByRoutine.entries.map((entry) {
              final first = entry.value.first;
              final judges = entry.value
                  .map((favorite) => favorite.judge)
                  .toSet()
                  .toList()
                ..sort((left, right) => left.compareTo(right));
              return (
                routine: first.routine,
                votes: judges.length,
                judges: judges,
              );
            }).toList()
              ..sort((left, right) {
                final voteCompare = right.votes.compareTo(left.votes);
                if (voteCompare != 0) return voteCompare;
                return _routineOrder(left.routine, right.routine);
              });
            final items = ranked.take(3).indexed.map((entry) {
              final item = entry.$2;
              return FavoriteRankingItem(
                id: '${blockEntry.key}::${category.id}::${item.routine.id}',
                rank: entry.$1 + 1,
                category: category,
                blockName: blockEntry.key,
                routine: item.routine,
                votes: item.votes,
                judges: item.judges,
              );
            }).toList();
            return FavoriteCategoryRanking(category: category, items: items);
          }).toList();
          return FavoriteRankingBlock(
            blockName: blockEntry.key,
            categories: categories,
          );
        })
        .where((block) => block.totalVotes > 0)
        .toList();

    blocks.sort((left, right) {
      final blockCompare = _blockSortOrder(left.blockName)
          .compareTo(_blockSortOrder(right.blockName));
      if (blockCompare != 0) return blockCompare;
      return left.blockName.compareTo(right.blockName);
    });
    return blocks;
  }

  Future<void> initialize() async {
    final watch = Stopwatch()..start();
    _prefs = await SharedPreferences.getInstance();
    _deviceID = _prefs?.getString(_deviceIDKey) ?? _createDeviceID();
    await _prefs?.setString(_deviceIDKey, _deviceID);
    selectedJudge = _prefs?.getString('selectedJudge') ?? '';
    selectedRoutineId = _prefs?.getString('selectedRoutineId') ?? '';
    selectedBlockId = _prefs?.getString('selectedBlockId');
    pendingScoreKeys
        .addAll(_prefs?.getStringList('pendingScoreKeys') ?? const []);
    pendingFeedbackKeys
        .addAll(_prefs?.getStringList('pendingFeedbackKeys') ?? const []);
    pendingPenaltyKeys
        .addAll(_prefs?.getStringList('pendingPenaltyKeys') ?? const []);
    pendingFavoriteKeys
        .addAll(_prefs?.getStringList('pendingFavoriteKeys') ?? const []);
    if (api.isConfigured) {
      scores.addAll(
          await _loadPendingDoubleMap(_scoresPendingKey, pendingScoreKeys));
      feedback.addAll(await _loadPendingStringMap(
          _feedbackPendingKey, pendingFeedbackKeys));
      penalties.addAll(await _loadPendingDoubleMap(
          _penaltiesPendingKey, pendingPenaltyKeys));
      favoriteSelections.addAll(await _loadPendingStringMap(
          _favoriteSelectionsPendingKey, pendingFavoriteKeys));
      _recoverPendingValuesFromLegacyCacheIfNeeded();
      _retainPendingLocalCacheOnly();
      await _clearLegacyRemoteCache();
      await _persistAll();
    } else {
      scores.addAll(_decodeDoubleMap(_prefs?.getString(_scoresPendingKey) ??
          _prefs?.getString(_legacyScoresKey) ??
          '{}'));
      feedback.addAll(_decodeStringMap(_prefs?.getString(_feedbackPendingKey) ??
          _prefs?.getString(_legacyFeedbackKey) ??
          '{}'));
      penalties.addAll(_decodeDoubleMap(
          _prefs?.getString(_penaltiesPendingKey) ??
              _prefs?.getString(_legacyPenaltiesKey) ??
              '{}'));
      favoriteSelections.addAll(_decodeStringMap(
          _prefs?.getString(_favoriteSelectionsPendingKey) ??
              _prefs?.getString(_legacyFavoriteSelectionsKey) ??
              '{}'));
    }
    _loadLog(
        'initialize localScores=${scores.length} localFeedback=${feedback.length} localPenalties=${penalties.length} localFavorites=${favoriteSelections.length} pending=$pendingCount remoteConfigured=${api.isConfigured} elapsed=${watch.elapsedMilliseconds}ms');

    await _loadBundledAppData();
    _normalizeCurrentSelection();

    if (!api.isConfigured) {
      syncState = SyncState.localOnly;
      syncMessage = appData == null || routines.isEmpty
          ? 'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY con --dart-define.'
          : 'Modo local con datos embebidos.';
      notifyListeners();
      return;
    }
    await refreshEvents();
  }

  Future<void> refreshEvents() async {
    syncState = SyncState.connecting;
    syncMessage = 'Buscando eventos en Supabase...';
    notifyListeners();
    try {
      events = await api.fetchEvents();
      programBlocksByEventId = await api.fetchEventBlocks();
      selectedEvent = events.firstWhere(
        (event) => event.id == _prefs?.getString('selectedEventId'),
        orElse: () => events.firstWhere(
          (event) => event.isActive,
          orElse: () => events.isEmpty
              ? EventSummary(
                  id: '', slug: '', name: '', sourceName: '', isActive: false)
              : events.first,
        ),
      );
      if (selectedEvent == null || selectedEvent!.id.isEmpty) {
        syncState = SyncState.offline;
        syncMessage = 'No hay eventos en Supabase.';
        notifyListeners();
        return;
      }
      await selectEvent(selectedEvent!);
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> selectEvent(EventSummary event) async {
    final watch = Stopwatch()..start();
    selectedEvent = event;
    await _prefs?.setString('selectedEventId', event.id);
    syncState = SyncState.connecting;
    syncMessage = 'Cargando ${event.name} desde Supabase...';
    notifyListeners();
    _loadLog('selectEvent started id=${event.id} name="${event.name}"');
    try {
      final bundle = await api.fetchBundle(event);
      _loadLog(
          'selectEvent fetched bundle scores=${bundle.scores.length} feedback=${bundle.feedback.length} penalties=${bundle.penalties.length} favorites=${bundle.favorites.length} elapsed=${watch.elapsedMilliseconds}ms');
      appData = bundle.appData;
      programBlocksByEventId = {
        ...programBlocksByEventId,
        event.id: bundle.appData.blocks,
      };
      _normalizeCurrentSelection();
      final judgeById = {
        for (final judge in judges) stableRemoteId(judge): judge
      };
      _pruneSyncedInMemoryCache();
      var appliedScores = 0;
      var skippedPendingScores = 0;
      for (final remoteScore in bundle.scores) {
        final judge = judgeById[remoteScore.judgeId];
        if (judge == null) continue;
        final key =
            scoreKey(remoteScore.routineId, judge, remoteScore.criterionId);
        if (!pendingScoreKeys.contains(key)) {
          scores[key] = remoteScore.value;
          appliedScores += 1;
        } else {
          skippedPendingScores += 1;
        }
      }
      var appliedFeedback = 0;
      var skippedPendingFeedback = 0;
      for (final remoteFeedback in bundle.feedback) {
        final judge = judgeById[remoteFeedback.judgeId];
        if (judge == null) continue;
        final key = feedbackKey(remoteFeedback.routineId, judge);
        if (!pendingFeedbackKeys.contains(key)) {
          feedback[key] = remoteFeedback.body;
          appliedFeedback += 1;
        } else {
          skippedPendingFeedback += 1;
        }
      }
      var appliedPenalties = 0;
      var skippedPendingPenalties = 0;
      for (final remotePenalty in bundle.penalties) {
        final judge = judgeById[remotePenalty.judgeId];
        if (judge == null) continue;
        final key = penaltyKey(remotePenalty.routineId, judge);
        if (!pendingPenaltyKeys.contains(key)) {
          penalties[key] = remotePenalty.value.clamp(-100, 0).toDouble();
          appliedPenalties += 1;
        } else {
          skippedPendingPenalties += 1;
        }
      }
      final eventPrefix = '${event.id}::';
      final staleFavoriteKeys = favoriteSelections.keys.where((key) {
        return key.startsWith(eventPrefix) &&
            !pendingFavoriteKeys.contains(key);
      }).toList();
      for (final key in staleFavoriteKeys) {
        favoriteSelections.remove(key);
      }
      for (final remoteFavorite in bundle.favorites) {
        final judge = judgeById[remoteFavorite.judgeId];
        if (judge == null) continue;
        final key = favoriteKey(
          remoteFavorite.category,
          judge: judge,
          eventId: remoteFavorite.eventId,
          blockId: remoteFavorite.blockId,
          routineId: remoteFavorite.routineId,
        );
        final legacyKey = favoriteKey(
          remoteFavorite.category,
          judge: judge,
          eventId: remoteFavorite.eventId,
          blockId: remoteFavorite.blockId,
        );
        if (!pendingFavoriteKeys.contains(key) &&
            !pendingFavoriteKeys.contains(legacyKey)) {
          favoriteSelections[key] = remoteFavorite.routineId;
        }
      }
      await _persistAll();
      _loadLog(
          'selectEvent applied scores=$appliedScores skippedScores=$skippedPendingScores feedback=$appliedFeedback skippedFeedback=$skippedPendingFeedback penalties=$appliedPenalties skippedPenalties=$skippedPendingPenalties localScores=${scores.length} elapsed=${watch.elapsedMilliseconds}ms');
      await syncPending();
      await reportHome();
      _loadLog(
          'selectEvent finished pending=$pendingCount elapsed=${watch.elapsedMilliseconds}ms');
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      _loadLog(
          'selectEvent failed elapsed=${watch.elapsedMilliseconds}ms error=$error');
      notifyListeners();
    }
  }

  JudgingTemplate templateFor(Routine routine) {
    final templates = appData?.templates ?? const <JudgingTemplate>[];
    for (final template in templates) {
      if (normalizedKey(template.genre) == normalizedKey(routine.genre)) {
        return template;
      }
    }
    if (ObligatoryChecklist.isAerialApparatusGenre(routine.genre)) {
      for (final template in templates) {
        if (normalizedKey(template.genre) == 'DANZA AEREA') {
          return template;
        }
      }
    }
    return templates.isEmpty
        ? JudgingTemplate(
            templateId: 'general',
            genre: 'General',
            title: 'Hoja de jueceo',
            maxScore: 0,
            criteria: const [])
        : templates.first;
  }

  String scoreKey(String routineId, String judge, int criterionId) {
    return '$routineId::${normalizedKey(judge)}::$criterionId';
  }

  String feedbackKey(String routineId, String judge) {
    return '$routineId::${normalizedKey(judge)}';
  }

  String penaltyKey(String routineId, String judge) {
    return '$routineId::${normalizedKey(judge)}';
  }

  String favoriteKey(
    FavoriteCategory category, {
    String? judge,
    String? eventId,
    String? blockId,
    String? routineId,
  }) {
    final eventKey = eventId ??
        selectedEvent?.id ??
        stableRemoteId(appData?.sourceName ?? '');
    final blockKey = blockId ?? selectedBlock?.blockId ?? 'sin-bloque';
    final baseKey =
        '$eventKey::$blockKey::${normalizedKey(judge ?? scoringJudge)}::${category.id}';
    final cleanRoutineId = routineId?.trim() ?? '';
    return cleanRoutineId.isEmpty ? baseKey : '$baseKey::$cleanRoutineId';
  }

  double scoreFor(Routine routine, String judge, Criterion criterion) {
    return scores[scoreKey(routine.id, judge, criterion.id)] ?? 0;
  }

  double penaltyFor(Routine routine, String judge) {
    return penalties[penaltyKey(routine.id, judge)] ?? 0;
  }

  bool isFavorite(Routine routine, FavoriteCategory category, {String? judge}) {
    final key = favoriteKey(category, judge: judge, routineId: routine.id);
    final legacyKey = favoriteKey(category, judge: judge);
    return favoriteSelections.containsKey(key) ||
        favoriteSelections[legacyKey] == routine.id;
  }

  bool hasFavorite(Routine routine, {String? judge}) {
    for (final category in FavoriteCategory.values) {
      if (isFavorite(routine, category, judge: judge)) return true;
    }
    return false;
  }

  Future<void> toggleFavorite(FavoriteCategory category, Routine routine,
      {String? judge}) async {
    final key = favoriteKey(category, judge: judge, routineId: routine.id);
    final legacyKey = favoriteKey(category, judge: judge);
    if (favoriteSelections.containsKey(key)) {
      favoriteSelections.remove(key);
      pendingFavoriteKeys.add(key);
    } else if (favoriteSelections[legacyKey] == routine.id) {
      favoriteSelections.remove(legacyKey);
      pendingFavoriteKeys.remove(legacyKey);
      pendingFavoriteKeys.add(key);
    } else {
      favoriteSelections[key] = routine.id;
      pendingFavoriteKeys.add(key);
    }
    await _persistAll();
    syncState = SyncState.pending;
    notifyListeners();
    await syncPending();
  }

  void selectJudge(String judge) {
    if (!judges.contains(judge)) return;
    selectedJudge = judge;
    if (roleFor(judge) != UserRole.admin) {
      adminScoringJudge = null;
    }
    _prefs?.setString('selectedJudge', judge);
    notifyListeners();
    unawaited(reportHome());
  }

  void addJudge(String name) {
    final cleanName = name.trim().toUpperCase();
    if (cleanName.isEmpty || judges.contains(cleanName) || appData == null) {
      return;
    }
    appData!.judges.add(cleanName);
    appData!.judgeProfiles.add(JudgeProfile(
      judgeId: stableRemoteId(cleanName),
      name: cleanName,
      role: androidAdminUserEnabled &&
              androidAdminJudgeIds.contains(stableRemoteId(cleanName))
          ? UserRole.admin
          : UserRole.judge,
    ));
    selectJudge(cleanName);
  }

  JudgeProfile? judgeProfileFor(String judge) {
    final judgeId = stableRemoteId(judge);
    final judgeKey = normalizedKey(judge);
    final profiles = appData?.judgeProfiles ?? const <JudgeProfile>[];
    for (final profile in profiles) {
      final matchesProfile = profile.judgeId == judgeId ||
          stableRemoteId(profile.judgeId) == judgeId ||
          normalizedKey(profile.name) == judgeKey;
      if (matchesProfile) return profile;
    }
    return null;
  }

  String? heroImageNameFor(String judge) {
    final heroImageName = judgeProfileFor(judge)?.heroImageName?.trim();
    return heroImageName == null || heroImageName.isEmpty
        ? null
        : heroImageName;
  }

  String? judgePhotoDataFor(String judge) {
    final photoData = judgeProfileFor(judge)?.photoData?.trim();
    return photoData == null || photoData.isEmpty ? null : photoData;
  }

  UserRole roleFor(String judge) {
    if (!androidAdminUserEnabled) return UserRole.judge;
    final judgeId = stableRemoteId(judge);
    if (androidAdminJudgeIds.contains(judgeId)) return UserRole.admin;
    final profiles = appData?.judgeProfiles ?? const <JudgeProfile>[];
    for (final profile in profiles) {
      if (profile.judgeId == judgeId ||
          normalizedKey(profile.name) == normalizedKey(judge)) {
        return profile.role;
      }
    }
    return UserRole.judge;
  }

  String roleTitleFor(String judge) {
    return roleFor(judge) == UserRole.admin ? 'Admin' : 'Juez';
  }

  void selectBlock(DanceBlock block) {
    selectedBlockId = block.blockId;
    _prefs?.setString('selectedBlockId', block.blockId);
    final nextRoutine = block.routines.isNotEmpty
        ? block.routines.first
        : routines.firstWhere(
            (routine) =>
                routine.blockId == block.blockId || routine.block == block.name,
            orElse: () => routines.isEmpty
                ? Routine(
                    id: '',
                    blockId: '',
                    block: '',
                    name: '',
                    academy: '',
                    division: '',
                    genre: '',
                    level: '',
                    category: '',
                    choreographer: '',
                    participant: '',
                    state: '',
                    time: '',
                    duration: '',
                  )
                : routines.first,
          );
    if (nextRoutine.id.isNotEmpty) {
      selectRoutine(nextRoutine.id, notify: false);
    }
    notifyListeners();
  }

  Future<void> selectProgramBlock(EventSummary event, DanceBlock? block) async {
    final shouldLoadEvent =
        api.isConfigured && events.isNotEmpty && selectedEvent?.id != event.id;
    if (shouldLoadEvent) {
      await selectEvent(event);
    }

    if (block == null) return;
    final targetBlock = blocks.firstWhere(
      (item) => item.blockId == block.blockId || item.name == block.name,
      orElse: () => block,
    );
    selectBlock(targetBlock);
  }

  void selectRoutine(String routineId, {bool notify = true}) {
    selectedRoutineId = routineId;
    _prefs?.setString('selectedRoutineId', routineId);
    if (notify) notifyListeners();
  }

  Future<void> reportHome() async {
    await _reportJudgeActivity(state: 'home');
  }

  Future<void> reportEnteredSheet(Routine routine) async {
    await _reportJudgeActivity(state: 'viewing_sheet', routine: routine);
  }

  Future<void> reportLeftSheet(Routine routine) async {
    await _reportJudgeActivity(state: 'left_sheet', routine: routine);
  }

  Future<void> _reportJudgeActivity({
    required String state,
    Routine? routine,
  }) async {
    final event = selectedEvent;
    if (!api.isConfigured ||
        event == null ||
        event.id.isEmpty ||
        selectedJudge.isEmpty ||
        roleFor(selectedJudge) != UserRole.judge) {
      return;
    }

    try {
      await api.upsertJudgeActivity({
        'event_id': event.id,
        'judge_id': stableRemoteId(selectedJudge),
        'device_id': _deviceID,
        'state': state,
        'block_id': routine == null ? null : _blockIdForRoutine(routine.id),
        'routine_id': routine?.id,
        'platform': 'Android',
      });
    } catch (error) {
      _loadLog('reportJudgeActivity failed state=$state error=$error');
    }
  }

  void beginAdminScoring({required String judge, required Routine routine}) {
    if (!isAdmin ||
        !judges.contains(judge) ||
        roleFor(judge) != UserRole.judge) {
      return;
    }
    adminScoringJudge = judge;
    selectedRoutineId = routine.id;
    final block = _blockContaining(routine);
    if (block != null) {
      selectedBlockId = block.blockId;
      _prefs?.setString('selectedBlockId', block.blockId);
    }
    _prefs?.setString('selectedRoutineId', routine.id);
    notifyListeners();
  }

  void clearAdminScoringOverride() {
    adminScoringJudge = null;
    notifyListeners();
  }

  Future<void> submitScores(
    Routine routine,
    Map<int, double> values, {
    String? judge,
    double? penalty,
  }) async {
    final activeJudge = judge ?? scoringJudge;
    final template = templateFor(routine);
    final maxByCriterion = {
      for (final criterion in template.criteria)
        criterion.id: criterion.maxScore
    };
    for (final entry in values.entries) {
      final maxScore = maxByCriterion[entry.key] ?? 10;
      final key = scoreKey(routine.id, activeJudge, entry.key);
      scores[key] = entry.value.clamp(0, maxScore).toDouble();
      pendingScoreKeys.add(key);
    }
    if (penalty != null) {
      final key = penaltyKey(routine.id, activeJudge);
      penalties[key] = penalty.clamp(-100, 0).toDouble();
      pendingPenaltyKeys.add(key);
    }
    await _persistAll();
    syncState = SyncState.pending;
    notifyListeners();
    await syncPending();
  }

  Future<void> setFeedback(Routine routine, String body,
      {String? judge}) async {
    final activeJudge = judge ?? scoringJudge;
    final key = feedbackKey(routine.id, activeJudge);
    feedback[key] = body.length > feedbackMaxLength
        ? body.substring(0, feedbackMaxLength)
        : body;
    pendingFeedbackKeys.add(key);
    await _persistAll();
    syncState = SyncState.pending;
    notifyListeners();
    await syncPending();
  }

  Future<ExcelImportSummary> uploadExcelImport({
    required String fileName,
    required Uint8List bytes,
    required String eventName,
    required String eventSlug,
  }) async {
    if (!api.isConfigured) {
      throw StateError('Supabase no está configurado.');
    }
    if (bytes.isEmpty) {
      throw StateError('No se pudo leer el Excel seleccionado.');
    }
    const maxBytes = 20 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw StateError('El archivo supera el máximo de 20 MB.');
    }
    final cleanEventName = eventName.trim();
    final cleanSlug = stableRemoteId(eventSlug);
    final summary = ExcelImportSummary(
      fileName: fileName,
      eventName: cleanEventName,
      eventSlug: cleanSlug,
      fileSize: bytes.length,
    );
    syncState = SyncState.syncing;
    syncMessage = 'Subiendo $fileName...';
    notifyListeners();
    await api.uploadExcelImport({
      'event_slug': cleanSlug,
      'event_name': cleanEventName,
      'filename': fileName,
      'file_size': bytes.length,
      'payload_base64': base64Encode(bytes),
      'device_id': 'android-tablet',
    });
    syncState = SyncState.online;
    syncMessage = 'Excel subido: $cleanEventName.';
    notifyListeners();
    return summary;
  }

  Future<void> syncPending() async {
    if (_syncInProgress) {
      _syncRequested = true;
      return;
    }
    _syncInProgress = true;
    try {
      do {
        _syncRequested = false;
        await _syncPendingOnce();
      } while (_syncRequested);
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _syncPendingOnce() async {
    if (!api.isConfigured || selectedEvent == null) {
      syncState = api.isConfigured ? SyncState.pending : SyncState.localOnly;
      notifyListeners();
      return;
    }
    if (pendingCount == 0) {
      syncState = SyncState.online;
      syncMessage = 'Datos sincronizados.';
      notifyListeners();
      return;
    }
    syncState = SyncState.syncing;
    notifyListeners();
    try {
      final eventID = selectedEvent!.id;
      final scoreKeys = Set<String>.from(pendingScoreKeys);
      final sentScoreValues = <String, double>{};
      final scoreRows = <Map<String, dynamic>>[];
      for (final key in scoreKeys) {
        final parts = key.split('::');
        if (parts.length != 3) {
          pendingScoreKeys.remove(key);
          continue;
        }
        final routineId = parts[0];
        final value = scores[key] ?? 0;
        sentScoreValues[key] = value;
        scoreRows.add({
          'event_id': eventID,
          'block_id': _blockIdForRoutine(routineId),
          'routine_id': routineId,
          'judge_id': stableRemoteId(parts[1]),
          'criterion_id': int.tryParse(parts[2]) ?? 0,
          'value': value,
          'device_id': _deviceID,
        });
      }
      await api.upsertScores(eventID, scoreRows);
      for (final key in scoreKeys) {
        if ((scores[key] ?? 0) == sentScoreValues[key]) {
          pendingScoreKeys.remove(key);
        }
      }

      final feedbackKeys = Set<String>.from(pendingFeedbackKeys);
      final sentFeedbackValues = <String, String>{};
      final feedbackRows = <Map<String, dynamic>>[];
      for (final key in feedbackKeys) {
        final parts = key.split('::');
        if (parts.length != 2) {
          pendingFeedbackKeys.remove(key);
          continue;
        }
        final routineId = parts[0];
        final body = feedback[key] ?? '';
        sentFeedbackValues[key] = body;
        feedbackRows.add({
          'event_id': eventID,
          'block_id': _blockIdForRoutine(routineId),
          'routine_id': routineId,
          'judge_id': stableRemoteId(parts[1]),
          'body': body,
          'device_id': _deviceID,
        });
      }
      await api.upsertFeedback(eventID, feedbackRows);
      for (final key in feedbackKeys) {
        if ((feedback[key] ?? '') == sentFeedbackValues[key]) {
          pendingFeedbackKeys.remove(key);
        }
      }

      final penaltyKeys = Set<String>.from(pendingPenaltyKeys);
      final sentPenaltyValues = <String, double>{};
      final penaltyRows = <Map<String, dynamic>>[];
      for (final key in penaltyKeys) {
        final parts = key.split('::');
        if (parts.length != 2) {
          pendingPenaltyKeys.remove(key);
          continue;
        }
        final routineId = parts[0];
        final value = penalties[key] ?? 0;
        sentPenaltyValues[key] = value;
        penaltyRows.add({
          'event_id': eventID,
          'block_id': _blockIdForRoutine(routineId),
          'routine_id': routineId,
          'judge_id': stableRemoteId(parts[1]),
          'value': value,
          'device_id': _deviceID,
        });
      }
      await api.upsertPenalties(eventID, penaltyRows);
      for (final key in penaltyKeys) {
        if ((penalties[key] ?? 0) == sentPenaltyValues[key]) {
          pendingPenaltyKeys.remove(key);
        }
      }

      final favoriteKeys = Set<String>.from(pendingFavoriteKeys);
      final sentFavoriteValues = <String, String?>{};
      final favoriteUpsertRows = <Map<String, dynamic>>[];
      final favoriteDeleteRows = <Map<String, dynamic>>[];
      for (final key in favoriteKeys) {
        final parsed = _parseFavoriteKey(key);
        if (parsed == null) {
          pendingFavoriteKeys.remove(key);
          continue;
        }
        final judgeName = _judgeNameForKey(parsed.judgeKey);
        if (judgeName == null) {
          pendingFavoriteKeys.remove(key);
          continue;
        }
        final isSelected = favoriteSelections.containsKey(key);
        final selectedRoutine =
            isSelected ? (parsed.routineId ?? favoriteSelections[key]) : null;
        sentFavoriteValues[key] = selectedRoutine;
        if (!isSelected) {
          favoriteDeleteRows.add({
            'event_id': parsed.eventId,
            'block_id': parsed.blockId,
            if (parsed.routineId != null) 'routine_id': parsed.routineId,
            'judge_id': stableRemoteId(judgeName),
            'category': parsed.category.id,
          });
        } else {
          favoriteUpsertRows.add({
            'event_id': parsed.eventId,
            'block_id': parsed.blockId,
            'routine_id': selectedRoutine,
            'judge_id': stableRemoteId(judgeName),
            'category': parsed.category.id,
            'device_id': _deviceID,
          });
        }
      }
      await api.upsertFavorites(favoriteUpsertRows);
      await api.deleteFavorites(favoriteDeleteRows);
      for (final key in favoriteKeys) {
        if (favoriteSelections[key] == sentFavoriteValues[key]) {
          pendingFavoriteKeys.remove(key);
        }
      }
      await _persistAll();
      syncState = SyncState.online;
      syncMessage = 'Datos sincronizados.';
    } catch (error) {
      syncState = SyncState.pending;
      syncMessage = '$error';
    }
    notifyListeners();
  }

  List<RoutineResult> get rankings {
    final results = visibleRoutines.map(resultFor).toList();
    results.sort((left, right) {
      final totalCompare = right.aggregateTotal.compareTo(left.aggregateTotal);
      if (totalCompare != 0) return totalCompare;
      return _routineOrder(left.routine, right.routine);
    });
    return results;
  }

  RoutineResult resultFor(Routine routine) {
    final template = templateFor(routine);
    final totals = <String, double>{};
    final penaltyValues = <String, double>{};
    var submittedCount = 0;
    var finalSum = 0.0;
    var penaltyTotal = 0.0;
    for (final judge in judges) {
      final subtotal = template.criteria.fold<double>(
        0,
        (sum, criterion) => sum + scoreFor(routine, judge, criterion),
      );
      final penalty = penaltyFor(routine, judge);
      final finalTotal = subtotal > 0
          ? (subtotal + penalty).clamp(0, double.infinity).toDouble()
          : 0.0;
      totals[judge] = finalTotal;
      penaltyValues[judge] = penalty;
      if (subtotal > 0) {
        submittedCount += 1;
        finalSum += finalTotal;
        penaltyTotal += penalty;
      }
    }
    final total = submittedCount == 0 ? 0.0 : finalSum / submittedCount;
    final maxScore = template.maxScore > 0
        ? template.maxScore
        : template.criteria
            .fold<double>(0, (sum, criterion) => sum + criterion.maxScore);
    return RoutineResult(
      routine: routine,
      judgeTotals: totals,
      judgePenalties: penaltyValues,
      total: total,
      penalty: penaltyTotal,
      maxScore: maxScore,
    );
  }

  Future<void> _persistAll() async {
    await _setEncodedMap(_scoresPendingKey, _scoresForStorage());
    await _setEncodedMap(_feedbackPendingKey, _feedbackForStorage());
    await _setEncodedMap(_penaltiesPendingKey, _penaltiesForStorage());
    await _setEncodedMap(
        _favoriteSelectionsPendingKey, _favoriteSelectionsForStorage());
    await _prefs?.setStringList(
        'pendingScoreKeys', pendingScoreKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingFeedbackKeys', pendingFeedbackKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingPenaltyKeys', pendingPenaltyKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingFavoriteKeys', pendingFavoriteKeys.toList()..sort());
  }

  Future<void> _setEncodedMap(String key, Map<String, Object?> value) async {
    if (value.isEmpty) {
      await _prefs?.remove(key);
      return;
    }
    await _prefs?.setString(key, jsonEncode(value));
  }

  Future<Map<String, double>> _loadPendingDoubleMap(
    String storageKey,
    Set<String> pendingKeys,
  ) async {
    if (pendingKeys.isEmpty) {
      await _prefs?.remove(storageKey);
      return const {};
    }
    final raw = _prefs?.getString(storageKey);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = _decodeDoubleMap(raw);
    decoded.removeWhere((key, _) => !pendingKeys.contains(key));
    return decoded;
  }

  Future<Map<String, String>> _loadPendingStringMap(
    String storageKey,
    Set<String> pendingKeys,
  ) async {
    if (pendingKeys.isEmpty) {
      await _prefs?.remove(storageKey);
      return const {};
    }
    final raw = _prefs?.getString(storageKey);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = _decodeStringMap(raw);
    decoded.removeWhere((key, _) => !pendingKeys.contains(key));
    return decoded;
  }

  Map<String, double> _scoresForStorage() {
    return {
      for (final key in pendingScoreKeys)
        if (scores.containsKey(key)) key: scores[key]!,
    };
  }

  Map<String, String> _feedbackForStorage() {
    return {
      for (final key in pendingFeedbackKeys)
        if (feedback.containsKey(key)) key: feedback[key]!,
    };
  }

  Map<String, double> _penaltiesForStorage() {
    return {
      for (final key in pendingPenaltyKeys)
        if (penalties.containsKey(key)) key: penalties[key]!,
    };
  }

  Map<String, String> _favoriteSelectionsForStorage() {
    return {
      for (final key in pendingFavoriteKeys)
        if (favoriteSelections.containsKey(key)) key: favoriteSelections[key]!,
    };
  }

  void _pruneSyncedInMemoryCache() {
    scores.removeWhere((key, _) => !pendingScoreKeys.contains(key));
    feedback.removeWhere((key, _) => !pendingFeedbackKeys.contains(key));
    penalties.removeWhere((key, _) => !pendingPenaltyKeys.contains(key));
  }

  void _retainPendingLocalCacheOnly() {
    _pruneSyncedInMemoryCache();
    favoriteSelections
        .removeWhere((key, _) => !pendingFavoriteKeys.contains(key));
  }

  void _recoverPendingValuesFromLegacyCacheIfNeeded() {
    if (pendingScoreKeys.isNotEmpty && scores.isEmpty) {
      _loadLog('recovering pending scores from legacy SharedPreferences');
      scores.addAll(
          _decodeDoubleMap(_prefs?.getString(_legacyScoresKey) ?? '{}'));
    }
    if (pendingFeedbackKeys.isNotEmpty && feedback.isEmpty) {
      _loadLog('recovering pending feedback from legacy SharedPreferences');
      feedback.addAll(
          _decodeStringMap(_prefs?.getString(_legacyFeedbackKey) ?? '{}'));
    }
    if (pendingPenaltyKeys.isNotEmpty && penalties.isEmpty) {
      _loadLog('recovering pending penalties from legacy SharedPreferences');
      penalties.addAll(
          _decodeDoubleMap(_prefs?.getString(_legacyPenaltiesKey) ?? '{}'));
    }
    if (pendingFavoriteKeys.isNotEmpty && favoriteSelections.isEmpty) {
      _loadLog('recovering pending favorites from legacy SharedPreferences');
      favoriteSelections.addAll(_decodeStringMap(
          _prefs?.getString(_legacyFavoriteSelectionsKey) ?? '{}'));
    }
  }

  Future<void> _clearLegacyRemoteCache() async {
    await _prefs?.remove(_legacyScoresKey);
    await _prefs?.remove(_legacyFeedbackKey);
    await _prefs?.remove(_legacyPenaltiesKey);
    await _prefs?.remove(_legacyFavoriteSelectionsKey);
  }

  Future<void> _loadBundledAppData() async {
    try {
      final raw = await rootBundle.loadString(bundledAppDataAsset);
      appData = AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      appData ??= AppData(
        sourceName: 'Sin datos',
        blocks: const [],
        routines: const [],
        templates: const [],
        judges: const ['JUEZ'],
      );
    }
  }

  void _normalizeCurrentSelection() {
    if (!judges.contains(selectedJudge)) {
      String? adminJudge;
      for (final judge in judges) {
        if (roleFor(judge) == UserRole.admin) {
          adminJudge = judge;
          break;
        }
      }
      selectedJudge = adminJudge ?? (judges.isEmpty ? '' : judges.first);
      _prefs?.setString('selectedJudge', selectedJudge);
    }
    if (selectedBlockId == null ||
        !blocks.any((block) =>
            block.blockId == selectedBlockId ||
            block.name == selectedBlockId)) {
      DanceBlock? defaultBlock;
      for (final block in blocks) {
        if (block.isActive) {
          defaultBlock = block;
          break;
        }
      }
      defaultBlock ??= blocks.isEmpty ? null : blocks.first;
      selectedBlockId = defaultBlock?.blockId;
      if (selectedBlockId != null) {
        _prefs?.setString('selectedBlockId', selectedBlockId!);
      }
    }
    if (!visibleRoutines.any((routine) => routine.id == selectedRoutineId)) {
      selectedRoutineId = visibleRoutines.isNotEmpty
          ? visibleRoutines.first.id
          : (routines.isEmpty ? '' : routines.first.id);
      _prefs?.setString('selectedRoutineId', selectedRoutineId);
    }
    if (adminScoringJudge != null &&
        (!isAdmin ||
            !judges.contains(adminScoringJudge) ||
            roleFor(adminScoringJudge!) != UserRole.judge)) {
      adminScoringJudge = null;
    }
  }

  DanceBlock? _blockContaining(Routine routine) {
    for (final block in blocks) {
      final routineIds = block.routines.map((item) => item.id).toSet();
      if (routineIds.contains(routine.id) ||
          routine.blockId == block.blockId ||
          routine.block == block.name) {
        return block;
      }
    }
    return null;
  }

  ({
    String eventId,
    String blockId,
    String judgeKey,
    FavoriteCategory category,
    String? routineId
  })? _parseFavoriteKey(String key) {
    final parts = key.split('::');
    if (parts.length != 4 && parts.length != 5) return null;
    final category = FavoriteCategory.fromId(parts[3]);
    if (category == null) return null;
    return (
      eventId: parts[0],
      blockId: parts[1],
      judgeKey: parts[2],
      category: category,
      routineId: parts.length == 5 ? parts[4] : null
    );
  }

  String? _judgeNameForKey(String judgeKey) {
    for (final judge in judges) {
      if (normalizedKey(judge) == judgeKey ||
          stableRemoteId(judge) == judgeKey) {
        return judge;
      }
    }
    return null;
  }

  String _blockNameFor(String blockId) {
    for (final block in blocks) {
      if (block.blockId == blockId || block.name == blockId) {
        return block.name;
      }
    }
    return blockId;
  }

  int _blockSortOrder(String blockName) {
    for (final block in blocks) {
      if (block.name == blockName || block.blockId == blockName) {
        return block.sortOrder;
      }
    }
    return 1 << 30;
  }

  int _routineOrder(Routine left, Routine right) {
    final leftNumber = int.tryParse(left.id) ?? 1 << 30;
    final rightNumber = int.tryParse(right.id) ?? 1 << 30;
    if (leftNumber == rightNumber) return left.id.compareTo(right.id);
    return leftNumber.compareTo(rightNumber);
  }

  bool _isAdminJudge(String judge) {
    final judgeId = stableRemoteId(judge);
    if (androidAdminJudgeIds.contains(judgeId)) return true;
    final profiles = appData?.judgeProfiles ?? const <JudgeProfile>[];
    for (final profile in profiles) {
      if ((profile.judgeId == judgeId ||
              normalizedKey(profile.name) == normalizedKey(judge)) &&
          profile.role == UserRole.admin) {
        return true;
      }
    }
    return false;
  }

  String _blockIdForRoutine(String routineId) {
    for (final routine in routines) {
      if (routine.id == routineId) {
        if (routine.blockId.isNotEmpty) return routine.blockId;
        return stableRemoteId(routine.block);
      }
    }
    return selectedBlock?.blockId ?? '';
  }

  String _createDeviceID() {
    return 'android-${DateTime.now().microsecondsSinceEpoch}';
  }

  Map<String, double> _decodeDoubleMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded
        .map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  Map<String, String> _decodeStringMap(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }
}
