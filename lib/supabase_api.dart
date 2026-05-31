import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class SupabaseApi {
  SupabaseApi({required this.url, required this.anonKey});

  static const int _pageSize = 1000;

  final String url;
  final String anonKey;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  Uri _endpoint(String path) {
    final cleanURL = url.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$cleanURL/rest/v1/$path');
  }

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      };

  Future<List<EventSummary>> fetchEvents() async {
    var response = await http.get(
      _endpoint(
          'events?select=id,slug,name,source_name,is_active,event_type&or=(event_type.is.null,event_type.eq.event)&order=is_active.desc,created_at.desc'),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      response = await http.get(
        _endpoint(
            'events?select=id,slug,name,source_name,is_active&order=is_active.desc,created_at.desc'),
        headers: _headers,
      );
    }
    _throwIfFailed(response);
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map((row) => EventSummary.fromJson(row as Map<String, dynamic>))
        .where((event) =>
            event.eventType != 'legacy_block' && event.eventType != 'archived')
        .toList();
  }

  Future<Map<String, List<DanceBlock>>> fetchEventBlocks() async {
    try {
      final rows = await _getAllRows(
          'blocks?select=event_id,block_id,name,title,sort_order,is_active&order=event_id.asc,sort_order.asc,block_id.asc');
      final result = <String, List<DanceBlock>>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final eventId = row['event_id'] as String? ?? '';
        if (eventId.isEmpty) continue;
        result.putIfAbsent(eventId, () => []).add(DanceBlock.fromJson(row));
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<RemoteBundle> fetchBundle(EventSummary event) async {
    final eventID = Uri.encodeQueryComponent(event.id);
    final blockRows = await _getAllRows(
      'blocks?select=*&event_id=eq.$eventID&order=sort_order.asc,block_id.asc',
    );
    final rows = await Future.wait([
      _getAllRows(
          'routines?select=*&event_id=eq.$eventID&order=sort_order.asc,routine_id.asc'),
      _getAllRows(
          'judges?select=*&event_id=eq.$eventID&order=sort_order.asc,judge_id.asc'),
      _getAllRows(
          'criteria_templates?select=*&event_id=eq.$eventID&order=sort_order.asc,template_id.asc'),
      _getAllRows(
          'criteria?select=*&event_id=eq.$eventID&order=sort_order.asc,criterion_id.asc'),
      _getAllRows(
          'scores?select=*&event_id=eq.$eventID&order=routine_id.asc,judge_id.asc,criterion_id.asc'),
      _getAllRows(
          'feedback?select=*&event_id=eq.$eventID&order=routine_id.asc,judge_id.asc'),
      _getAllRows(
          'penalties?select=*&event_id=eq.$eventID&order=routine_id.asc,judge_id.asc'),
    ]);

    final routineRows = rows[0];
    final judgeRows = rows[1];
    final templateRows = rows[2];
    final criterionRows = rows[3];
    final scoreRows = rows[4];
    final feedbackRows = rows[5];
    final penaltyRows = rows[6];
    final favoriteRows = await _fetchFavorites(eventID);

    final routines = routineRows
        .map((row) => Routine.fromJson(row as Map<String, dynamic>))
        .toList();
    final judges = judgeRows
        .map((row) => (row as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final judgeProfiles = judgeRows
        .cast<Map<String, dynamic>>()
        .map(JudgeProfile.fromJson)
        .where((profile) => profile.name.isNotEmpty)
        .toList();

    final criteriaByTemplate = <String, List<Criterion>>{};
    for (final item in criterionRows.cast<Map<String, dynamic>>()) {
      final templateID = item['template_id'] as String? ?? '';
      criteriaByTemplate
          .putIfAbsent(templateID, () => [])
          .add(Criterion.fromJson(item));
    }

    final templates = templateRows.cast<Map<String, dynamic>>().map((row) {
      final templateID = row['template_id'] as String? ?? '';
      return JudgingTemplate(
        templateId: templateID,
        genre: row['genre'] as String? ?? '',
        title: row['title'] as String? ?? '',
        maxScore: (row['max_score'] as num? ?? 0).toDouble(),
        criteria: criteriaByTemplate[templateID] ?? const [],
      );
    }).toList();

    final blocks = <String, List<Routine>>{};
    final blockTitles = <String, String>{};
    for (final row in routineRows.cast<Map<String, dynamic>>()) {
      final routine = Routine.fromJson(row);
      final key = routine.blockId.isEmpty
          ? stableRemoteId(routine.block)
          : routine.blockId;
      blocks.putIfAbsent(key, () => []).add(routine);
      blockTitles[key] = row['block_title'] as String? ?? '';
    }
    final remoteBlocks = blockRows.cast<Map<String, dynamic>>().map((row) {
      final blockId = row['block_id'] as String? ?? '';
      return DanceBlock(
        blockId: blockId,
        name: row['name'] as String? ?? '',
        title: row['title'] as String? ?? '',
        sortOrder: row['sort_order'] as int? ?? 0,
        isActive: row['is_active'] as bool? ?? false,
        routines: blocks[blockId] ?? const [],
      );
    }).toList();

    final appData = AppData(
      sourceName: event.sourceName.isEmpty ? event.name : event.sourceName,
      routines: routines,
      judges: judges,
      judgeProfiles: judgeProfiles,
      templates: templates,
      blocks: remoteBlocks.isNotEmpty
          ? remoteBlocks
          : blocks.entries
              .map((entry) => DanceBlock(
                    blockId: entry.key,
                    name: entry.key,
                    title: blockTitles[entry.key] ?? '',
                    routines: entry.value,
                  ))
              .toList(),
    );

    return RemoteBundle(
      event: event,
      appData: appData,
      scores: scoreRows
          .map((row) => RemoteScore.fromJson(row as Map<String, dynamic>))
          .toList(),
      feedback: feedbackRows
          .map((row) => RemoteFeedback.fromJson(row as Map<String, dynamic>))
          .toList(),
      penalties: penaltyRows
          .map((row) => RemotePenalty.fromJson(row as Map<String, dynamic>))
          .toList(),
      favorites: favoriteRows
          .map((row) => RemoteFavorite.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> upsertScores(
      String eventID, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('scores?on_conflict=event_id,routine_id,judge_id,criterion_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertFeedback(
      String eventID, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('feedback?on_conflict=event_id,routine_id,judge_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertPenalties(
      String eventID, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint('penalties?on_conflict=event_id,routine_id,judge_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertJudgeActivity(Map<String, dynamic> row) async {
    final response = await http.post(
      _endpoint('judge_activity?on_conflict=event_id,judge_id,device_id'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(row),
    );
    _throwIfFailed(response);
  }

  Future<void> upsertFavorites(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint(
          'routine_favorite_votes?on_conflict=event_id,block_id,routine_id,judge_id,category'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    _throwIfFailed(response);
  }

  Future<void> deleteFavorites(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      final eventID = _queryValue(row['event_id'] as String? ?? '');
      final blockID = _queryValue(row['block_id'] as String? ?? '');
      final judgeID = _queryValue(row['judge_id'] as String? ?? '');
      final category = _queryValue(row['category'] as String? ?? '');
      final routineID = _queryValue(row['routine_id'] as String? ?? '');
      final routineFilter =
          routineID.isEmpty ? '' : '&routine_id=eq.$routineID';
      await _deleteFavoriteRow(
          'routine_favorite_votes?event_id=eq.$eventID&block_id=eq.$blockID&judge_id=eq.$judgeID&category=eq.$category$routineFilter');
      await _deleteFavoriteRow(
          'routine_favorites?event_id=eq.$eventID&block_id=eq.$blockID&judge_id=eq.$judgeID&category=eq.$category$routineFilter');
    }
  }

  Future<void> _deleteFavoriteRow(String path) async {
    final response = await http.delete(
      _endpoint(path),
      headers: {
        ..._headers,
        'Prefer': 'return=minimal',
      },
    );
    _throwIfFailed(response);
  }

  Future<void> uploadExcelImport(Map<String, dynamic> row) async {
    final response = await http.post(
      _endpoint('excel_imports'),
      headers: {
        ..._headers,
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(row),
    );
    _throwIfFailed(response);
  }

  Future<List<dynamic>> _fetchFavorites(String eventID) async {
    final rows = <dynamic>[];
    final seen = <String>{};

    for (final table in ['routine_favorite_votes', 'routine_favorites']) {
      try {
        final tableRows = await _getAllRows(
            '$table?select=*&event_id=eq.$eventID&order=block_id.asc,judge_id.asc,category.asc,routine_id.asc');
        for (final row in tableRows) {
          final item = row as Map<String, dynamic>;
          final key = [
            item['event_id'],
            item['block_id'],
            item['routine_id'],
            item['judge_id'],
            item['category'],
          ].join('::');
          if (seen.add(key)) {
            rows.add(item);
          }
        }
      } catch (_) {
        continue;
      }
    }

    return rows;
  }

  Future<List<dynamic>> _getAllRows(String path,
      {int pageSize = _pageSize}) async {
    final rows = <dynamic>[];
    var start = 0;
    while (true) {
      final end = start + pageSize - 1;
      final response = await http.get(
        _endpoint(path),
        headers: {
          ..._headers,
          'Range-Unit': 'items',
          'Range': '$start-$end',
        },
      );
      _throwIfFailed(response);
      final page = jsonDecode(response.body) as List<dynamic>;
      rows.addAll(page);
      if (page.length < pageSize) {
        return rows;
      }
      start += pageSize;
    }
  }

  String _queryValue(String value) => Uri.encodeQueryComponent(value);

  void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseApiException(response.statusCode, response.body);
    }
  }
}

class RemoteBundle {
  RemoteBundle({
    required this.event,
    required this.appData,
    required this.scores,
    required this.feedback,
    required this.penalties,
    required this.favorites,
  });

  final EventSummary event;
  final AppData appData;
  final List<RemoteScore> scores;
  final List<RemoteFeedback> feedback;
  final List<RemotePenalty> penalties;
  final List<RemoteFavorite> favorites;
}

class SupabaseApiException implements Exception {
  SupabaseApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Supabase $statusCode: $body';
}
