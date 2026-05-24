import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'google_drive_service.dart';
import 'judging_store.dart';
import 'models.dart';
import 'supabase_api.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const googleDriveRootFolder = String.fromEnvironment(
  'GOOGLE_DRIVE_ROOT_FOLDER',
  defaultValue: 'Levitate CDMX 2026',
);
const addJudgeMenuValue = '__add_judge__';

const levitPink = Color(0xffed2a72);
const levitateLogoAsset = 'assets/images/levitate_logo.png';
const levitateDancerHeroAsset = 'assets/images/levitate_dancer_hero.png';
const judgeHeroAssets = {
  'alex': 'assets/images/judge_hero_alex.jpeg',
  'angela': 'assets/images/judge_hero_angela.png',
  'daniel': 'assets/images/judge_hero_daniel.png',
  'vladimir': 'assets/images/judge_hero_vladimir.png',
  'yoli': 'assets/images/judge_hero_yoli.png',
};
const levitPaperLight = Color(0xfffbfbfd);
const levitPaperDark = Color(0xff0b0e13);

String judgeHeroAssetFor(String judge) {
  final judgeId = stableRemoteId(judge);
  final exact = judgeHeroAssets[judgeId];
  if (exact != null) return exact;
  final tokens = judgeId.split('-').toSet();
  for (final entry in judgeHeroAssets.entries) {
    if (tokens.contains(entry.key)) return entry.value;
  }
  return levitateDancerHeroAsset;
}

ThemeData levitateTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: levitPink,
    brightness: brightness,
  ).copyWith(
    surface: brightness == Brightness.light ? levitPaperLight : levitPaperDark,
  );
  final base = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    typography: Typography.material2021(platform: TargetPlatform.iOS),
    fontFamily: 'sans-serif',
    fontFamilyFallback: const ['Roboto', 'Arial'],
  );

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surface,
    textTheme: _levitateTextTheme(base.textTheme),
    primaryTextTheme: _levitateTextTheme(base.primaryTextTheme),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    ),
  );
}

TextTheme _levitateTextTheme(TextTheme base) {
  TextStyle? fix(TextStyle? style) => style?.copyWith(letterSpacing: 0);
  return base.copyWith(
    displayLarge: fix(base.displayLarge),
    displayMedium: fix(base.displayMedium),
    displaySmall: fix(base.displaySmall),
    headlineLarge: fix(base.headlineLarge),
    headlineMedium: fix(base.headlineMedium),
    headlineSmall: fix(base.headlineSmall),
    titleLarge: fix(base.titleLarge),
    titleMedium: fix(base.titleMedium),
    titleSmall: fix(base.titleSmall),
    bodyLarge: fix(base.bodyLarge),
    bodyMedium: fix(base.bodyMedium),
    bodySmall: fix(base.bodySmall),
    labelLarge: fix(base.labelLarge),
    labelMedium: fix(base.labelMedium),
    labelSmall: fix(base.labelSmall),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseApiKey = supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;
  final store =
      JudgingStore(SupabaseApi(url: supabaseUrl, anonKey: supabaseApiKey));
  await store.initialize();
  runApp(JueceoTabletApp(store: store));
}

enum AppSection {
  home,
  admin,
  favorites,
  blocks,
  judging,
  scores,
  dictamen,
  excel
}

extension AppSectionMeta on AppSection {
  String get label {
    return switch (this) {
      AppSection.home => 'Inicio',
      AppSection.admin => 'Admin',
      AppSection.favorites => 'Favoritos',
      AppSection.blocks => 'Bloques',
      AppSection.judging => 'Jueceo',
      AppSection.scores => 'Ranking',
      AppSection.dictamen => 'Dictamen',
      AppSection.excel => 'Excel',
    };
  }

  IconData get icon {
    return switch (this) {
      AppSection.home => Icons.home_outlined,
      AppSection.admin => Icons.admin_panel_settings,
      AppSection.favorites => Icons.star,
      AppSection.blocks => Icons.list_alt,
      AppSection.judging => Icons.fact_check,
      AppSection.scores => Icons.bar_chart,
      AppSection.dictamen => Icons.emoji_events,
      AppSection.excel => Icons.upload_file,
    };
  }

  bool get requiresAdmin {
    return switch (this) {
      AppSection.home || AppSection.judging => false,
      AppSection.admin ||
      AppSection.favorites ||
      AppSection.blocks ||
      AppSection.scores ||
      AppSection.dictamen ||
      AppSection.excel =>
        true,
    };
  }
}

List<AppSection> navigationSectionsFor(JudgingStore store) {
  if (store.isAdmin) {
    return const [
      AppSection.home,
      AppSection.admin,
      AppSection.favorites,
      AppSection.scores,
      AppSection.dictamen,
      AppSection.excel,
    ];
  }
  return const [AppSection.home, AppSection.judging];
}

bool canOpenSection(AppSection section, JudgingStore store) {
  if (navigationSectionsFor(store).contains(section)) return true;
  return store.isAdmin &&
      section == AppSection.judging &&
      store.isAdminEditingAsJudge;
}

class LevitateBrand extends StatelessWidget {
  const LevitateBrand({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Levitate',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          levitateLogoAsset,
          width: isCompact ? 136 : 204,
          height: isCompact ? 40 : 60,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.onSurface,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class JueceoTabletApp extends StatelessWidget {
  const JueceoTabletApp({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jueceo Coreografías',
      theme: levitateTheme(Brightness.light),
      darkTheme: levitateTheme(Brightness.dark),
      home: AnimatedBuilder(
        animation: store,
        builder: (context, _) => AdaptiveShell(store: store),
      ),
    );
  }
}

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return PhoneShell(store: store);
        }
        return TabletShell(store: store);
      },
    );
  }
}

class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, required this.store});

  final JudgingStore store;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  AppSection section = AppSection.home;

  void navigate(AppSection target) {
    if (!canOpenSection(target, widget.store)) return;
    setState(() => section = target);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final navigationSections = navigationSectionsFor(store);
    final currentSection =
        canOpenSection(section, store) ? section : AppSection.home;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _pageFor(currentSection, store)),
            if (store.isLoadingBackendData)
              BackendLoadingOverlay(message: store.syncMessage),
          ],
        ),
      ),
      bottomNavigationBar: PhoneBottomNav(
        sections: navigationSections,
        selected: currentSection,
        onSelected: navigate,
      ),
    );
  }

  Widget _pageFor(AppSection activeSection, JudgingStore store) {
    return switch (activeSection) {
      AppSection.home => PhoneHomePage(store: store, onNavigate: navigate),
      AppSection.admin => PhoneAdminPage(store: store, onNavigate: navigate),
      AppSection.favorites => PhoneFavoritesPage(store: store),
      AppSection.blocks => PhoneBlocksPage(
          store: store, onOpenRoutine: () => navigate(AppSection.judging)),
      AppSection.judging =>
        JudgingPage(store: store, onBack: () => navigate(AppSection.home)),
      AppSection.scores => PhoneScoresPage(store: store),
      AppSection.dictamen => PhoneDictamenPage(store: store),
      AppSection.excel => ExcelImportPage(store: store),
    };
  }
}

class PhoneBottomNav extends StatelessWidget {
  const PhoneBottomNav(
      {super.key,
      required this.sections,
      required this.selected,
      required this.onSelected});

  final List<AppSection> sections;
  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (final item in sections)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PhoneNavButton(
                    section: item,
                    selected: item == selected,
                    onTap: () => onSelected(item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhoneNavButton extends StatelessWidget {
  const PhoneNavButton(
      {super.key,
      required this.section,
      required this.selected,
      required this.onTap});

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background =
        selected ? colorScheme.primaryContainer : Colors.transparent;
    final foreground =
        selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 86,
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(section.icon, color: foreground, size: 21),
              const SizedBox(height: 3),
              Text(section.phoneLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

extension PhoneAppSectionMeta on AppSection {
  String get phoneLabel {
    return switch (this) {
      AppSection.blocks => 'Rutinas',
      AppSection.scores => 'Ranking',
      AppSection.excel => 'Excel',
      _ => label,
    };
  }
}

class TabletShell extends StatefulWidget {
  const TabletShell({super.key, required this.store});

  final JudgingStore store;

  @override
  State<TabletShell> createState() => _TabletShellState();
}

class _TabletShellState extends State<TabletShell> {
  AppSection section = AppSection.home;

  void navigate(AppSection target) {
    if (!canOpenSection(target, widget.store)) return;
    setState(() => section = target);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final navigationSections = navigationSectionsFor(store);
    final currentSection =
        canOpenSection(section, store) ? section : AppSection.home;
    final selectedNavIndex = navigationSections.indexOf(currentSection);
    final showNavigationRail = currentSection != AppSection.judging;

    return Scaffold(
      appBar: AppBar(
        title: const LevitateBrand(isCompact: true),
        titleSpacing: 20,
        actions: [
          if (store.isAdmin) ...[
            EventSelectorButton(store: store),
            const SizedBox(width: 8),
            BlockSelectorButton(store: store),
            const SizedBox(width: 8),
          ],
          JudgeSelectorButton(store: store),
          const SizedBox(width: 8),
          SyncChip(store: store),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              store.refreshEvents();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          if (showNavigationRail) ...[
            NavigationRail(
              selectedIndex: selectedNavIndex < 0 ? null : selectedNavIndex,
              onDestinationSelected: (index) =>
                  navigate(navigationSections[index]),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final item in navigationSections)
                  NavigationRailDestination(
                    icon: SidebarIcon(section: item, selected: false),
                    selectedIcon: SidebarIcon(section: item, selected: true),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _pageFor(currentSection, store)),
                if (store.isLoadingBackendData)
                  BackendLoadingOverlay(message: store.syncMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageFor(AppSection activeSection, JudgingStore store) {
    return switch (activeSection) {
      AppSection.home => HomePage(store: store, onNavigate: navigate),
      AppSection.admin => AdminPage(store: store, onNavigate: navigate),
      AppSection.favorites => FavoritesPage(store: store),
      AppSection.blocks => BlocksPage(
          store: store, onOpenRoutine: () => navigate(AppSection.judging)),
      AppSection.judging =>
        JudgingPage(store: store, onBack: () => navigate(AppSection.home)),
      AppSection.scores => ScoresPage(store: store),
      AppSection.dictamen => DictamenPage(store: store),
      AppSection.excel => ExcelImportPage(store: store),
    };
  }
}

class SidebarIcon extends StatelessWidget {
  const SidebarIcon({super.key, required this.section, required this.selected});

  final AppSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(section.icon, color: selected ? colorScheme.primary : null),
        if (section == AppSection.admin)
          Positioned(
            right: -7,
            bottom: -7,
            child: CircleAvatar(
              radius: 8,
              backgroundColor:
                  selected ? colorScheme.primary : colorScheme.primaryContainer,
              child: Icon(Icons.settings,
                  size: 10,
                  color:
                      selected ? colorScheme.onPrimary : colorScheme.primary),
            ),
          ),
      ],
    );
  }
}

class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final color = switch (store.syncState) {
      SyncState.online => Colors.green,
      SyncState.connecting || SyncState.syncing => Colors.blue,
      SyncState.pending => Colors.orange,
      SyncState.offline => Colors.red,
      SyncState.localOnly => Colors.grey,
    };
    final label = store.pendingCount > 0
        ? '${syncStateLabel(store.syncState)} · ${store.pendingCount}'
        : syncStateLabel(store.syncState);
    return Chip(
      avatar: Icon(Icons.cloud_queue, color: color, size: 18),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.10),
    );
  }
}

String syncStateLabel(SyncState state) {
  return switch (state) {
    SyncState.localOnly => 'Modo local',
    SyncState.connecting => 'Conectando',
    SyncState.online => 'En línea',
    SyncState.syncing => 'Sincronizando',
    SyncState.pending => 'Pendiente',
    SyncState.offline => 'Sin conexión',
  };
}

class EventSelectorButton extends StatelessWidget {
  const EventSelectorButton({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<EventSummary>(
      tooltip: 'Evento',
      onSelected: (event) {
        store.selectEvent(event);
      },
      itemBuilder: (context) => [
        for (final event in store.events)
          PopupMenuItem(
            value: event,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(event.id == store.selectedEvent?.id
                  ? Icons.check_circle
                  : Icons.circle_outlined),
              title: Text(event.name),
              subtitle: Text(
                  event.sourceName.isEmpty ? event.slug : event.sourceName),
            ),
          ),
      ],
      child: HeaderPill(
        icon: Icons.event,
        title: store.selectedEvent?.name ?? 'Evento',
        subtitle: '${store.routines.length} coreografías',
      ),
    );
  }
}

class BlockSelectorButton extends StatelessWidget {
  const BlockSelectorButton({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DanceBlock>(
      tooltip: 'Bloque',
      onSelected: store.selectBlock,
      itemBuilder: (context) => [
        for (final block in store.blocks)
          PopupMenuItem(
            value: block,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(block.blockId == store.selectedBlock?.blockId
                  ? Icons.check_circle
                  : Icons.circle_outlined),
              title: Text(block.name),
              subtitle:
                  Text('${routineCountForBlock(store, block)} coreografías'),
            ),
          ),
      ],
      child: HeaderPill(
        icon: Icons.view_agenda,
        title: store.selectedBlock?.name ?? 'Bloque',
        subtitle: '${store.visibleRoutines.length} en vista',
      ),
    );
  }
}

class JudgeSelectorButton extends StatelessWidget {
  const JudgeSelectorButton({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Juez',
      onSelected: (value) {
        if (value == addJudgeMenuValue) {
          showAddJudgeDialog(context, store);
        } else {
          store.selectJudge(value);
        }
      },
      itemBuilder: (context) => [
        for (final judge in store.judges)
          PopupMenuItem(
            value: judge,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(judge == store.selectedJudge
                  ? Icons.check_circle
                  : Icons.circle_outlined),
              title: Text(judge),
              subtitle: Text(store.roleTitleFor(judge)),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: addJudgeMenuValue,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_add),
            title: Text('Nuevo juez'),
          ),
        ),
      ],
      child: HeaderPill(
        icon: Icons.person,
        title: store.selectedJudge.isEmpty ? 'Juez' : store.selectedJudge,
        subtitle: store.selectedJudge.isEmpty
            ? 'Seleccionar'
            : store.roleTitleFor(store.selectedJudge),
      ),
    );
  }
}

Future<void> showAddJudgeDialog(
  BuildContext context,
  JudgingStore store,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Nuevo juez'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Agregar'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty) return;
  final before = store.judges.length;
  store.addJudge(name);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        store.judges.length == before
            ? 'Ese juez ya existe.'
            : 'Juez agregado: ${name.trim().toUpperCase()}',
      ),
    ),
  );
}

