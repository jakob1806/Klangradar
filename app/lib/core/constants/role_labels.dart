/// Deutsche Anzeigenamen für die rohen role/type-Enum-Werte aus der DB
/// (persons.roles, ensembles.type) — bisher nur lokal in search_screen.dart
/// definiert, dadurch zeigte die Personen-Detailseite die rohen
/// Kleinbuchstaben-Werte ("solist" statt "Solist:in").
const personRoleLabel = {
  'komponist': 'Komponist:in',
  'dirigent': 'Dirigent:in',
  'solist': 'Solist:in',
  'chorleiter': 'Chorleiter:in',
  'moderator': 'Moderator:in',
};

const ensembleTypeLabel = {
  'chor': 'Chor',
  'orchester': 'Orchester',
  'kammerensemble': 'Kammerensemble',
  'big_band': 'Big Band',
  'sonstiges': 'Ensemble',
};
