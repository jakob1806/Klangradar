import '../../l10n/generated/app_localizations.dart';

/// Anzeigenamen für die rohen role/type-Enum-Werte aus der DB
/// (persons.roles, ensembles.type) — bisher nur lokal in search_screen.dart
/// definiert, dadurch zeigte die Personen-Detailseite die rohen
/// Kleinbuchstaben-Werte ("solist" statt "Solist:in").
Map<String, String> personRoleLabels(AppLocalizations l10n) => {
  'komponist': l10n.roleComposer,
  'dirigent': l10n.roleConductor,
  'solist': l10n.roleSoloist,
  'chorleiter': l10n.roleChoirmaster,
  'moderator': l10n.roleModerator,
};

Map<String, String> ensembleTypeLabels(AppLocalizations l10n) => {
  'chor': l10n.ensembleTypeChoir,
  'orchester': l10n.ensembleTypeOrchestra,
  'kammerensemble': l10n.ensembleTypeChamberEnsemble,
  'big_band': l10n.ensembleTypeBigBand,
  'sonstiges': l10n.ensembleTypeOther,
};