class HeaderPill extends StatelessWidget {
  const HeaderPill(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class BackendLoadingOverlay extends StatelessWidget {
  const BackendLoadingOverlay({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface.withValues(alpha: 0.82),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 14))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text('Cargando datos',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.onNavigate});

  final JudgingStore store;
  final ValueChanged<AppSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final routines = sortedRoutines(store.visibleRoutines);
    final pending = routines
        .where((routine) => store.resultFor(routine).aggregateTotal == 0)
        .take(1)
        .toList();
    final preview = pending.isEmpty ? routines.take(1).toList() : pending;
    final completed =
        store.rankings.where((result) => result.aggregateTotal > 0).length;
    final nextRoutine =
        preview.isNotEmpty ? preview.first : store.selectedRoutine;
    final syncPercent = store.pendingCount == 0
        ? 100
        : (100 - store.pendingCount * 8).clamp(0, 100);
    final syncDetail = store.pendingCount == 0
        ? 'Todo al día'
        : '${store.pendingCount} pendiente${store.pendingCount == 1 ? '' : 's'}';

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final showHeroImage = constraints.maxWidth >= 620;
            final heroWidth =
                (constraints.maxWidth * 0.38).clamp(220.0, 330.0).toDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Buenos días,',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline)),
                      Text(
                        store.selectedJudge.isEmpty
                            ? 'JUEZ'
                            : store.selectedJudge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w900, color: levitPink),
                      ),
                      Text('Estás lista para calificar.\nQue comience el flow!',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                if (showHeroImage) ...[
                  const SizedBox(width: 28),
                  DashboardJudgeImage(
                    judge: store.scoringJudge,
                    width: heroWidth,
                    height: heroWidth * 0.527,
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            Widget metricsGrid() => GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.18,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    MetricTile(
                        icon: Icons.calendar_month,
                        value: '$completed',
                        label: 'Calificadas',
                        detail:
                            '${percentage(completed, store.visibleRoutines.length)}% del bloque'),
                    MetricTile(
                        icon: Icons.cloud_done,
                        value: '$syncPercent%',
                        label: 'Sincronización',
                        detail: syncDetail),
                  ],
                );

            Widget upcoming() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Próximas coreografías'),
                    const SizedBox(height: 10),
                    for (final routine in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RoutineListTile(
                          routine: routine,
                          selected: routine.id == nextRoutine?.id,
                          onTap: () => store.selectRoutine(routine.id),
                        ),
                      ),
                  ],
                );

            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: metricsGrid()),
                  const SizedBox(width: 18),
                  Expanded(flex: 3, child: upcoming()),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                metricsGrid(),
                const SizedBox(height: 18),
                upcoming(),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (!store.isAdmin)
              Expanded(
                child: FilledButton.icon(
                  onPressed: nextRoutine == null
                      ? null
                      : () => onNavigate(AppSection.judging),
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Entrar al jueceo'),
                  ),
                ),
              ),
            if (store.isAdmin)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onNavigate(AppSection.admin),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Panel admin'),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class DashboardJudgeImage extends StatelessWidget {
  const DashboardJudgeImage({
    super.key,
    required this.judge,
    this.width = 330,
    this.height = 174,
  });

  final String judge;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = colorScheme.surface;
    final asset = judgeHeroAssetFor(judge);

    return Semantics(
      label: 'Imagen de Levitate para $judge',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                asset,
                key: ValueKey(asset),
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                filterQuality: FilterQuality.high,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      surface.withValues(alpha: isDark ? 0.76 : 0.58),
                      surface.withValues(alpha: isDark ? 0.18 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      surface.withValues(alpha: isDark ? 0.52 : 0.34),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.store, required this.onNavigate});

  final JudgingStore store;
  final ValueChanged<AppSection> onNavigate;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String selectedJudgeForEdit = '';
  String selectedRoutineIdForEdit = '';
  String query = '';
  bool exportingDrive = false;
  String? driveMessage;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!store.editableJudges.contains(selectedJudgeForEdit)) {
      selectedJudgeForEdit = store.adminScoringJudge ??
          (store.editableJudges.isEmpty ? '' : store.editableJudges.first);
    }
    final routines = sortedRoutines(store.visibleRoutines);
    if (!routines.any((routine) => routine.id == selectedRoutineIdForEdit)) {
      selectedRoutineIdForEdit = store.selectedRoutine?.id ??
          (routines.isEmpty ? '' : routines.first.id);
    }
    final filtered = routines.where((routine) {
      final haystack =
          '${routine.id} ${routine.name} ${routine.academy} ${routine.participant} ${routine.genre} ${routine.division} ${routine.category}'
              .toUpperCase();
      return haystack.contains(query.toUpperCase());
    }).toList();
    final selectedRoutine = firstOrNull(
        routines.where((routine) => routine.id == selectedRoutineIdForEdit));
    final completed =
        store.rankings.where((result) => result.aggregateTotal > 0).length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Panel admin',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(
                      '${store.selectedEvent?.name ?? store.appData?.sourceName ?? 'Evento'} - ${store.selectedBlock?.name ?? 'Bloque'}'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                store.refreshEvents();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 2.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MetricTile(
                icon: Icons.view_agenda,
                value: '${store.blocks.length}',
                label: 'Bloques',
                detail: '${store.visibleRoutines.length} en vista'),
            MetricTile(
                icon: Icons.self_improvement,
                value: '${store.routines.length}',
                label: 'Coreografías',
                detail: '$completed calificadas'),
            MetricTile(
                icon: Icons.groups,
                value: '${store.editableJudges.length}',
                label: 'Jueces',
                detail: 'ATI administra'),
            MetricTile(
                icon: Icons.cloud_upload,
                value: '${store.pendingCount}',
                label: 'Pendientes',
                detail: syncStateLabel(store.syncState)),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ActionChip(
              avatar: const Icon(Icons.upload_file),
              label: const Text('Importar Excel'),
              onPressed: () => widget.onNavigate(AppSection.excel),
            ),
            ActionChip(
              avatar: const Icon(Icons.bar_chart),
              label: const Text('Ranking'),
              onPressed: () => widget.onNavigate(AppSection.scores),
            ),
            ActionChip(
              avatar: const Icon(Icons.star),
              label: const Text('Favoritos'),
              onPressed: () => widget.onNavigate(AppSection.favorites),
            ),
            ActionChip(
              avatar: const Icon(Icons.emoji_events),
              label: const Text('Dictamen'),
              onPressed: () => widget.onNavigate(AppSection.dictamen),
            ),
            ActionChip(
              avatar: const Icon(Icons.picture_as_pdf),
              label: const Text('Exportar PDF'),
              onPressed: () {
                exportResultsPdf(store);
              },
            ),
            ActionChip(
              avatar: exportingDrive
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Exportar Drive'),
              onPressed: exportingDrive ? null : _exportDrive,
            ),
          ],
        ),
        if (driveMessage != null) ...[
          const SizedBox(height: 12),
          DriveExportStatusCard(
            exporting: exportingDrive,
            message: driveMessage!,
          ),
        ],
        const SizedBox(height: 24),
        const SectionHeader(
            title: 'Bloques',
            subtitle: 'Selecciona el bloque activo para revisar o editar'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final block in store.blocks)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    selected: block.blockId == store.selectedBlock?.blockId,
                    label: Text(
                        '${block.name} · ${routineCountForBlock(store, block)}'),
                    onSelected: (_) => store.selectBlock(block),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Editar como juez',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedJudgeForEdit),
                        initialValue: selectedJudgeForEdit.isEmpty
                            ? null
                            : selectedJudgeForEdit,
                        decoration: const InputDecoration(labelText: 'Juez'),
                        items: [
                          for (final judge in store.editableJudges)
                            DropdownMenuItem(value: judge, child: Text(judge))
                        ],
                        onChanged: (value) =>
                            setState(() => selectedJudgeForEdit = value ?? ''),
                      ),
                      const SizedBox(height: 14),
                      if (selectedRoutine != null)
                        SelectedRoutineSummary(
                          routine: selectedRoutine,
                          judge: selectedJudgeForEdit,
                          total: judgeTotalFor(
                              store, selectedRoutine, selectedJudgeForEdit),
                          maxScore: store.templateFor(selectedRoutine).maxScore,
                        ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: selectedRoutine == null ||
                                selectedJudgeForEdit.isEmpty
                            ? null
                            : () {
                                store.beginAdminScoring(
                                    judge: selectedJudgeForEdit,
                                    routine: selectedRoutine);
                                widget.onNavigate(AppSection.judging);
                              },
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Abrir hoja de jueceo'),
                      ),
                      if (store.isAdminEditingAsJudge) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: store.clearAdminScoringOverride,
                          icon: const Icon(Icons.close),
                          label: const Text('Salir de edición'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar coreografía'),
                        onChanged: (value) => setState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      for (final routine in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RoutineListTile(
                            routine: routine,
                            selected: routine.id == selectedRoutineIdForEdit,
                            trailing: Text(
                                '${judgeTotalFor(store, routine, selectedJudgeForEdit).toStringAsFixed(1)} pts'),
                            onTap: () => setState(
                                () => selectedRoutineIdForEdit = routine.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportDrive() async {
    setState(() {
      exportingDrive = true;
      driveMessage = 'Preparando exportación a Google Drive...';
    });
    try {
      final summary = await exportSelectedBlockToDrive(
        widget.store,
        onProgress: (message) {
          if (mounted) setState(() => driveMessage = message);
        },
      );
      if (!mounted) return;
      setState(() {
        driveMessage =
            '${summary.uploadedFiles.length} PDFs exportados a ${summary.rootFolderName}.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(driveMessage!)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => driveMessage = '$error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => exportingDrive = false);
    }
  }
}

class BlocksPage extends StatefulWidget {
  const BlocksPage(
      {super.key, required this.store, required this.onOpenRoutine});

  final JudgingStore store;
  final VoidCallback onOpenRoutine;

  @override
  State<BlocksPage> createState() => _BlocksPageState();
}

class _BlocksPageState extends State<BlocksPage> {
  String query = '';
  RoutineFilter filter = RoutineFilter.all;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final filtered = sortedRoutines(store.visibleRoutines).where((routine) {
      final result = store.resultFor(routine);
      final matchesFilter = switch (filter) {
        RoutineFilter.all => true,
        RoutineFilter.pending => result.aggregateTotal == 0,
        RoutineFilter.scored => result.aggregateTotal > 0,
        RoutineFilter.favorites => store.hasFavorite(routine),
      };
      final haystack =
          '${routine.id} ${routine.name} ${routine.academy} ${routine.participant} ${routine.genre} ${routine.category}'
              .toUpperCase();
      return matchesFilter && haystack.contains(query.toUpperCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar coreografía, academia o género'),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<RoutineFilter>(
                segments: const [
                  ButtonSegment(value: RoutineFilter.all, label: Text('Todas')),
                  ButtonSegment(
                      value: RoutineFilter.pending, label: Text('Pendientes')),
                  ButtonSegment(
                      value: RoutineFilter.scored, label: Text('Calificadas')),
                  ButtonSegment(
                      value: RoutineFilter.favorites,
                      label: Text('Mis favoritas')),
                ],
                selected: {filter},
                onSelectionChanged: (value) =>
                    setState(() => filter = value.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionHeader(
                title:
                    'Coreografías del ${store.selectedBlock?.name.toLowerCase() ?? 'bloque'}',
                subtitle: '${filtered.length} resultados',
              ),
              const SizedBox(height: 12),
              for (final routine in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RoutineListTile(
                    routine: routine,
                    selected: routine.id == store.selectedRoutineId,
                    trailing: FilledButton.tonalIcon(
                      onPressed: () {
                        store.selectRoutine(routine.id);
                        widget.onOpenRoutine();
                      },
                      icon: const Icon(Icons.fact_check),
                      label: const Text('Juecear'),
                    ),
                    onTap: () => store.selectRoutine(routine.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum RoutineFilter { all, pending, scored, favorites }

extension RoutineFilterMeta on RoutineFilter {
  String get label {
    return switch (this) {
      RoutineFilter.all => 'Todas',
      RoutineFilter.pending => 'Pendientes',
      RoutineFilter.scored => 'Calificadas',
      RoutineFilter.favorites => 'Favoritas',
    };
  }

  IconData get icon {
    return switch (this) {
      RoutineFilter.all => Icons.list_alt,
      RoutineFilter.pending => Icons.hourglass_bottom,
      RoutineFilter.scored => Icons.check_circle,
      RoutineFilter.favorites => Icons.star,
    };
  }
}

class PhoneHomePage extends StatelessWidget {
  const PhoneHomePage(
      {super.key, required this.store, required this.onNavigate});

  final JudgingStore store;
  final ValueChanged<AppSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final routines = sortedRoutines(store.visibleRoutines);
    final pending = routines
        .where((routine) => store.resultFor(routine).aggregateTotal == 0)
        .take(1)
        .toList();
    final preview = pending.isEmpty ? routines.take(1).toList() : pending;
    final completed =
        store.rankings.where((result) => result.aggregateTotal > 0).length;
    final nextRoutine =
        preview.isNotEmpty ? preview.first : store.selectedRoutine;
    final syncPercent = store.pendingCount == 0
        ? 100
        : (100 - store.pendingCount * 8).clamp(0, 100);
    final syncDetail = store.pendingCount == 0
        ? 'Todo al día'
        : '${store.pendingCount} pendiente${store.pendingCount == 1 ? '' : 's'}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Levitate',
          titleWidget: const LevitateBrand(isCompact: true),
          subtitle: store.selectedEvent?.name ??
              store.appData?.sourceName ??
              'Jueceo coreografías',
          trailing: IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: store.refreshEvents,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (store.isAdmin) ...[
              EventSelectorButton(store: store),
              BlockSelectorButton(store: store),
            ],
            JudgeSelectorButton(store: store),
            SyncChip(store: store),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashboardJudgeImage(
                  judge: store.scoringJudge,
                  width: double.infinity,
                  height: 128,
                ),
                const SizedBox(height: 16),
                Text('Buenos días,',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                Text(
                  store.selectedJudge.isEmpty ? 'JUEZ' : store.selectedJudge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900, color: levitPink),
                ),
                const SizedBox(height: 4),
                const Text('Estás lista para calificar. Que comience el flow!'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            Widget metricsGrid() => PhoneMetricGrid(
                  children: [
                    MetricTile(
                        icon: Icons.calendar_month,
                        value: '$completed',
                        label: 'Calificadas',
                        detail:
                            '${percentage(completed, store.visibleRoutines.length)}% del bloque'),
                    MetricTile(
                        icon: Icons.cloud_done,
                        value: '$syncPercent%',
                        label: 'Sincronización',
                        detail: syncDetail),
                  ],
                );

            Widget upcoming() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Próximas coreografías'),
                    const SizedBox(height: 10),
                    if (preview.isEmpty)
                      const PhoneEmptyCard(
                          icon: Icons.inbox,
                          title: 'Sin coreografías',
                          message: 'Carga un evento para empezar.')
                    else
                      for (final routine in preview)
                        PhoneRoutineCard(
                          routine: routine,
                          selected: routine.id == nextRoutine?.id,
                          favorite: store.hasFavorite(routine),
                          footer: store.isAdmin
                              ? null
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      store.selectRoutine(routine.id);
                                      onNavigate(AppSection.judging);
                                    },
                                    icon: const Icon(Icons.fact_check),
                                    label: const Text('Juecear'),
                                  ),
                                ),
                          onTap: () => store.selectRoutine(routine.id),
                        ),
                  ],
                );

            if (constraints.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: metricsGrid()),
                  const SizedBox(width: 12),
                  Expanded(child: upcoming()),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                metricsGrid(),
                const SizedBox(height: 16),
                upcoming(),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (!store.isAdmin)
          FilledButton.icon(
            onPressed: nextRoutine == null
                ? null
                : () {
                    store.selectRoutine(nextRoutine.id);
                    onNavigate(AppSection.judging);
                  },
            icon: const Icon(Icons.play_arrow),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Entrar al jueceo'),
            ),
          ),
        if (store.isAdmin) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => onNavigate(AppSection.admin),
            icon: const Icon(Icons.admin_panel_settings),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Panel admin'),
            ),
          ),
        ],
      ],
    );
  }
}

class PhoneAdminPage extends StatefulWidget {
  const PhoneAdminPage(
      {super.key, required this.store, required this.onNavigate});

  final JudgingStore store;
  final ValueChanged<AppSection> onNavigate;

  @override
  State<PhoneAdminPage> createState() => _PhoneAdminPageState();
}

class _PhoneAdminPageState extends State<PhoneAdminPage> {
  String selectedJudgeForEdit = '';
  String selectedRoutineIdForEdit = '';
  String query = '';
  bool exportingDrive = false;
  String? driveMessage;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!store.editableJudges.contains(selectedJudgeForEdit)) {
      selectedJudgeForEdit = store.adminScoringJudge ??
          (store.editableJudges.isEmpty ? '' : store.editableJudges.first);
    }
    final routines = sortedRoutines(store.visibleRoutines);
    if (!routines.any((routine) => routine.id == selectedRoutineIdForEdit)) {
      selectedRoutineIdForEdit = store.selectedRoutine?.id ??
          (routines.isEmpty ? '' : routines.first.id);
    }
    final filtered = routines.where((routine) {
      final haystack =
          '${routine.id} ${routine.name} ${routine.academy} ${routine.participant} ${routine.genre} ${routine.division} ${routine.category}'
              .toUpperCase();
      return haystack.contains(query.toUpperCase());
    }).toList();
    final selectedRoutine = firstOrNull(
        routines.where((routine) => routine.id == selectedRoutineIdForEdit));
    final completed =
        store.rankings.where((result) => result.aggregateTotal > 0).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Panel admin',
          subtitle:
              '${store.selectedEvent?.name ?? store.appData?.sourceName ?? 'Evento'} · ${store.selectedBlock?.name ?? 'Bloque'}',
          trailing: IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: store.refreshEvents,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EventSelectorButton(store: store),
            BlockSelectorButton(store: store),
            SyncChip(store: store),
          ],
        ),
        const SizedBox(height: 14),
        PhoneMetricGrid(
          children: [
            MetricTile(
                icon: Icons.view_agenda,
                value: '${store.blocks.length}',
                label: 'Bloques',
                detail: '${store.visibleRoutines.length} en vista'),
            MetricTile(
                icon: Icons.self_improvement,
                value: '${store.routines.length}',
                label: 'Coreografías',
                detail: '$completed calificadas'),
            MetricTile(
                icon: Icons.groups,
                value: '${store.editableJudges.length}',
                label: 'Jueces',
                detail: 'ATI administra'),
            MetricTile(
                icon: Icons.cloud_upload,
                value: '${store.pendingCount}',
                label: 'Pendientes',
                detail: syncStateLabel(store.syncState)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.upload_file),
              label: const Text('Excel'),
              onPressed: () => widget.onNavigate(AppSection.excel),
            ),
            ActionChip(
              avatar: const Icon(Icons.bar_chart),
              label: const Text('Ranking'),
              onPressed: () => widget.onNavigate(AppSection.scores),
            ),
            ActionChip(
              avatar: const Icon(Icons.star),
              label: const Text('Favoritos'),
              onPressed: () => widget.onNavigate(AppSection.favorites),
            ),
            ActionChip(
              avatar: const Icon(Icons.emoji_events),
              label: const Text('Dictamen'),
              onPressed: () => widget.onNavigate(AppSection.dictamen),
            ),
            ActionChip(
              avatar: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
              onPressed: () {
                exportResultsPdf(store);
              },
            ),
            ActionChip(
              avatar: exportingDrive
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Drive'),
              onPressed: exportingDrive ? null : _exportDrive,
            ),
          ],
        ),
        if (driveMessage != null) ...[
          const SizedBox(height: 12),
          DriveExportStatusCard(
            exporting: exportingDrive,
            message: driveMessage!,
          ),
        ],
        const SizedBox(height: 22),
        const SectionHeader(
            title: 'Bloques', subtitle: 'Selecciona el bloque activo'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final block in store.blocks)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: block.blockId == store.selectedBlock?.blockId,
                    label: Text(
                        '${block.name} · ${routineCountForBlock(store, block)}'),
                    onSelected: (_) => store.selectBlock(block),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeader(
            title: 'Editar como juez',
            subtitle: 'Abrir una hoja de jueceo específica'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedJudgeForEdit),
          isExpanded: true,
          initialValue:
              selectedJudgeForEdit.isEmpty ? null : selectedJudgeForEdit,
          decoration: const InputDecoration(labelText: 'Juez'),
          items: [
            for (final judge in store.editableJudges)
              DropdownMenuItem(value: judge, child: Text(judge))
          ],
          onChanged: (value) =>
              setState(() => selectedJudgeForEdit = value ?? ''),
        ),
        const SizedBox(height: 12),
        if (selectedRoutine != null)
          SelectedRoutineSummary(
            routine: selectedRoutine,
            judge: selectedJudgeForEdit,
            total: judgeTotalFor(store, selectedRoutine, selectedJudgeForEdit),
            maxScore: store.templateFor(selectedRoutine).maxScore,
          ),
        FilledButton.icon(
          onPressed: selectedRoutine == null || selectedJudgeForEdit.isEmpty
              ? null
              : () {
                  store.beginAdminScoring(
                      judge: selectedJudgeForEdit, routine: selectedRoutine);
                  widget.onNavigate(AppSection.judging);
                },
          icon: const Icon(Icons.edit_note),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Abrir hoja de jueceo'),
          ),
        ),
        if (store.isAdminEditingAsJudge) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: store.clearAdminScoringOverride,
            icon: const Icon(Icons.close),
            label: const Text('Salir de edición'),
          ),
        ],
        const SizedBox(height: 22),
        TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Buscar coreografía'),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 14),
        SectionHeader(
            title: 'Coreografías', subtitle: '${filtered.length} resultados'),
        const SizedBox(height: 10),
        for (final routine in filtered)
          PhoneRoutineCard(
            routine: routine,
            selected: routine.id == selectedRoutineIdForEdit,
            favorite: store.hasFavorite(routine),
            footer: Row(
              children: [
                Expanded(
                  child: Text(
                    '${judgeTotalFor(store, routine, selectedJudgeForEdit).toStringAsFixed(1)} pts',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => setState(() => selectedRoutineIdForEdit = routine.id),
          ),
      ],
    );
  }

  Future<void> _exportDrive() async {
    setState(() {
      exportingDrive = true;
      driveMessage = 'Preparando exportación a Google Drive...';
    });
    try {
      final summary = await exportSelectedBlockToDrive(
        widget.store,
        onProgress: (message) {
          if (mounted) setState(() => driveMessage = message);
        },
      );
      if (!mounted) return;
      setState(() {
        driveMessage =
            '${summary.uploadedFiles.length} PDFs exportados a ${summary.rootFolderName}.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(driveMessage!)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => driveMessage = '$error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => exportingDrive = false);
    }
  }
}

class PhoneBlocksPage extends StatefulWidget {
  const PhoneBlocksPage(
      {super.key, required this.store, required this.onOpenRoutine});

  final JudgingStore store;
  final VoidCallback onOpenRoutine;

  @override
  State<PhoneBlocksPage> createState() => _PhoneBlocksPageState();
}

class _PhoneBlocksPageState extends State<PhoneBlocksPage> {
  String query = '';
  RoutineFilter filter = RoutineFilter.all;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final filtered = sortedRoutines(store.visibleRoutines).where((routine) {
      final result = store.resultFor(routine);
      final matchesFilter = switch (filter) {
        RoutineFilter.all => true,
        RoutineFilter.pending => result.aggregateTotal == 0,
        RoutineFilter.scored => result.aggregateTotal > 0,
        RoutineFilter.favorites => store.hasFavorite(routine),
      };
      final haystack =
          '${routine.id} ${routine.name} ${routine.academy} ${routine.participant} ${routine.genre} ${routine.category}'
              .toUpperCase();
      return matchesFilter && haystack.contains(query.toUpperCase());
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Rutinas',
          subtitle: store.selectedBlock?.name ?? 'Bloque activo',
          trailing: IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: store.refreshEvents,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar coreografía, academia o género'),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in RoutineFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: item == filter,
                    avatar: Icon(item.icon, size: 18),
                    label: Text(item.label),
                    onSelected: (_) => setState(() => filter = item),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(
          title:
              'Coreografías del ${store.selectedBlock?.name.toLowerCase() ?? 'bloque'}',
          subtitle: '${filtered.length} resultados',
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const PhoneEmptyCard(
              icon: Icons.search_off,
              title: 'Sin resultados',
              message: 'Probá con otro filtro o búsqueda.')
        else
          for (final routine in filtered)
            PhoneRoutineCard(
              routine: routine,
              selected: routine.id == store.selectedRoutineId,
              favorite: store.hasFavorite(routine),
              footer: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    store.selectRoutine(routine.id);
                    widget.onOpenRoutine();
                  },
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Juecear'),
                ),
              ),
              onTap: () => store.selectRoutine(routine.id),
            ),
      ],
    );
  }
}

