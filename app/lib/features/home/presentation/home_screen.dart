import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/editorial_collections_section.dart';
import '../../../core/widgets/event_section.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/liquid_glass/liquid_glass.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.appColors;
    final async = ref.watch(homeDataProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeDataProvider),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPaddingMobile,
                AppSpacing.md,
                AppSpacing.screenPaddingMobile,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.homeTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    LiquidGlassIconButton(
                      icon: Icons.person_rounded,
                      semanticLabel: l10n.navProfile,
                      onPressed: () => context.go('/profile'),
                    ),
                  ],
                ),
              ),
            ),
            ...async.when(
              loading: () => [
                const SliverPadding(
                  padding: EdgeInsets.only(top: 120),
                  sliver: SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPaddingMobile,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Center(
                        child: Text(
                          'Konnte Events nicht laden: $e',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              data: (data) => [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPaddingMobile,
                    AppSpacing.md,
                    AppSpacing.screenPaddingMobile,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Hero(colors: colors, event: data.hero),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  sliver: SliverList.list(
                    // Modul-Reihenfolge nach docs/08-home-feed-
                    // recommendation-algorithm.md, Abschnitt 3: zeitliche
                    // Dringlichkeit zuerst, dann das personalisierte Kern-
                    // Modul, direkt gefolgt vom bewusst NICHT nach
                    // Geschmack gefilterten Entdecken-Modul (Abschnitt 4.3
                    // — sonst verstärkt der Feed nur das schon Bekannte),
                    // dann weitere Dringlichkeit/Nische, Popularität als
                    // Fallback/Füller ganz am Ende.
                    children: [
                      if (data.heute.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionToday,
                          events: data.heute,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      const EditorialCollectionsSection(),
                      const SizedBox(height: AppSpacing.sectionGap),
                      if (data.empfehlungen.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionRecommendations,
                          events: data.empfehlungen,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.entdecken.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionDiscover,
                          events: data.entdecken,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.entityNews.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionEntityNews,
                          events: data.entityNews,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.ausverkauft.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionAlmostSoldOut,
                          events: data.ausverkauft,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.festival.isNotEmpty) ...[
                        EventSection(
                          title: data.festivalName ?? l10n.homeSectionFestival,
                          events: data.festival,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.kostenlos.isNotEmpty) ...[
                        EventSection(
                          title: l10n.homeSectionFree,
                          events: data.kostenlos,
                        ),
                        const SizedBox(height: AppSpacing.sectionGap),
                      ],
                      if (data.beliebt.isNotEmpty)
                        EventSection(
                          title: l10n.homeSectionPopular,
                          events: data.beliebt,
                        ),
                      if (data.heute.isEmpty &&
                          data.empfehlungen.isEmpty &&
                          data.entdecken.isEmpty &&
                          data.entityNews.isEmpty &&
                          data.ausverkauft.isEmpty &&
                          data.festival.isEmpty &&
                          data.kostenlos.isEmpty &&
                          data.beliebt.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.screenPaddingMobile,
                            vertical: AppSpacing.xxxl,
                          ),
                          child: Center(
                            child: Text(
                              l10n.homeEmptyState,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.colors, required this.event});
  final AppColorsExtension colors;
  final Map<String, dynamic>? event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final genreSlugs = (event?['event_genres'] as List? ?? [])
        .map((g) => g['genres']?['slug'] as String?)
        .whereType<String>();
    final genre = EventGenre.fromSlug(
      genreSlugs.isEmpty ? null : genreSlugs.first,
    );
    final start = MunichTime.tryParse(event?['start_datetime'] as String?);
    final venueName = event?['venues']?['name'] as String?;
    final imageUrls = event?['image_urls'] as List?;
    final imageUrl = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls.first as String?
        : null;
    final cardRadius = BorderRadius.circular(AppRadius.card);

    return GestureDetector(
      onTap: event == null
          ? null
          : () => context.push('/event/${event!['slug']}'),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    GenreArtwork(genre: genre, borderRadius: cardRadius),
                placeholder: (context, url) =>
                    GenreArtwork(genre: genre, borderRadius: cardRadius),
                imageBuilder: (context, imageProvider) => ClipRRect(
                  borderRadius: cardRadius,
                  child: Image(image: imageProvider, fit: BoxFit.cover),
                ),
              )
            else
              GenreArtwork(genre: genre, borderRadius: cardRadius),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xC7000000)],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: LiquidGlassSurface(
                borderRadius: BorderRadius.circular(AppRadius.card),
                blurSigma: AppGlassDepth.control,
                onImage: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event == null
                          ? l10n.homeHeroBadgeUpcoming
                          : l10n.homeHeroBadgeToday,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event == null
                          ? l10n.homeHeroNothingPlanned
                          : (event!['title'] as String? ?? ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (event != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          event!['subtitle'],
                          venueName,
                          if (start != null)
                            '${start.day}.${start.month}. · ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
