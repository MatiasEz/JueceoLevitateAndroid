class EventSummary {
  EventSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.sourceName,
    required this.isActive,
    this.eventType,
  });

  final String id;
  final String slug;
  final String name;
  final String sourceName;
  final bool isActive;
  final String? eventType;

  factory EventSummary.fromJson(Map<String, dynamic> json) => EventSummary(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sourceName: json['source_name'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
        eventType: json['event_type'] as String?,
      );
}

class AppData {
  AppData({
    required this.sourceName,
    required this.blocks,
    required this.routines,
    required this.templates,
    required this.judges,
    this.judgeProfiles = const [],
  });

  final String sourceName;
  final List<DanceBlock> blocks;
  final List<Routine> routines;
  final List<JudgingTemplate> templates;
  final List<String> judges;
  final List<JudgeProfile> judgeProfiles;

  factory AppData.fromJson(Map<String, dynamic> json) {
    final routines = (json['routines'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Routine.fromJson)
        .toList();
    final routinesByBlock = <String, List<Routine>>{};
    for (final routine in routines) {
      final key = routine.blockId.isEmpty
          ? stableRemoteId(routine.block)
          : routine.blockId;
      routinesByBlock.putIfAbsent(key, () => []).add(routine);
    }
    final blocks = (json['blocks'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((row) {
      final block = DanceBlock.fromJson(row);
      final blockRoutines = block.routines.isNotEmpty
          ? block.routines
          : routinesByBlock[block.blockId];
      return DanceBlock(
        blockId: block.blockId,
        name: block.name,
        title: block.title,
        sortOrder: block.sortOrder,
        isActive: block.isActive,
        routines: blockRoutines ?? const [],
      );
    }).toList();

    return AppData(
      sourceName: json['sourceName'] as String? ??
          json['source_name'] as String? ??
          'Sin datos',
      blocks: blocks.isNotEmpty
          ? blocks
          : routinesByBlock.entries
              .map((entry) => DanceBlock(
                    blockId: entry.key,
                    name: entry.value.first.block,
                    title: entry.value.first.block,
                    routines: entry.value,
                  ))
              .toList(),
      routines: routines,
      templates: (json['templates'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(JudgingTemplate.fromJson)
          .toList(),
      judges: (json['judges'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .where((name) => name.trim().isNotEmpty)
          .toList(),
      judgeProfiles: (json['judgeProfiles'] as List<dynamic>? ??
              json['judge_profiles'] as List<dynamic>? ??
              const [])
          .cast<Map<String, dynamic>>()
          .map(JudgeProfile.fromJson)
          .where((profile) => profile.name.trim().isNotEmpty)
          .toList(),
    );
  }
}

enum UserRole { judge, admin }

enum FavoriteCategory {
  costume,
  choreography,
  music;

  String get id => name;

  String get title {
    return switch (this) {
      FavoriteCategory.costume => 'Vestuario favorito',
      FavoriteCategory.choreography => 'Coreografía favorita',
      FavoriteCategory.music => 'Música favorita',
    };
  }

  static FavoriteCategory? fromId(String value) {
    for (final category in FavoriteCategory.values) {
      if (category.id == value) return category;
    }
    return null;
  }
}

class JudgeProfile {
  JudgeProfile({
    required this.judgeId,
    required this.name,
    required this.role,
    this.heroImageName,
  });

  final String judgeId;
  final String name;
  final UserRole role;
  final String? heroImageName;

  factory JudgeProfile.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role'] as String? ?? '';
    final judgeId = json['judge_id'] as String? ??
        json['judgeID'] as String? ??
        stableRemoteId(json['name'] as String? ?? '');
    return JudgeProfile(
      judgeId: judgeId,
      name: json['name'] as String? ?? '',
      role: rawRole == 'admin' || judgeId == 'ati'
          ? UserRole.admin
          : UserRole.judge,
      heroImageName: json['hero_image_name'] as String? ??
          json['heroImageName'] as String?,
    );
  }
}

class DanceBlock {
  DanceBlock({
    required this.blockId,
    required this.name,
    required this.title,
    required this.routines,
    this.sortOrder = 0,
    this.isActive = false,
  });

  final String blockId;
  final String name;
  final String title;
  final List<Routine> routines;
  final int sortOrder;
  final bool isActive;

  factory DanceBlock.fromJson(Map<String, dynamic> json) => DanceBlock(
        blockId: json['block_id'] as String? ??
            json['blockID'] as String? ??
            json['id'] as String? ??
            stableRemoteId(json['name'] as String? ?? ''),
        name: json['name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sortOrder: json['sort_order'] as int? ?? json['sortOrder'] as int? ?? 0,
        isActive:
            json['is_active'] as bool? ?? json['isActive'] as bool? ?? false,
        routines: (json['routines'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Routine.fromJson)
            .toList(),
      );
}

class Routine {
  Routine({
    required this.id,
    required this.blockId,
    required this.block,
    required this.name,
    required this.academy,
    required this.division,
    required this.genre,
    required this.level,
    required this.category,
    required this.choreographer,
    required this.participant,
    required this.state,
    required this.time,
    required this.duration,
  });

  final String id;
  final String blockId;
  final String block;
  final String name;
  final String academy;
  final String division;
  final String genre;
  final String level;
  final String category;
  final String choreographer;
  final String participant;
  final String state;
  final String time;
  final String duration;

  String? get levelTagText {
    final trimmed = level.trim();
    if (trimmed.isEmpty ||
        trimmed == '-' ||
        normalizedKey(trimmed) == 'SIN NIVEL') {
      return null;
    }
    return trimmed;
  }

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: json['routine_id'] as String? ?? json['id'] as String? ?? '',
        blockId:
            json['block_id'] as String? ?? json['blockID'] as String? ?? '',
        block: json['block'] as String? ?? '',
        name: json['name'] as String? ?? '',
        academy: json['academy'] as String? ?? '',
        division: json['division'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        level: json['level'] as String? ?? '',
        category: json['category'] as String? ?? '',
        choreographer: json['choreographer'] as String? ?? '',
        participant: json['participant'] as String? ?? '',
        state: json['state'] as String? ?? '',
        time:
            json['scheduled_time'] as String? ?? json['time'] as String? ?? '',
        duration: json['duration'] as String? ?? '',
      );
}

class JudgingTemplate {
  JudgingTemplate({
    required this.templateId,
    required this.genre,
    required this.title,
    required this.maxScore,
    required this.criteria,
  });

  final String templateId;
  final String genre;
  final String title;
  final double maxScore;
  final List<Criterion> criteria;

  factory JudgingTemplate.fromJson(Map<String, dynamic> json) =>
      JudgingTemplate(
        templateId: json['template_id'] as String? ??
            json['templateID'] as String? ??
            stableRemoteId(json['genre'] as String? ?? ''),
        genre: json['genre'] as String? ?? '',
        title: json['title'] as String? ?? '',
        maxScore: (json['max_score'] as num? ?? json['maxScore'] as num? ?? 0)
            .toDouble(),
        criteria: (json['criteria'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Criterion.fromJson)
            .toList(),
      );
}

class Criterion {
  Criterion({
    required this.id,
    required this.section,
    required this.label,
    required this.maxScore,
  });

  final int id;
  final String section;
  final String label;
  final double maxScore;

  factory Criterion.fromJson(Map<String, dynamic> json) => Criterion(
        id: json['criterion_id'] as int? ?? json['id'] as int? ?? 0,
        section: json['section'] as String? ?? '',
        label: json['label'] as String? ?? '',
        maxScore: (json['max_score'] as num? ?? json['maxScore'] as num? ?? 0)
            .toDouble(),
      );
}

class RemoteScore {
  RemoteScore({
    required this.routineId,
    required this.judgeId,
    required this.criterionId,
    required this.value,
  });

  final String routineId;
  final String judgeId;
  final int criterionId;
  final double value;

  factory RemoteScore.fromJson(Map<String, dynamic> json) => RemoteScore(
        routineId: json['routine_id'] as String? ?? '',
        judgeId: json['judge_id'] as String? ?? '',
        criterionId: json['criterion_id'] as int? ?? 0,
        value: (json['value'] as num? ?? 0).toDouble(),
      );
}

class RemoteFeedback {
  RemoteFeedback(
      {required this.routineId, required this.judgeId, required this.body});

  final String routineId;
  final String judgeId;
  final String body;

  factory RemoteFeedback.fromJson(Map<String, dynamic> json) => RemoteFeedback(
        routineId: json['routine_id'] as String? ?? '',
        judgeId: json['judge_id'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
}

class RemotePenalty {
  RemotePenalty({
    required this.routineId,
    required this.judgeId,
    required this.value,
  });

  final String routineId;
  final String judgeId;
  final double value;

  factory RemotePenalty.fromJson(Map<String, dynamic> json) => RemotePenalty(
        routineId: json['routine_id'] as String? ?? '',
        judgeId: json['judge_id'] as String? ?? '',
        value: (json['value'] as num? ?? 0).toDouble(),
      );
}

class RemoteFavorite {
  RemoteFavorite({
    required this.eventId,
    required this.blockId,
    required this.routineId,
    required this.judgeId,
    required this.category,
  });

  final String eventId;
  final String blockId;
  final String routineId;
  final String judgeId;
  final FavoriteCategory category;

  factory RemoteFavorite.fromJson(Map<String, dynamic> json) => RemoteFavorite(
        eventId: json['event_id'] as String? ?? '',
        blockId: json['block_id'] as String? ?? '',
        routineId: json['routine_id'] as String? ?? '',
        judgeId: json['judge_id'] as String? ?? '',
        category: FavoriteCategory.fromId(json['category'] as String? ?? '') ??
            FavoriteCategory.costume,
      );
}

class FavoriteSelectionSummary {
  FavoriteSelectionSummary({
    required this.id,
    required this.category,
    required this.judge,
    required this.blockName,
    required this.routine,
  });

  final String id;
  final FavoriteCategory category;
  final String judge;
  final String blockName;
  final Routine routine;
}

class FavoriteRankingBlock {
  FavoriteRankingBlock({required this.blockName, required this.categories});

  String get id => normalizedKey(blockName);
  final String blockName;
  final List<FavoriteCategoryRanking> categories;

  int get totalVotes =>
      categories.fold(0, (sum, category) => sum + category.totalVotes);
}

class FavoriteCategoryRanking {
  FavoriteCategoryRanking({required this.category, required this.items});

  String get id => category.id;
  final FavoriteCategory category;
  final List<FavoriteRankingItem> items;

  int get totalVotes => items.fold(0, (sum, item) => sum + item.votes);
}

class FavoriteRankingItem {
  FavoriteRankingItem({
    required this.id,
    required this.rank,
    required this.category,
    required this.blockName,
    required this.routine,
    required this.votes,
    required this.judges,
  });

  final String id;
  final int rank;
  final FavoriteCategory category;
  final String blockName;
  final Routine routine;
  final int votes;
  final List<String> judges;
}

class RoutineResult {
  RoutineResult({
    required this.routine,
    required this.judgeTotals,
    required this.judgePenalties,
    required this.total,
    required this.penalty,
    required this.maxScore,
  });

  final Routine routine;
  final Map<String, double> judgeTotals;
  final Map<String, double> judgePenalties;
  final double total;
  final double penalty;
  final double maxScore;

  double get aggregateTotal =>
      judgeTotals.values.fold(0, (sum, total) => sum + total);
}

String normalizedKey(String value) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final folded =
      value.toLowerCase().split('').map((char) => accents[char] ?? char).join();
  return folded.trim().toUpperCase();
}

String stableRemoteId(String value) {
  final normalized = normalizedKey(value).toLowerCase();
  final buffer = StringBuffer();
  var lastWasDash = false;
  for (final unit in normalized.codeUnits) {
    final isAlpha = unit >= 97 && unit <= 122;
    final isDigit = unit >= 48 && unit <= 57;
    if (isAlpha || isDigit) {
      buffer.writeCharCode(unit);
      lastWasDash = false;
    } else if (!lastWasDash) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  final cleaned = buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'sin-dato' : cleaned;
}