class PhoneFavoritesPage extends StatelessWidget {
  const PhoneFavoritesPage({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final rankingBlocks = store.favoriteRankingBlocks;
    final totalVotes =
        rankingBlocks.fold(0, (sum, block) => sum + block.totalVotes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Favoritos',
          subtitle: store.selectedBlock?.name ?? 'Todos los bloques',
          trailing: IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: store.refreshEvents,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 14),
        PhoneMetricGrid(
          children: [
            MetricTile(
              icon: Icons.star,
              value: '$totalVotes',
              label: 'Votos',
              detail: store.pendingCount == 0
                  ? 'Sin pendientes'
                  : '${store.pendingCount} por subir',
            ),
            for (final category in FavoriteCategory.values)
              MetricTile(
                icon: favoriteCategoryIcon(category),
                value: '${favoriteVoteCount(rankingBlocks, category)}',
                label: category.title,
                detail: 'Top por bloque',
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (rankingBlocks.isEmpty)
          const PhoneEmptyCard(
              icon: Icons.star_border,
              title: 'Todavía no hay favoritos',
              message: 'El top 3 de cada bloque aparece acá.')
        else
          for (final block in rankingBlocks)
            PhoneFavoriteRankingBlock(block: block),
      ],
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.store});

  final JudgingStore store;

  @override
  Widget build(BuildContext context) {
    final rankingBlocks = store.favoriteRankingBlocks;
    final totalVotes =
        rankingBlocks.fold(0, (sum, block) => sum + block.totalVotes);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Favoritos',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(store.selectedBlock?.name ?? 'Todos los bloques'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                store.refreshEvents();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 2.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MetricTile(
              icon: Icons.star,
              value: '$totalVotes',
              label: 'Votos',
              detail: store.pendingCount == 0
                  ? 'Sin pendientes'
                  : '${store.pendingCount} por subir',
            ),
            for (final category in FavoriteCategory.values)
              MetricTile(
                icon: favoriteCategoryIcon(category),
                value: '${favoriteVoteCount(rankingBlocks, category)}',
                label: category.title,
                detail: 'Top por bloque',
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (rankingBlocks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.star_border),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Todavía no hay favoritos',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text('El top 3 de cada bloque va a aparecer acá.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final block in rankingBlocks) ...[
            SectionHeader(
              title: block.blockName,
              subtitle:
                  '${block.totalVotes} voto${block.totalVotes == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 10),
            GridView.builder(
              itemCount: block.categories.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 460,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.34,
              ),
              itemBuilder: (context, index) => FavoriteCategoryRankingCard(
                ranking: block.categories[index],
              ),
            ),
            const SizedBox(height: 22),
          ],
      ],
    );
  }
}

