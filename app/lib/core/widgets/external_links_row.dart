import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

const _socialIcons = {
  'instagram': Icons.camera_alt_outlined,
  'facebook': Icons.facebook_rounded,
  'twitter': Icons.alternate_email_rounded,
  'x': Icons.alternate_email_rounded,
  'youtube': Icons.play_circle_outline_rounded,
  'spotify': Icons.music_note_rounded,
  'tiktok': Icons.music_note_rounded,
  'linkedin': Icons.business_center_outlined,
};

/// Website/Wikipedia/Social-Links als Icon-Reihe — website_url,
/// wikipedia_url und social_links (jsonb, {instagram, facebook, ...})
/// existierten in persons/ensembles/venues von Anfang an, wurden aber
/// nirgends verlinkt.
class ExternalLinksRow extends StatelessWidget {
  const ExternalLinksRow({
    super.key,
    this.websiteUrl,
    this.wikipediaUrl,
    this.socialLinks,
  });

  final String? websiteUrl;
  final String? wikipediaUrl;
  final Map<String, dynamic>? socialLinks;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final links = <(IconData, String, String)>[
      if (websiteUrl != null)
        (Icons.language_rounded, l10n.externalLinkWebsite, websiteUrl!),
      if (wikipediaUrl != null)
        (Icons.menu_book_rounded, l10n.externalLinkWikipedia, wikipediaUrl!),
      for (final entry in (socialLinks ?? const {}).entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          (
            _socialIcons[entry.key.toLowerCase()] ?? Icons.link_rounded,
            entry.key,
            entry.value as String,
          ),
    ];
    if (links.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label, url) in links)
          OutlinedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textSecondary,
              side: BorderSide(color: colors.separator),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}
