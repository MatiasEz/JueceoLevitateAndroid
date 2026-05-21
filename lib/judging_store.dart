import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'supabase_api.dart';

enum SyncState { localOnly, connecting, online, syncing, pending, offline }

const bundledAppDataAsset = 'assets/data/app_data.json';

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

  int get pendingCount =>
      pendingScoreKeys.length +
      pendingFeedbackKeys.length +
      pendingPenaltyKeys.length +
      pendingFavoriteKeys.length;
  List<Routine> get routines => appData?.routines ?? const [];
  List<DanceBlock> get blocks => appData?.blocks ?? const [];
  List<String> get judges => appData?.judges ?? const [];
  List<String> get editableJudges =>
      judges.where((judge) => roleFor(judge) == UserRole.judge).toList();
  bool get isAdmin => roleFor(selectedJudge) == UserRole.admin;
  bool get isAdminEditingAsJudge =>
      isAdmin &&
      adminScoringJudge != null &&
      adminScoringJudge != selectedJudge;
  bool get isLoadingBackendData =>
      api.isConfigured && syncState == SyncState.connecting;
  String get scoringJudge =>
      isAdmin ? (adminScoringJudge ?? selectedJudge) : selectedJudge;

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
    for (final entry in favoriteSelections.entries) {
      final parsed = _parseFavoriteKey(entry.key);
      final routine = routinesByID[entry.value];
      if (parsed == null ||
          parsed.eventId != currentEventKey ||
          routine == null) {
        continue;
      }
      summaries.add(FavoriteSelectionSummary(
        id: entry.key,
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

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    selectedJudge = _prefs?.getString('selectedJudge') ?? '';
    selectedRoutineId = _prefs?.getString('selectedRoutineId') ?? '';
    selectedBlockId = _prefs?.getString('selectedBlockId');
    scores.addAll(_decodeDoubleMap(_prefs?.getString('scores') ?? '{}'));
    feedback.addAll(_decodeStringMap(_prefs?.getString('feedback') ?? '{}'));
    penalties.addAll(_decodeDoubleMap(_prefs?.getString('penalties') ?? '{}'));
    favoriteSelections.addAll(
        _decodeStringMap(_prefs?.getString('favoriteSelections') ?? '{}'));
    pendingScoreKeys
        .addAll(_prefs?.getStringList('pendingScoreKeys') ?? const []);
    pendingFeedbackKeys
        .addAll(_prefs?.getStringList('pendingFeedbackKeys') ?? const []);
    pendingPenaltyKeys
        .addAll(_prefs?.getStringList('pendingPenaltyKeys') ?? const []);
    pendingFavoriteKeys
        .addAll(_prefs?.getStringList('pendingFavoriteKeys') ?? const []);

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
    selectedEvent = event;
    await _prefs?.setString('selectedEventId', event.id);
    syncState = SyncState.connecting;
    syncMessage = 'Cargando ${event.name} desde Supabase...';
    notifyListeners();
    try {
      final bundle = await api.fetchBundle(event);
      appData = bundle.appData;
      _normalizeCurrentSelection();
      final judgeById = {
        for (final judge in judges) stableRemoteId(judge): judge
      };
      for (final remoteScore in bundle.scores) {
        final judge = judgeById[remoteScore.judgeId];
        if (judge == null) continue;
        final key =
            scoreKey(remoteScore.routineId, judge, remoteScore.criterionId);
        if (!pendingScoreKeys.contains(key)) {
          scores[key] = remoteScore.value;
        }
      }
      for (final remoteFeedback in bundle.feedback) {
        final judge = judgeById[remoteFeedback.judgeId];
        if (judge == null) continue;
        final key = feedbackKey(remoteFeedback.routineId, judge);
        if (!pendingFeedbackKeys.contains(key)) {
          feedback[key] = remoteFeedback.body;
        }
      }
      for (final remotePenalty in bundle.penalties) {
        final judge = judgeById[remotePenalty.judgeId];
        if (judge == null) continue;
        final key = penaltyKey(remotePenalty.routineId, judge);
        if (!pendingPenaltyKeys.contains(key)) {
          penalties[key] = remotePenalty.value.clamp(-100, 0).toDouble();
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
        );
        if (!pendingFavoriteKeys.contains(key)) {
          favoriteSelections[key] = remoteFavorite.routineId;
        }
      }
      await _persistAll();
      await syncPending();
    } catch (error) {
      syncState = pendingCount > 0 ? SyncState.pending : SyncState.offline;
      syncMessage = '$error';
      notifyListeners();
    }
  }

  JudgingTemplate templateFor(Routine routine) {
    final templates = appData?.templates ?? const <JudgingTemplate>[];
    return templates.firstWhere(
      (template) =>
          normalizedKey(template.genre) == normalizedKey(routine.genre),
      orElse: () => templates.isEmpty
          ? JudgingTemplate(
              templateId: 'general',
              genre: 'General',
              title: 'Hoja de jueceo',
              maxScore: 0,
              criteria: const [])
          : templates.first,
    );
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
  }) {
    final eventKey = eventId ??
        selectedEvent?.id ??
        stableRemoteId(appData?.sourceName ?? '');
    final blockKey = blockId ?? selectedBlock?.blockId ?? 'sin-bloque';
    return '$eventKey::$blockKey::${normalizedKey(judge ?? scoringJudge)}::${category.id}';
  }

  double scoreFor(Routine routine, String judge, Criterion criterion) {
    return scores[scoreKey(routine.id, judge, criterion.id)] ?? 0;
  }

  double penaltyFor(Routine routine, String judge) {
    return penalties[penaltyKey(routine.id, judge)] ?? 0;
  }

  bool isFavorite(Routine routine, FavoriteCategory category, {String? judge}) {
    return favoriteSelections[favoriteKey(category, judge: judge)] ==
        routine.id;
  }

  bool hasFavorite(Routine routine, {String? judge}) {
    for (final category in FavoriteCategory.values) {
      if (isFavorite(routine, category, judge: judge)) return true;
    }
    return false;
  }

  Future<void> toggleFavorite(FavoriteCategory category, Routine routine,
      {String? judge}) async {
    final key = favoriteKey(category, judge: judge);
    if (favoriteSelections[key] == routine.id) {
      favoriteSelections.remove(key);
    } else {
      favoriteSelections[key] = routine.id;
    }
    pendingFavoriteKeys.add(key);
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
      role:
          stableRemoteId(cleanName) == 'ati' ? UserRole.admin : UserRole.judge,
    ));
    selectJudge(cleanName);
  }

  UserRole roleFor(String judge) {
    final judgeId = stableRemoteId(judge);
    if (judgeId == 'ati') return UserRole.admin;
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

  void selectRoutine(String routineId, {bool notify = true}) {
    selectedRoutineId = routineId;
    _prefs?.setString('selectedRoutineId', routineId);
    if (notify) notifyListeners();
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
    feedback[key] = body.length > 300 ? body.substring(0, 300) : body;
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
      throw StateError('Supabase no esta configurado.');
    }
    if (bytes.isEmpty) {
      throw StateError('No se pudo leer el Excel seleccionado.');
    }
    const maxBytes = 20 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw StateError('El archivo supera el maximo de 20 MB.');
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
      final scoreRows = <Map<String, dynamic>>[];
      for (final key in pendingScoreKeys) {
        final parts = key.split('::');
        if (parts.length != 3) continue;
        scoreRows.add({
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'criterion_id': int.tryParse(parts[2]) ?? 0,
          'value': scores[key] ?? 0,
          'device_id': 'android-tablet',
        });
      }
      await api.upsertScores(eventID, scoreRows);
      pendingScoreKeys.clear();

      final feedbackRows = <Map<String, dynamic>>[];
      for (final key in pendingFeedbackKeys) {
        final parts = key.split('::');
        if (parts.length != 2) continue;
        feedbackRows.add({
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'body': feedback[key] ?? '',
          'device_id': 'android-tablet',
        });
      }
      await api.upsertFeedback(eventID, feedbackRows);
      pendingFeedbackKeys.clear();

      final penaltyRows = <Map<String, dynamic>>[];
      for (final key in pendingPenaltyKeys) {
        final parts = key.split('::');
        if (parts.length != 2) continue;
        penaltyRows.add({
          'event_id': eventID,
          'routine_id': parts[0],
          'judge_id': stableRemoteId(parts[1]),
          'value': penalties[key] ?? 0,
          'device_id': 'android-tablet',
        });
      }
      await api.upsertPenalties(eventID, penaltyRows);
      pendingPenaltyKeys.clear();

      final favoriteKeys = Set<String>.from(pendingFavoriteKeys);
      final favoriteUpsertRows = <Map<String, dynamic>>[];
      final favoriteDeleteRows = <Map<String, dynamic>>[];
      for (final key in favoriteKeys) {
        final parsed = _parseFavoriteKey(key);
        if (parsed == null) continue;
        final judgeName = _judgeNameForKey(parsed.judgeKey);
        if (judgeName == null) continue;
        final selectedRoutine = favoriteSelections[key];
        if (selectedRoutine == null) {
          favoriteDeleteRows.add({
            'event_id': parsed.eventId,
            'block_id': parsed.blockId,
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
            'device_id': 'android-tablet',
          });
        }
      }
      await api.upsertFavorites(favoriteUpsertRows);
      await api.deleteFavorites(favoriteDeleteRows);
      pendingFavoriteKeys.removeAll(favoriteKeys);
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
      final totalCompare = right.total.compareTo(left.total);
      if (totalCompare != 0) return totalCompare;
      return (int.tryParse(left.routine.id) ?? 0)
          .compareTo(int.tryParse(right.routine.id) ?? 0);
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
    await _prefs?.setString('scores', jsonEncode(scores));
    await _prefs?.setString('feedback', jsonEncode(feedback));
    await _prefs?.setString('penalties', jsonEncode(penalties));
    await _prefs?.setString(
        'favoriteSelections', jsonEncode(favoriteSelections));
    await _prefs?.setStringList(
        'pendingScoreKeys', pendingScoreKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingFeedbackKeys', pendingFeedbackKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingPenaltyKeys', pendingPenaltyKeys.toList()..sort());
    await _prefs?.setStringList(
        'pendingFavoriteKeys', pendingFavoriteKeys.toList()..sort());
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
        (!judges.contains(adminScoringJudge) ||
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
    FavoriteCategory category
  })? _parseFavoriteKey(String key) {
    final parts = key.split('::');
    if (parts.length != 4) return null;
    final category = FavoriteCategory.fromId(parts[3]);
    if (category == null) return null;
    return (
      eventId: parts[0],
      blockId: parts[1],
      judgeKey: parts[2],
      category: category
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