class PhoneFavoriteRankingBlock extends StatelessWidget {
  const PhoneFavoriteRankingBlock({super.key, required this.block});

  final FavoriteRankingBlock block;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: block.blockName,
            subtitle:
                '${block.totalVotes} voto${block.totalVotes == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 10),
          for (final ranking in block.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FavoriteCategoryRankingCard(ranking: ranking),
            ),
        ],
      ),
    );
  }
}

class FavoriteCategoryRankingCard extends StatelessWidget {
  const FavoriteCategoryRankingCard({super.key, required this.ranking});

  final FavoriteCategoryRanking ranking;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(favoriteCategoryIcon(ranking.category), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ranking.category.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ranking.items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.44),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Sin votos',
                    style: TextStyle(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w800)),
              )
            else
              for (final item in ranking.items) ...[
                FavoriteRankingRow(item: item),
                if (item != ranking.items.last) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class FavoriteRankingRow extends StatelessWidget {
  const FavoriteRankingRow({super.key, required this.item});

  final FavoriteRankingItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWinner = item.rank == 1;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isWinner
            ? levitPink.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor:
                isWinner ? levitPink : colorScheme.primaryContainer,
            foregroundColor:
                isWinner ? Colors.white : colorScheme.onPrimaryContainer,
            child: Text('${item.rank}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.routine.academy.isEmpty
                      ? item.routine.name
                      : item.routine.academy,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '#${item.routine.id} ${item.routine.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${item.votes}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('voto${item.votes == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class FavoriteSummaryCard extends StatelessWidget {
  const FavoriteSummaryCard({super.key, required this.favorite});

  final FavoriteSelectionSummary favorite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('#${favorite.routine.id}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(favorite.routine.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(routineDetailLine(favorite.routine),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FavoriteInfoChip(icon: Icons.person, text: favorite.judge),
                FavoriteInfoChip(
                    icon: Icons.view_agenda, text: favorite.blockName),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteInfoChip extends StatelessWidget {
  const FavoriteInfoChip({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 178),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class FavoriteButtonsPanel extends StatelessWidget {
  const FavoriteButtonsPanel(
      {super.key,
      required this.store,
      required this.routine,
      required this.judge});

  final JudgingStore store;
  final Routine routine;
  final String judge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Favoritos',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.outline, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (final category in FavoriteCategory.values) ...[
              _FavoriteToggleButton(
                category: category,
                selected: store.isFavorite(routine, category, judge: judge),
                onPressed: () {
                  store.toggleFavorite(category, routine, judge: judge);
                },
              ),
              if (category != FavoriteCategory.values.last)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _FavoriteToggleButton extends StatelessWidget {
  const _FavoriteToggleButton({
    required this.category,
    required this.selected,
    required this.onPressed,
  });

  final FavoriteCategory category;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? levitPink.withValues(alpha: 0.12)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? levitPink.withValues(alpha: 0.48)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(favoriteCategoryIcon(category),
                  color: selected ? levitPink : colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(category.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? levitPink : colorScheme.onSurface,
                        fontWeight: FontWeight.w900)),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? levitPink : colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveJudgeCard extends StatelessWidget {
  const ActiveJudgeCard(
      {super.key, required this.judge, required this.isAdminEditing});

  final String judge;
  final bool isAdminEditing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          child: Icon(isAdminEditing ? Icons.manage_accounts : Icons.person),
        ),
        title: Text(
          judge.isEmpty ? 'Juez sin asignar' : judge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(isAdminEditing ? 'Editando desde admin' : 'Juez activo'),
        trailing: const Icon(Icons.lock_outline),
      ),
    );
  }
}

class RoutinePickerCard extends StatelessWidget {
  const RoutinePickerCard({
    super.key,
    required this.routine,
    required this.routines,
    required this.onChanged,
  });

  final Routine routine;
  final List<Routine> routines;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: levitPink.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.self_improvement, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('routine-picker-${routine.id}'),
                isExpanded: true,
                initialValue: routines.any((item) => item.id == routine.id)
                    ? routine.id
                    : null,
                decoration:
                    const InputDecoration(labelText: 'Coreografía del bloque'),
                items: [
                  for (final item in routines)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text('#${item.id} ${item.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScoreStepperField extends StatelessWidget {
  const ScoreStepperField({
    super.key,
    required this.criterion,
    required this.controller,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
    required this.compact,
  });

  final Criterion criterion;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreCriterionLabel(criterion: criterion, compact: true),
          const SizedBox(height: 10),
          _ScoreStepperControls(
            controller: controller,
            criterion: criterion,
            onChanged: onChanged,
            onDecrement: onDecrement,
            onIncrement: onIncrement,
            compact: true,
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(child: _ScoreCriterionLabel(criterion: criterion)),
          const SizedBox(width: 14),
          _ScoreStepperControls(
            controller: controller,
            criterion: criterion,
            onChanged: onChanged,
            onDecrement: onDecrement,
            onIncrement: onIncrement,
            compact: false,
          ),
        ],
      ),
    );
  }
}

class _ScoreCriterionLabel extends StatelessWidget {
  const _ScoreCriterionLabel({required this.criterion, this.compact = false});

  final Criterion criterion;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${criterion.id}.',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: levitPink, fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(criterion.label,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text('0 a ${_scoreText(criterion.maxScore)} puntos',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.outline, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreStepperControls extends StatelessWidget {
  const _ScoreStepperControls({
    required this.controller,
    required this.criterion,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
    required this.compact,
  });

  final TextEditingController controller;
  final Criterion criterion;
  final ValueChanged<String> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final input = TextField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      maxLength: _scoreMaxLength(criterion.maxScore),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: const InputDecoration(
        counterText: '',
        hintText: '0',
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: onChanged,
    );
    return Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _RoundScoreButton(icon: Icons.remove, onPressed: onDecrement),
        const SizedBox(width: 10),
        if (compact)
          Expanded(child: input)
        else
          SizedBox(width: 64, child: input),
        const SizedBox(width: 10),
        _RoundScoreButton(icon: Icons.add, onPressed: onIncrement),
      ],
    );
  }
}

class _RoundScoreButton extends StatelessWidget {
  const _RoundScoreButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(42),
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurface,
      ),
    );
  }
}

