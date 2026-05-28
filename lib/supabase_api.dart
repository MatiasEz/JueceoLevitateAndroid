import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class SupabaseApi {
  SupabaseApi({required this.url, required this.anonKey});

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
      final response = await http.get(
        _endpoint(
            'blocks?select=event_id,block_id,name,title,sort_order,is_active&order=sort_order.asc'),
        headers: _headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {};
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
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
    final blockResponse = await http.get(
      _endpoint('blocks?select=*&event_id=eq.$eventID&order=sort_order.asc'),
      headers: _headers,
    );
    final blockRows =
        blockResponse.statusCode >= 200 && blockResponse.statusCode < 300
            ? jsonDecode(blockResponse.body) as List<dynamic>
            : <dynamic>[];
    final responses = await Future.wait([
      http.get(
          _endpoint(
              'routines?select=*&event_id=eq.$eventID&order=sort_order.asc'),
          headers: _headers),
      http.get(
          _endpoint(
              'judges?select=*&event_id=eq.$eventID&order=sort_order.asc'),
          headers: _headers),
      http.get(
          _endpoint(
              'criteria_templates?select=*&event_id=eq.$eventID&order=sort_order.asc'),
          headers: _headers),
      http.get(
          _endpoint(
              'criteria?select=*&event_id=eq.$eventID&order=sort_order.asc'),
          headers: _headers),
      http.get(_endpoint('scores?select=*&event_id=eq.$eventID'),
          headers: _headers),
      http.get(_endpoint('feedback?select=*&event_id=eq.$eventID'),
          headers: _headers),
      http.get(_endpoint('penalties?select=*&event_id=eq.$eventID'),
          headers: _headers),
    ]);
    for (final response in responses) {
      _throwIfFailed(response);
    }

    final routineRows = jsonDecode(responses[0].body) as List<dynamic>;
    final judgeRows = jsonDecode(responses[1].body) as List<dynamic>;
    final templateRows = jsonDecode(responses[2].body) as List<dynamic>;
    final criterionRows = jsonDecode(responses[3].body) as List<dynamic>;
    final scoreRows = jsonDecode(responses[4].body) as List<dynamic>;
    final feedbackRows = jsonDecode(responses[5].body) as List<dynamic>;
    final penaltyRows = jsonDecode(responses[6].body) as List<dynamic>;
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

  Future<void> upsertFavorites(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final response = await http.post(
      _endpoint(
          'routine_favorites?on_conflict=event_id,block_id,judge_id,category'),
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
      final response = await http.delete(
        _endpoint(
            'routine_favorites?event_id=eq.$eventID&block_id=eq.$blockID&judge_id=eq.$judgeID&category=eq.$category'),
        headers: {
          ..._headers,
          'Prefer': 'return=minimal',
        },
      );
      _throwIfFailed(response);
    }
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
    try {
      final response = await http.get(
        _endpoint('routine_favorites?select=*&event_id=eq.$eventID'),
        headers: _headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {
      return const [];
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