class JudgingPage extends StatefulWidget {
  const JudgingPage({super.key, required this.store, this.onBack});

  final JudgingStore store;
  final VoidCallback? onBack;

  @override
  State<JudgingPage> createState() => _JudgingPageState();
}

class _JudgingPageState extends State<JudgingPage> {
  final Map<int, TextEditingController> controllers = {};
  final feedbackController = TextEditingController();
  final penaltyController = TextEditingController();
  String penaltySelection = '0';
  String? loadedRoutineId;
  String? loadedJudge;
  String? errorMessage;

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    feedbackController.dispose();
    penaltyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final routine = store.selectedRoutine;
    if (routine == null) {
      return const EmptyState(
          icon: Icons.inbox,
          title: 'Sin coreografías',
          message: 'Carga un evento para empezar.');
    }
    final scoringJudge = store.scoringJudge;
    final template = store.templateFor(routine);
    _loadDraftIfNeeded(store, routine, scoringJudge, template);
    final scoreSubtotal = template.criteria.fold<double>(0, (sum, criterion) {
      return sum +
          (double.tryParse(
                  controllers[criterion.id]?.text.replaceAll(',', '.') ?? '') ??
              0);
    });
    final penaltyValue = _currentPenaltyValue();
    final total = scoreSubtotal > 0
        ? (scoreSubtotal + penaltyValue).clamp(0.0, double.infinity).toDouble()
        : 0.0;
    final maxTotal = template.maxScore > 0
        ? template.maxScore
        : template.criteria
            .fold<double>(0, (sum, criterion) => sum + criterion.maxScore);
    final routines = sortedRoutines(store.visibleRoutines);
    final currentIndex = routines.indexWhere((item) => item.id == routine.id);
    final nextRoutine = currentIndex >= 0 && currentIndex + 1 < routines.length
        ? routines[currentIndex + 1]
        : null;

    if (MediaQuery.sizeOf(context).width < 720) {
      return _buildPhoneLayout(
        store: store,
        routine: routine,
        template: template,
        scoringJudge: scoringJudge,
        scoreSubtotal: scoreSubtotal,
        penaltyValue: penaltyValue,
        total: total,
        maxTotal: maxTotal,
        routines: routines,
        currentIndex: currentIndex,
        nextRoutine: nextRoutine,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      children: [
        _buildJudgingHeader(
          context: context,
          routine: routine,
          routines: routines,
          currentIndex: currentIndex,
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 330,
              child: Column(
                children: [
                  ActiveJudgeCard(
                    judge: scoringJudge,
                    isAdminEditing: store.isAdminEditingAsJudge,
                  ),
                  const SizedBox(height: 12),
                  RoutinePickerCard(
                    routine: routine,
                    routines: routines,
                    onChanged: store.selectRoutine,
                  ),
                  const SizedBox(height: 12),
                  _buildTotalPanel(
                    context: context,
                    routine: routine,
                    template: template,
                    scoreSubtotal: scoreSubtotal,
                    penaltyValue: penaltyValue,
                    total: total,
                    maxTotal: maxTotal,
                    nextRoutine: nextRoutine,
                  ),
                  const SizedBox(height: 12),
                  FavoriteButtonsPanel(
                    store: store,
                    routine: routine,
                    judge: scoringJudge,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                children: [
                  ..._buildCriteriaSections(template, compact: false),
                  const SizedBox(height: 12),
                  _buildPenaltyControl(context),
                  const SizedBox(height: 12),
                  TextField(
                    controller: feedbackController,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(
                        labelText: 'Feedback',
                        alignLabelWithHint: true,
                        counterText: ''),
                    maxLength: 300,
                    onChanged: (value) {
                      store.setFeedback(routine, value, judge: scoringJudge);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJudgingHeader({
    required BuildContext context,
    required Routine routine,
    required List<Routine> routines,
    required int currentIndex,
  }) {
    final currentPosition = currentIndex >= 0 ? currentIndex + 1 : 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Volver'),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('#${routine.id}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: levitPink, fontWeight: FontWeight.w900)),
              Text(routine.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              Text(routineDetailLine(routine),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Tag(routine.division),
                  Tag(routine.category),
                  Tag(routine.genre),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 172,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$currentPosition / ${routines.length}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              Text('Coreografías',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: routines.isEmpty ? 0 : currentPosition / routines.length,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalPanel({
    required BuildContext context,
    required Routine routine,
    required JudgingTemplate template,
    required double scoreSubtotal,
    required double penaltyValue,
    required double total,
    required double maxTotal,
    required Routine? nextRoutine,
  }) {
    final hasIncompleteScores = _hasIncompleteScores(template);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Puntaje total',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            Text(
              '${_scoreText(total)} / ${_scoreText(maxTotal)}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: levitPink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            if (hasIncompleteScores) ...[
              const SizedBox(height: 6),
              Text('Asegúrate de llenar todos los campos',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ],
            if (penaltyValue != 0)
              Text(
                  'Subtotal ${_scoreText(scoreSubtotal)} · Penalización ${_scoreText(penaltyValue)}'),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 14),
            _buildSaveButton(
              routine: routine,
              template: template,
              hasNextRoutine: nextRoutine != null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton({
    required Routine routine,
    required JudgingTemplate template,
    required bool hasNextRoutine,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          _save(routine, template, advance: hasNextRoutine);
        },
        icon: Icon(hasNextRoutine ? Icons.arrow_forward : Icons.save),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(hasNextRoutine ? 'Guardar y siguiente' : 'Guardar'),
        ),
      ),
    );
  }

  bool _hasIncompleteScores(JudgingTemplate template) {
    for (final criterion in template.criteria) {
      if ((controllers[criterion.id]?.text.trim() ?? '').isEmpty) {
        return true;
      }
    }
    return false;
  }

  List<Widget> _buildCriteriaSections(JudgingTemplate template,
      {required bool compact}) {
    final sections = groupedCriteriaFor(template);
    return [
      for (final section in sections)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.key.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  for (var index = 0;
                      index < section.value.length;
                      index++) ...[
                    if (index > 0) const SizedBox(height: 10),
                    ScoreStepperField(
                      criterion: section.value[index],
                      controller: controllers[section.value[index].id]!,
                      compact: compact,
                      onChanged: (value) =>
                          _setScoreText(section.value[index], value),
                      onDecrement: () => _adjustScore(section.value[index], -1),
                      onIncrement: () => _adjustScore(section.value[index], 1),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildPhoneLayout({
    required JudgingStore store,
    required Routine routine,
    required JudgingTemplate template,
    required String scoringJudge,
    required double scoreSubtotal,
    required double penaltyValue,
    required double total,
    required double maxTotal,
    required List<Routine> routines,
    required int currentIndex,
    required Routine? nextRoutine,
  }) {
    final currentPosition = currentIndex >= 0 ? currentIndex + 1 : 1;
    final progress =
        maxTotal <= 0 ? 0.0 : (total / maxTotal).clamp(0.0, 1.0).toDouble();
    final hasIncompleteScores = _hasIncompleteScores(template);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (widget.onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Volver'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        PhonePageTitle(
          title: 'Jueceo',
          subtitle: '${store.selectedBlock?.name ?? 'Bloque'} · $scoringJudge',
          trailing: Chip(label: Text('$currentPosition / ${routines.length}')),
        ),
        const SizedBox(height: 12),
        ActiveJudgeCard(
          judge: scoringJudge,
          isAdminEditing: store.isAdminEditingAsJudge,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('routine-${routine.id}'),
          isExpanded: true,
          initialValue: routine.id,
          decoration: const InputDecoration(labelText: 'Rutina'),
          items: [
            for (final item in routines)
              DropdownMenuItem(
                value: item.id,
                child: Text('#${item.id} ${item.name}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            if (value != null) store.selectRoutine(value);
          },
        ),
        const SizedBox(height: 12),
        PhoneRoutineCard(
          routine: routine,
          selected: true,
          favorite: store.hasFavorite(routine),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(template.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${_scoreText(total)} / ${_scoreText(maxTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              if (penaltyValue != 0) ...[
                const SizedBox(height: 4),
                Text(
                    'Subtotal ${_scoreText(scoreSubtotal)} · Penalización ${_scoreText(penaltyValue)}'),
              ],
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
        FavoriteButtonsPanel(
          store: store,
          routine: routine,
          judge: scoringJudge,
        ),
        const SizedBox(height: 12),
        const SectionHeader(
          title: 'Puntajes',
          subtitle: 'Completa cada criterio',
        ),
        const SizedBox(height: 10),
        ..._buildCriteriaSections(template, compact: true),
        const SizedBox(height: 10),
        _buildPenaltyControl(context),
        const SizedBox(height: 10),
        TextField(
          controller: feedbackController,
          minLines: 4,
          maxLines: 6,
          decoration: const InputDecoration(
              labelText: 'Feedback', alignLabelWithHint: true, counterText: ''),
          maxLength: 300,
          onChanged: (value) {
            store.setFeedback(routine, value, judge: scoringJudge);
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Puntaje total',
                    style: Theme.of(context).textTheme.labelLarge),
                Text(
                  '${_scoreText(total)} / ${_scoreText(maxTotal)}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: levitPink, fontWeight: FontWeight.w900),
                ),
                if (hasIncompleteScores) ...[
                  const SizedBox(height: 6),
                  Text('Asegúrate de llenar todos los campos',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ],
                if (penaltyValue != 0)
                  Text(
                      'Subtotal ${_scoreText(scoreSubtotal)} · Penalización ${_scoreText(penaltyValue)}'),
                if (errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(errorMessage!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 14),
                _buildSaveButton(
                  routine: routine,
                  template: template,
                  hasNextRoutine: nextRoutine != null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _setScoreText(Criterion criterion, String value) {
    final controller = controllers[criterion.id];
    if (controller == null) return;
    final normalized = _normalizedScoreText(value, criterion.maxScore);
    if (controller.text != normalized) {
      controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    setState(() => errorMessage = null);
  }

  void _adjustScore(Criterion criterion, int delta) {
    final controller = controllers[criterion.id];
    if (controller == null) return;
    final current = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    final next = (current + delta).clamp(0, criterion.maxScore).toDouble();
    final nextText = _scoreText(next);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    setState(() => errorMessage = null);
  }

  Widget _buildPenaltyControl(BuildContext context) {
    const options = ['0', '-1', '-2', 'Otro'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Penalización', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option),
                    selected: penaltySelection == option,
                    onSelected: (_) {
                      setState(() {
                        penaltySelection = option;
                        if (option != 'Otro') {
                          penaltyController.clear();
                        }
                        errorMessage = null;
                      });
                    },
                  ),
              ],
            ),
            if (penaltySelection == 'Otro') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: penaltyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    helperText: 'Entre -100 y 0',
                  ),
                  onChanged: (_) => setState(() => errorMessage = null),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _loadDraftIfNeeded(JudgingStore store, Routine routine, String judge,
      JudgingTemplate template) {
    if (loadedRoutineId == routine.id && loadedJudge == judge) return;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    controllers.clear();
    for (final criterion in template.criteria) {
      final saved = store.scoreFor(routine, judge, criterion);
      controllers[criterion.id] = TextEditingController(
          text: saved > 0
              ? _normalizedScoreText(_scoreText(saved), criterion.maxScore)
              : '');
    }
    feedbackController.text =
        store.feedback[store.feedbackKey(routine.id, judge)] ?? '';
    _loadPenalty(store.penaltyFor(routine, judge));
    loadedRoutineId = routine.id;
    loadedJudge = judge;
    errorMessage = null;
  }

  Future<void> _save(Routine routine, JudgingTemplate template,
      {required bool advance}) async {
    final values = <int, double>{};
    for (final criterion in template.criteria) {
      final text = controllers[criterion.id]?.text ?? '';
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null || value < 0 || value > criterion.maxScore) {
        setState(() {
          errorMessage =
              'Completa todas las notas con números entre 0 y ${_scoreText(criterion.maxScore)}.';
        });
        return;
      }
      values[criterion.id] = value;
    }
    await widget.store.submitScores(
      routine,
      values,
      penalty: _currentPenaltyValue(),
    );
    if (advance) {
      final routines = sortedRoutines(widget.store.visibleRoutines);
      final currentIndex = routines.indexWhere((item) => item.id == routine.id);
      if (currentIndex >= 0 && currentIndex + 1 < routines.length) {
        widget.store.selectRoutine(routines[currentIndex + 1].id);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calificaciones guardadas.')));
    }
  }

  void _loadPenalty(double value) {
    if (value.abs() < 0.0001) {
      penaltySelection = '0';
      penaltyController.clear();
    } else if ((value + 1).abs() < 0.0001) {
      penaltySelection = '-1';
      penaltyController.clear();
    } else if ((value + 2).abs() < 0.0001) {
      penaltySelection = '-2';
      penaltyController.clear();
    } else {
      penaltySelection = 'Otro';
      penaltyController.text = _scoreText(value);
    }
  }

  double _currentPenaltyValue() {
    if (penaltySelection != 'Otro') {
      return double.tryParse(penaltySelection) ?? 0;
    }
    final value =
        double.tryParse(penaltyController.text.replaceAll(',', '.')) ?? 0;
    return _normalizedPenalty(value);
  }

  double _normalizedPenalty(double value) {
    final signed = value > 0 ? -value : value;
    return signed.clamp(-100.0, 0.0).toDouble();
  }
}

class PhoneScoresPage extends StatefulWidget {
  const PhoneScoresPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<PhoneScoresPage> createState() => _PhoneScoresPageState();
}

class _PhoneScoresPageState extends State<PhoneScoresPage> {
  String selectedAcademy = allRankingFilter;
  String selectedGenre = allRankingFilter;

  @override
  Widget build(BuildContext context) {
    final results = widget.store.rankings;
    final filtered = filteredRankingResults(
      results,
      selectedAcademy: selectedAcademy,
      selectedGenre: selectedGenre,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Ranking',
          subtitle: '${filtered.length} de ${results.length} resultados',
          trailing: IconButton.filledTonal(
            tooltip: 'Exportar PDF',
            onPressed: () {
              exportResultsPdf(widget.store);
            },
            icon: const Icon(Icons.picture_as_pdf),
          ),
        ),
        const SizedBox(height: 14),
        RankingFilterControls(
          results: results,
          selectedAcademy: selectedAcademy,
          selectedGenre: selectedGenre,
          onAcademyChanged: (value) => setState(() => selectedAcademy = value),
          onGenreChanged: (value) => setState(() => selectedGenre = value),
          onClear: () => setState(() {
            selectedAcademy = allRankingFilter;
            selectedGenre = allRankingFilter;
          }),
        ),
        const SizedBox(height: 14),
        if (results.isEmpty)
          const PhoneEmptyCard(
              icon: Icons.bar_chart,
              title: 'Sin resultados',
              message: 'Todavía no hay calificaciones para mostrar.')
        else if (filtered.isEmpty)
          const PhoneEmptyCard(
              icon: Icons.filter_alt_off,
              title: 'Sin coincidencias',
              message: 'Cambia los filtros para ver mas resultados.')
        else
          for (final indexed in filtered.indexed)
            PhoneResultCard(
              result: indexed.$2,
              place: indexed.$2.aggregateTotal > 0 ? indexed.$1 + 1 : null,
              judges: widget.store.judges,
            ),
      ],
    );
  }
}

class RankingFilterControls extends StatelessWidget {
  const RankingFilterControls({
    super.key,
    required this.results,
    required this.selectedAcademy,
    required this.selectedGenre,
    required this.onAcademyChanged,
    required this.onGenreChanged,
    required this.onClear,
  });

  final List<RoutineResult> results;
  final String selectedAcademy;
  final String selectedGenre;
  final ValueChanged<String> onAcademyChanged;
  final ValueChanged<String> onGenreChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final academies = rankingFilterValues(
      results.map((result) => result.routine.academy),
    );
    final genres = rankingFilterValues(
      results.map((result) => result.routine.genre),
    );
    final academyValue = academies.contains(selectedAcademy)
        ? selectedAcademy
        : allRankingFilter;
    final genreValue =
        genres.contains(selectedGenre) ? selectedGenre : allRankingFilter;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            key: ValueKey('academy-$academyValue-${academies.length}'),
            initialValue: academyValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Academia',
              prefixIcon: Icon(Icons.school),
            ),
            items: [
              for (final academy in academies)
                DropdownMenuItem(value: academy, child: Text(academy)),
            ],
            onChanged: (value) {
              if (value != null) onAcademyChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            key: ValueKey('genre-$genreValue-${genres.length}'),
            initialValue: genreValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Género',
              prefixIcon: Icon(Icons.category),
            ),
            items: [
              for (final genre in genres)
                DropdownMenuItem(value: genre, child: Text(genre)),
            ],
            onChanged: (value) {
              if (value != null) onGenreChanged(value);
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed:
              academyValue == allRankingFilter && genreValue == allRankingFilter
                  ? null
                  : onClear,
          icon: const Icon(Icons.filter_alt_off),
          label: const Text('Limpiar'),
        ),
      ],
    );
  }
}

class PhoneDictamenPage extends StatefulWidget {
  const PhoneDictamenPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<PhoneDictamenPage> createState() => _PhoneDictamenPageState();
}

class _PhoneDictamenPageState extends State<PhoneDictamenPage> {
  String? selectedGroupKey;

  @override
  Widget build(BuildContext context) {
    final groups = dictamenGroups(widget.store.rankings);
    if (groups.isEmpty) {
      return const EmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'Sin dictamen',
          message: 'Todavía no hay coreografías para mostrar.');
    }
    selectedGroupKey = groups.containsKey(selectedGroupKey)
        ? selectedGroupKey
        : groups.keys.first;
    final selectedResults = groups[selectedGroupKey] ?? const <RoutineResult>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        PhonePageTitle(
          title: 'Dictamen',
          subtitle: 'Resultados oficiales',
          trailing: IconButton.filledTonal(
            tooltip: 'Exportar PDF',
            onPressed: () {
              exportResultsPdf(
                widget.store,
                results: selectedResults,
                title: 'Dictamen final - ${selectedGroupKey ?? ''}',
                filename:
                    'dictamen-${stableRemoteId(selectedGroupKey ?? 'grupo')}.pdf',
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedGroupKey),
          isExpanded: true,
          initialValue: selectedGroupKey,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            for (final entry in groups.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  '${entry.key} · ${entry.value.length}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => selectedGroupKey = value);
          },
        ),
        const SizedBox(height: 18),
        SectionHeader(
          title: selectedGroupKey ?? '',
          subtitle: '${selectedResults.length} coreografías',
        ),
        const SizedBox(height: 10),
        if (selectedResults.isEmpty)
          const PhoneEmptyCard(
              icon: Icons.emoji_events_outlined,
              title: 'Sin resultados',
              message: 'Este grupo todavía no tiene puntajes.')
        else ...[
          for (final indexed in selectedResults.take(3).indexed)
            PhonePodiumCard(result: indexed.$2, place: indexed.$1 + 1),
          const SizedBox(height: 12),
          const SectionHeader(
              title: 'Listado completo', subtitle: 'Ordenado por puntaje'),
          const SizedBox(height: 10),
          for (final indexed in selectedResults.indexed)
            ListTile(
              leading: CircleAvatar(child: Text('${indexed.$1 + 1}')),
              title: Text(
                  '#${indexed.$2.routine.id} ${indexed.$2.routine.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(indexed.$2.routine.academy,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(indexed.$2.aggregateTotal > 0
                  ? indexed.$2.aggregateTotal.toStringAsFixed(2)
                  : '-'),
            ),
        ],
      ],
    );
  }
}

class ScoresPage extends StatefulWidget {
  const ScoresPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends State<ScoresPage> {
  String selectedAcademy = allRankingFilter;
  String selectedGenre = allRankingFilter;

  @override
  Widget build(BuildContext context) {
    final results = widget.store.rankings;
    final filtered = filteredRankingResults(
      results,
      selectedAcademy: selectedAcademy,
      selectedGenre: selectedGenre,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${filtered.length} de ${results.length} resultados',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      exportResultsPdf(widget.store);
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RankingFilterControls(
                results: results,
                selectedAcademy: selectedAcademy,
                selectedGenre: selectedGenre,
                onAcademyChanged: (value) =>
                    setState(() => selectedAcademy = value),
                onGenreChanged: (value) =>
                    setState(() => selectedGenre = value),
                onClear: () => setState(() {
                  selectedAcademy = allRankingFilter;
                  selectedGenre = allRankingFilter;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Pos')),
                const DataColumn(label: Text('#')),
                const DataColumn(label: Text('Coreografía')),
                const DataColumn(label: Text('Academia')),
                const DataColumn(label: Text('Género')),
                for (final judge in widget.store.judges)
                  DataColumn(label: Text(judge)),
                const DataColumn(label: Text('Penal.')),
                const DataColumn(label: Text('Total')),
              ],
              rows: [
                for (final indexed in filtered.indexed)
                  DataRow(cells: [
                    DataCell(Text(indexed.$2.aggregateTotal > 0
                        ? '${indexed.$1 + 1}'
                        : '-')),
                    DataCell(Text(indexed.$2.routine.id)),
                    DataCell(SizedBox(
                        width: 220,
                        child: Text(indexed.$2.routine.name,
                            overflow: TextOverflow.ellipsis))),
                    DataCell(SizedBox(
                        width: 220,
                        child: Text(indexed.$2.routine.academy,
                            overflow: TextOverflow.ellipsis))),
                    DataCell(Text(indexed.$2.routine.genre)),
                    for (final judge in widget.store.judges)
                      DataCell(Text((indexed.$2.judgeTotals[judge] ?? 0)
                          .toStringAsFixed(1))),
                    DataCell(Text(indexed.$2.penalty == 0
                        ? '-'
                        : indexed.$2.penalty.toStringAsFixed(1))),
                    DataCell(Text(indexed.$2.aggregateTotal > 0
                        ? indexed.$2.aggregateTotal.toStringAsFixed(2)
                        : '-')),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DictamenPage extends StatefulWidget {
  const DictamenPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<DictamenPage> createState() => _DictamenPageState();
}

class _DictamenPageState extends State<DictamenPage> {
  String? selectedGroupKey;

  @override
  Widget build(BuildContext context) {
    final groups = dictamenGroups(widget.store.rankings);
    if (groups.isEmpty) {
      return const EmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'Sin dictamen',
          message: 'Todavía no hay coreografías para mostrar.');
    }
    selectedGroupKey = groups.containsKey(selectedGroupKey)
        ? selectedGroupKey
        : groups.keys.first;
    final selectedResults = groups[selectedGroupKey] ?? const <RoutineResult>[];

    return Row(
      children: [
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Dictamen final',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final entry in groups.entries)
                Card(
                  color: entry.key == selectedGroupKey
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    title: Text(entry.key,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${entry.value.length} coreografías'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => selectedGroupKey = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedGroupKey ?? '',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const Text('Resultados oficiales'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      exportResultsPdf(
                        widget.store,
                        results: selectedResults,
                        title: 'Dictamen final - ${selectedGroupKey ?? ''}',
                        filename:
                            'dictamen-${stableRemoteId(selectedGroupKey ?? 'grupo')}.pdf',
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Descargar PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                      child: PodiumTile(
                          place: 2,
                          result: selectedResults.length > 1
                              ? selectedResults[1]
                              : null)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: PodiumTile(
                          place: 1,
                          result: selectedResults.isNotEmpty
                              ? selectedResults[0]
                              : null,
                          featured: true)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: PodiumTile(
                          place: 3,
                          result: selectedResults.length > 2
                              ? selectedResults[2]
                              : null)),
                ],
              ),
              const SizedBox(height: 24),
              for (final indexed in selectedResults.indexed)
                ListTile(
                  leading: CircleAvatar(child: Text('${indexed.$1 + 1}')),
                  title: Text(
                      '#${indexed.$2.routine.id} ${indexed.$2.routine.name}'),
                  subtitle: Text(indexed.$2.routine.academy),
                  trailing: Text(indexed.$2.aggregateTotal > 0
                      ? indexed.$2.aggregateTotal.toStringAsFixed(2)
                      : '-'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ExcelImportPage extends StatefulWidget {
  const ExcelImportPage({super.key, required this.store});

  final JudgingStore store;

  @override
  State<ExcelImportPage> createState() => _ExcelImportPageState();
}

class _ExcelImportPageState extends State<ExcelImportPage> {
  late final TextEditingController eventNameController;
  late final TextEditingController eventSlugController;
  PlatformFile? selectedFile;
  ExcelImportSummary? lastUpload;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    final event = widget.store.selectedEvent;
    eventNameController =
        TextEditingController(text: event?.name ?? 'Competencia Levitate');
    eventSlugController = TextEditingController(
        text: event?.slug ??
            stableRemoteId(event?.name ?? 'competencia-levitate'));
  }

  @override
  void dispose() {
    eventNameController.dispose();
    eventSlugController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Subir Excel',
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text(
            'El archivo queda pendiente en Supabase para procesarse con el mismo contrato de datos.'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                TextField(
                  controller: eventNameController,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del evento'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: eventSlugController,
                  decoration:
                      const InputDecoration(labelText: 'Slug del evento'),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: Text(selectedFile?.name ?? 'Seleccionar Excel'),
                  subtitle: Text(selectedFile == null
                      ? 'Formatos .xlsx o .xls'
                      : '${selectedFile!.size} bytes'),
                  trailing: OutlinedButton.icon(
                    onPressed: () {
                      _pickFile();
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Elegir'),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: uploading || selectedFile == null
                      ? null
                      : () {
                          _upload();
                        },
                  icon: uploading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(uploading ? 'Subiendo' : 'Subir Excel'),
                ),
                if (lastUpload != null) ...[
                  const SizedBox(height: 16),
                  ListTile(
                    leading:
                        const Icon(Icons.check_circle, color: Colors.green),
                    title: Text(lastUpload!.fileName),
                    subtitle: Text(
                        '${lastUpload!.eventName} · ${lastUpload!.fileSize} bytes'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => selectedFile = result.files.single);
  }

  Future<void> _upload() async {
    final file = selectedFile;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo leer el archivo seleccionado.')));
      return;
    }
    setState(() => uploading = true);
    try {
      final summary = await widget.store.uploadExcelImport(
        fileName: file.name,
        bytes: bytes,
        eventName: eventNameController.text,
        eventSlug: eventSlugController.text,
      );
      setState(() => lastUpload = summary);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel subido a Supabase.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }
}

class PhonePageTitle extends StatelessWidget {
  const PhonePageTitle(
      {super.key,
      required this.title,
      required this.subtitle,
      this.titleWidget,
      this.trailing});

  final String title;
  final String subtitle;
  final Widget? titleWidget;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget ??
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class PhoneMetricGrid extends StatelessWidget {
  const PhoneMetricGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

class PhoneEmptyCard extends StatelessWidget {
  const PhoneEmptyCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.primary,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneRoutineCard extends StatelessWidget {
  const PhoneRoutineCard(
      {super.key,
      required this.routine,
      required this.selected,
      this.favorite = false,
      this.footer,
      this.onTap});

  final Routine routine;
  final bool selected;
  final bool favorite;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.62)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('#${routine.id}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(routine.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        Text(routineDetailLine(routine),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (favorite)
                    Icon(Icons.star, color: colorScheme.primary, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Tag(routine.division),
                  Tag(routine.category),
                  Tag(routine.genre),
                ],
              ),
              if (footer != null) ...[
                const Divider(height: 18),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PhoneFavoriteTile extends StatelessWidget {
  const PhoneFavoriteTile({super.key, required this.favorite});

  final FavoriteSelectionSummary favorite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('#${favorite.routine.id}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(favorite.routine.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(routineDetailLine(favorite.routine),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FavoriteInfoChip(icon: Icons.person, text: favorite.judge),
                FavoriteInfoChip(
                    icon: Icons.view_agenda, text: favorite.blockName),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneResultCard extends StatelessWidget {
  const PhoneResultCard(
      {super.key,
      required this.result,
      required this.place,
      required this.judges});

  final RoutineResult result;
  final int? place;
  final List<String> judges;

  @override
  Widget build(BuildContext context) {
    final total = result.aggregateTotal > 0
        ? result.aggregateTotal.toStringAsFixed(2)
        : '-';
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(place == null ? '-' : '$place')),
        title: Text('#${result.routine.id} ${result.routine.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(routineDetailLine(result.routine),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing:
            Text(total, style: const TextStyle(fontWeight: FontWeight.w900)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Tag(result.routine.genre),
              Tag(result.routine.division),
              Tag(result.routine.category),
            ],
          ),
          const SizedBox(height: 10),
          if (result.penalty != 0) ...[
            Row(
              children: [
                const Expanded(child: Text('Penalización total')),
                Text(result.penalty.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const Divider(height: 16),
          ],
          for (final judge in judges)
            Row(
              children: [
                Expanded(child: Text(judge)),
                Text(
                    '${(result.judgeTotals[judge] ?? 0).toStringAsFixed(1)}'
                    '${(result.judgePenalties[judge] ?? 0) == 0 ? '' : ' (${(result.judgePenalties[judge] ?? 0).toStringAsFixed(1)})'}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
        ],
      ),
    );
  }
}

class PhonePodiumCard extends StatelessWidget {
  const PhonePodiumCard({super.key, required this.result, required this.place});

  final RoutineResult result;
  final int place;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final featured = place == 1;
    return Card(
      color: featured ? levitPink : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  featured ? Colors.amber : colorScheme.primaryContainer,
              child: Text('$place',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${result.routine.id} ${result.routine.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: featured ? Colors.white : null,
                          fontWeight: FontWeight.w900)),
                  Text(routineDetailLine(result.routine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: featured ? Colors.white : null)),
                ],
              ),
            ),
            Text(
              result.aggregateTotal > 0
                  ? result.aggregateTotal.toStringAsFixed(1)
                  : '-',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: featured ? Colors.white : null,
                  fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile(
      {super.key,
      required this.icon,
      required this.value,
      required this.label,
      required this.detail});

  final IconData icon;
  final String value;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.primary,
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriveExportStatusCard extends StatelessWidget {
  const DriveExportStatusCard({
    super.key,
    required this.exporting,
    required this.message,
  });

  final bool exporting;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (exporting)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.cloud_done, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {super.key, required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class RoutineListTile extends StatelessWidget {
  const RoutineListTile(
      {super.key,
      required this.routine,
      required this.selected,
      this.trailing,
      this.onTap});

  final Routine routine;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.60)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('#${routine.id}',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    Text(routineDetailLine(routine),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Wrap(
                      spacing: 6,
                      children: [
                        Tag(routine.division),
                        Tag(routine.category),
                        Tag(routine.genre),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(text.trim().isEmpty ? 'SIN DATO' : text.toUpperCase(),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      visualDensity: VisualDensity.compact,
      labelStyle: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class SelectedRoutineSummary extends StatelessWidget {
  const SelectedRoutineSummary(
      {super.key,
      required this.routine,
      required this.judge,
      required this.total,
      required this.maxScore});

  final Routine routine;
  final String judge;
  final double total;
  final double maxScore;

  @override
  Widget build(BuildContext context) {
    final resolvedMax = maxScore > 0 ? maxScore : 25;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#${routine.id} ${routine.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(routineDetailLine(routine),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              Tag(routine.division),
              Tag(routine.category),
              Tag(routine.genre)
            ]),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text(judge.isEmpty ? 'Juez' : judge)),
                Text(
                    '${total.toStringAsFixed(1)} / ${resolvedMax.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PodiumTile extends StatelessWidget {
  const PodiumTile(
      {super.key,
      required this.place,
      required this.result,
      this.featured = false});

  final int place;
  final RoutineResult? result;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: featured ? levitPink : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 18, vertical: featured ? 36 : 24),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor:
                  featured ? Colors.amber : colorScheme.primaryContainer,
              child: Text('$place',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 14),
            Text(
              result == null ? '-' : routineDetailLine(result!.routine),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: featured ? Colors.white : null),
            ),
            const SizedBox(height: 10),
            Text(
              result == null || result!.aggregateTotal == 0
                  ? '-'
                  : result!.aggregateTotal.toStringAsFixed(1),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: featured ? Colors.white : null),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

List<Routine> sortedRoutines(List<Routine> routines) {
  final copy = [...routines];
  copy.sort((left, right) {
    final leftNumber = int.tryParse(left.id) ?? 1 << 30;
    final rightNumber = int.tryParse(right.id) ?? 1 << 30;
    if (leftNumber == rightNumber) return left.id.compareTo(right.id);
    return leftNumber.compareTo(rightNumber);
  });
  return copy;
}

String routineDetailLine(Routine routine) {
  final participant = routine.participant.trim();
  if (participant.isEmpty) return routine.academy;
  if (routine.academy.trim().isEmpty) return participant;
  return '${routine.academy} · $participant';
}

const allRankingFilter = 'Todas';

List<String> rankingFilterValues(Iterable<String> values) {
  final unique = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort((left, right) => left.compareTo(right));
  return [allRankingFilter, ...unique];
}

List<RoutineResult> filteredRankingResults(
  List<RoutineResult> results, {
  required String selectedAcademy,
  required String selectedGenre,
}) {
  return results.where((result) {
    final matchesAcademy = selectedAcademy == allRankingFilter ||
        result.routine.academy == selectedAcademy;
    final matchesGenre = selectedGenre == allRankingFilter ||
        result.routine.genre == selectedGenre;
    return matchesAcademy && matchesGenre;
  }).toList();
}

int percentage(int value, int total) {
  if (total <= 0) return 0;
  return (value / total * 100).round();
}

int routineCountForBlock(JudgingStore store, DanceBlock block) {
  return routinesForBlock(store, block).length;
}

List<Routine> routinesForBlock(JudgingStore store, DanceBlock block) {
  final routineIds = block.routines.map((routine) => routine.id).toSet();
  return sortedRoutines(store.routines
      .where((routine) =>
          routineIds.contains(routine.id) ||
          routine.blockId == block.blockId ||
          routine.block == block.name)
      .toList());
}

double judgeTotalFor(JudgingStore store, Routine routine, String judge) {
  if (judge.isEmpty) return 0;
  final subtotal = store.templateFor(routine).criteria.fold<double>(
      0, (sum, criterion) => sum + store.scoreFor(routine, judge, criterion));
  return subtotal > 0
      ? (subtotal + store.penaltyFor(routine, judge))
          .clamp(0.0, double.infinity)
          .toDouble()
      : 0;
}

IconData favoriteCategoryIcon(FavoriteCategory category) {
  return switch (category) {
    FavoriteCategory.costume => Icons.checkroom,
    FavoriteCategory.choreography => Icons.self_improvement,
    FavoriteCategory.music => Icons.music_note,
  };
}

int favoriteVoteCount(
    List<FavoriteRankingBlock> blocks, FavoriteCategory category) {
  var total = 0;
  for (final block in blocks) {
    for (final ranking in block.categories) {
      if (ranking.category == category) total += ranking.totalVotes;
    }
  }
  return total;
}

Map<String, List<RoutineResult>> dictamenGroups(List<RoutineResult> results) {
  final groups = <String, List<RoutineResult>>{};
  for (final result in results) {
    final key =
        '${result.routine.genre} - ${result.routine.division} - ${result.routine.category}';
    groups.putIfAbsent(key, () => []).add(result);
  }
  for (final values in groups.values) {
    values.sort((left, right) {
      final totalCompare = right.aggregateTotal.compareTo(left.aggregateTotal);
      if (totalCompare != 0) return totalCompare;
      return (int.tryParse(left.routine.id) ?? 0)
          .compareTo(int.tryParse(right.routine.id) ?? 0);
    });
  }
  return groups;
}

T? firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

Future<GoogleDriveExportSummary> exportSelectedBlockToDrive(
  JudgingStore store, {
  ValueChanged<String>? onProgress,
}) async {
  final block = store.selectedBlock;
  if (block == null) {
    throw StateError('No hay bloque seleccionado.');
  }
  final judges = store.editableJudges;
  if (judges.isEmpty) {
    throw StateError('No hay jueces para exportar.');
  }
  final routines = routinesForBlock(store, block);
  if (routines.isEmpty) {
    throw StateError('No hay coreografías en ${block.name}.');
  }

  final drive = GoogleDriveService(
    clientId: googleClientId,
    serverClientId: googleServerClientId,
  );
  final uploaded = <GoogleDriveUploadedFile>[];
  final totalFiles = routines.length * judges.length;
  var completed = 0;

  for (final routine in routines) {
    final academyFolder = driveSafeName(routine.academy, fallback: 'Academia');
    final routineFolder = driveSafeName('#${routine.id} ${routine.name}',
        fallback: 'Coreografía');
    for (final judge in judges) {
      completed += 1;
      onProgress?.call(
          'Subiendo $completed / $totalFiles: $routineFolder - $judge...');
      final bytes = await buildJudgingSheetPdfBytes(
        store,
        routine: routine,
        judge: judge,
        blockName: block.name,
      );
      final fileName = '${driveSafeName(routineFolder)} - '
          '${driveSafeName(judge, fallback: 'Juez')}.pdf';
      final file = await drive.uploadPdf(
        bytes: bytes,
        fileName: fileName,
        folderPath: [
          googleDriveRootFolder,
          driveSafeName(block.name, fallback: 'Bloque'),
          academyFolder,
          routineFolder,
        ],
      );
      uploaded.add(file);
    }
  }
  return GoogleDriveExportSummary(
    rootFolderName: googleDriveRootFolder,
    uploadedFiles: uploaded,
  );
}

String driveSafeName(String value, {String fallback = 'Archivo'}) {
  final clean = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? fallback : clean;
}

Future<void> exportResultsPdf(
  JudgingStore store, {
  List<RoutineResult>? results,
  String title = 'Calificaciones y dictamen final',
  String filename = 'calificaciones-dictamen-final.pdf',
}) async {
  final bytes = await buildResultsPdfBytes(
    store,
    results: results,
    title: title,
  );
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<Uint8List> buildResultsPdfBytes(
  JudgingStore store, {
  List<RoutineResult>? results,
  String title = 'Calificaciones y dictamen final',
}) async {
  final document = pw.Document();
  final exportResults = results ?? store.rankings;
  final judges =
      store.editableJudges.isEmpty ? store.judges : store.editableJudges;
  final logo = await _loadPdfLogo();
  final positionByRoutineId = {
    for (final indexed in exportResults.indexed)
      indexed.$2.routine.id:
          indexed.$2.aggregateTotal > 0 ? indexed.$1 + 1 : null
  };
  final groupedResults = <String, List<RoutineResult>>{};
  for (final result in exportResults) {
    final template = store.templateFor(result.routine);
    final key = template.genre.isEmpty ? result.routine.genre : template.genre;
    groupedResults.putIfAbsent(key, () => []).add(result);
  }

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        _pdfHeader(
          logo: logo,
          title: title,
          subtitle:
              '${store.selectedBlock?.name ?? store.appData?.sourceName ?? store.selectedEvent?.name ?? ''} · ${exportResults.length} coreografías',
        ),
        for (final entry in groupedResults.entries) ...[
          pw.SizedBox(height: 12),
          _pdfResultsGroup(
            store: store,
            title: entry.key,
            results: entry.value,
            judges: judges,
            positionByRoutineId: positionByRoutineId,
          ),
        ],
      ],
    ),
  );
  return document.save();
}

Future<Uint8List> buildJudgingSheetPdfBytes(
  JudgingStore store, {
  required Routine routine,
  required String judge,
  String? blockName,
}) async {
  final document = pw.Document();
  final template = store.templateFor(routine);
  final logo = await _loadPdfLogo();
  final subtotal = template.criteria.fold<double>(
    0,
    (sum, criterion) => sum + store.scoreFor(routine, judge, criterion),
  );
  final penalty = store.penaltyFor(routine, judge);
  final total = subtotal > 0
      ? (subtotal + penalty).clamp(0.0, double.infinity).toDouble()
      : 0.0;
  final maxTotal = template.maxScore > 0
      ? template.maxScore
      : template.criteria.fold<double>(
          0,
          (sum, criterion) => sum + criterion.maxScore,
        );
  final feedback = store.feedback[store.feedbackKey(routine.id, judge)] ?? '';

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        _pdfHeader(
          logo: logo,
          title: 'Hoja de jueceo',
          subtitle:
              '${blockName ?? store.selectedBlock?.name ?? routine.block} · $judge',
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            color: PdfColors.grey100,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('#${routine.id} ${routine.name}',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(routine.academy),
              pw.Text(
                  '${routine.genre} · ${routine.division} · ${routine.category}'),
              if (routine.choreographer.trim().isNotEmpty)
                pw.Text('Coreografo/a: ${routine.choreographer}'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(template.title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle:
              pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: ['#', 'Seccion', 'Criterio', 'Max.', 'Puntaje'],
          data: [
            for (final criterion in template.criteria)
              [
                '${criterion.id}',
                criterion.section,
                criterion.label,
                _scoreText(criterion.maxScore),
                _scoreText(store.scoreFor(routine, judge, criterion)),
              ],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: _pdfSummaryBox(
                label: 'Subtotal',
                value: _scoreText(subtotal),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _pdfSummaryBox(
                  label: 'Penalización', value: _scoreText(penalty)),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _pdfSummaryBox(
                label: 'Total',
                value: '${_scoreText(total)} / ${_scoreText(maxTotal)}',
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('Feedback',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          constraints: const pw.BoxConstraints(minHeight: 72),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Text(feedback.trim().isEmpty ? '-' : feedback,
              style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
  return document.save();
}

pw.Widget _pdfHeader({
  required pw.ImageProvider? logo,
  required String title,
  required String subtitle,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      if (logo != null)
        pw.Image(logo, width: 118, height: 36, fit: pw.BoxFit.contain)
      else
        pw.Text('Levitate',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 18),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _pdfResultsGroup({
  required JudgingStore store,
  required String title,
  required List<RoutineResult> results,
  required List<String> judges,
  required Map<String, int?> positionByRoutineId,
}) {
  final template =
      results.isEmpty ? null : store.templateFor(results.first.routine);
  final criteria = template?.criteria ?? const <Criterion>[];
  final headers = [
    'Lugar',
    '#',
    'Coreografía',
    'Academia',
    'Juez',
    for (final criterion in criteria) '${criterion.id}',
    'Penal.',
    'Total juez',
    'Total',
  ];
  final data = <List<String>>[];
  for (final result in results) {
    final place = positionByRoutineId[result.routine.id];
    for (final judge in judges) {
      final judgeTotal = result.judgeTotals[judge] ?? 0;
      final penalty = result.judgePenalties[judge] ?? 0;
      final isFirstJudge = judge == judges.first;
      data.add([
        isFirstJudge ? (place == null ? '-' : '$place') : '',
        isFirstJudge ? result.routine.id : '',
        isFirstJudge ? result.routine.name : '',
        isFirstJudge ? result.routine.academy : '',
        judge,
        for (final criterion in criteria)
          _scoreText(store.scoreFor(result.routine, judge, criterion)),
        penalty == 0 ? '-' : _scoreText(penalty),
        _scoreText(judgeTotal),
        isFirstJudge && result.aggregateTotal > 0
            ? result.aggregateTotal.toStringAsFixed(2)
            : '',
      ]);
    }
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        headerStyle:
            pw.TextStyle(fontSize: 6.6, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 6.2),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        cellAlignment: pw.Alignment.center,
      ),
      if (criteria.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            for (final criterion in criteria)
              pw.Text('${criterion.id}. ${criterion.label}',
                  style: const pw.TextStyle(fontSize: 6.4)),
          ],
        ),
      ],
    ],
  );
}

pw.Widget _pdfSummaryBox({required String label, required String value}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      color: PdfColors.grey100,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

Future<pw.ImageProvider?> _loadPdfLogo() async {
  try {
    final data = await rootBundle.load(levitateLogoAsset);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _scoreText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

int _scoreMaxLength(double maxScore) {
  final integerDigits = maxScore.floor().toString().length;
  return integerDigits + 2;
}

String _normalizedScoreText(String value, double maxScore) {
  var normalized =
      value.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
  if (normalized.isEmpty) return '';

  final firstDot = normalized.indexOf('.');
  if (firstDot >= 0) {
    final before = normalized.substring(0, firstDot);
    final after = normalized.substring(firstDot + 1).replaceAll('.', '');
    normalized = '$before.$after';
  }
  if (normalized == '.') return '';
  if (normalized.startsWith('.')) normalized = '0$normalized';

  final dotIndex = normalized.indexOf('.');
  if (dotIndex >= 0 && normalized.length > dotIndex + 2) {
    normalized = normalized.substring(0, dotIndex + 2);
  }

  final parsed = double.tryParse(normalized);
  if (parsed == null) return '';
  if (parsed > maxScore) return _scoreText(maxScore);
  return normalized;
}

List<MapEntry<String, List<Criterion>>> groupedCriteriaFor(
    JudgingTemplate template) {
  final grouped = <String, List<Criterion>>{};
  for (final criterion in template.criteria) {
    final section =
        criterion.section.trim().isEmpty ? 'General' : criterion.section.trim();
    grouped.putIfAbsent(section, () => <Criterion>[]).add(criterion);
  }
  final entries = grouped.entries.toList();
  for (final entry in entries) {
    entry.value.sort((left, right) => left.id.compareTo(right.id));
  }
  entries.sort((left, right) {
    final leftId = left.value.isEmpty ? 0 : left.value.first.id;
    final rightId = right.value.isEmpty ? 0 : right.value.first.id;
    return leftId.compareTo(rightId);
  });
  return entries;
}
