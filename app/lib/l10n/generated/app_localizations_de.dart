// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Suche';

  @override
  String get navMap => 'Karte';

  @override
  String get navCalendar => 'Kalender';

  @override
  String get navProfile => 'Profil';

  @override
  String get homeTitle => 'München';

  @override
  String get homeSectionToday => 'Heute in München';

  @override
  String get homeSectionRecommendations => 'Empfehlungen für dich';

  @override
  String get homeSectionDiscover => 'Entdecken';

  @override
  String get homeSectionAlmostSoldOut => 'Demnächst ausverkauft';

  @override
  String get homeSectionEntityNews =>
      'Deine Orte & Ensembles haben Neuigkeiten';

  @override
  String get homeSectionFestival => 'Festival gerade in München';

  @override
  String get homeSectionFree => 'Kostenlose Konzerte';

  @override
  String get homeSectionPopular => 'Beliebt gerade in München';

  @override
  String get homeSectionCollections => 'Für dich zusammengestellt';

  @override
  String get homeEmptyState => 'Aktuell keine Veranstaltungen gefunden.';

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileLanguage => 'Sprache';

  @override
  String get profileLanguageGerman => 'Deutsch';

  @override
  String get profileLanguageEnglish => 'English';

  @override
  String get profileLanguageSystem => 'Systemsprache';

  @override
  String get entityTypeEvents => 'Veranstaltungen';

  @override
  String get entityTypePersons => 'Personen';

  @override
  String get entityTypeArtists => 'Künstler';

  @override
  String get entityTypeEnsembles => 'Ensembles';

  @override
  String get entityTypeVenues => 'Orte';

  @override
  String get searchHint => 'Werk, Komponist, Ensemble, Ort …';

  @override
  String get searchClearTooltip => 'Suche löschen';

  @override
  String get searchFilterLabel => 'Filter';

  @override
  String searchFilterLabelActive(int count) {
    return 'Filter, $count aktiv';
  }

  @override
  String get searchNoFilterResults => 'Keine Veranstaltungen für diese Filter.';

  @override
  String get searchHistoryTitle => 'Suchverlauf';

  @override
  String get searchTrendingTitle => 'Beliebte Suchen';

  @override
  String get searchBrowseTitle => 'Durchstöbern';

  @override
  String get searchDirectoryEmpty => 'Keine Einträge.';

  @override
  String get searchNoResults => 'Keine Treffer.';

  @override
  String searchDetectedFilters(String labels) {
    return 'Erkannt: $labels';
  }

  @override
  String get searchFilterFree => 'Kostenlos';

  @override
  String searchFilterUpTo(String price) {
    return 'bis $price €';
  }

  @override
  String loadingFailed(String error) {
    return 'Laden fehlgeschlagen: $error';
  }

  @override
  String get calendarTitle => 'Kalender';

  @override
  String get calendarSyncTooltip => 'Kalender synchronisieren';

  @override
  String get calendarViewMonth => 'Monat';

  @override
  String get calendarViewWeek => 'Woche';

  @override
  String get calendarViewAgenda => 'Agenda';

  @override
  String get calendarPlanEvening => 'Für diesen Abend planen';

  @override
  String get calendarMoreThisWeek => 'Mehr diese Woche';

  @override
  String get calendarNoEventsUpcoming => 'Keine anstehenden Veranstaltungen.';

  @override
  String calendarNoEventsOnDay(String day) {
    return 'Keine Veranstaltungen am $day.';
  }

  @override
  String get calendarMoreEventsHint =>
      'Weitere Veranstaltungen vorhanden — bitte später erneut prüfen oder die Suche nutzen.';

  @override
  String errorLoadingGeneric(String error) {
    return 'Fehler beim Laden: $error';
  }

  @override
  String get favoritesTitle => 'Meine Favoriten';

  @override
  String get favoritesSignInPrompt =>
      'Bitte im Profil-Tab anmelden, um Favoriten zu sehen.';

  @override
  String get favoritesEmptyState =>
      'Noch keine Favoriten. Tippe auf das Herz bei einer Veranstaltung, um sie hier zu sammeln.';

  @override
  String get favoritesSearchHint => 'Suchen nach Ort, Künstler oder Werk…';

  @override
  String get favoritesStatusAttending => 'Besuche ich';

  @override
  String get favoritesStatusInterested => 'Interessiert';

  @override
  String favoritesNoSearchResults(String query) {
    return 'Keine Treffer für \"$query\".';
  }

  @override
  String get eventCalendarAddFailed => 'Kalender konnte nicht geöffnet werden.';

  @override
  String get eventNotFound => 'Veranstaltung nicht gefunden';

  @override
  String get eventAddToCalendarTooltip => 'Zum Kalender hinzufügen';

  @override
  String get eventShareTooltip => 'Teilen';

  @override
  String get eventStatusSoldOut => 'Ausverkauft';

  @override
  String get eventStatusCancelled => 'Abgesagt';

  @override
  String get eventStatusPostponed => 'Verschoben';

  @override
  String get roleComposer => 'Komponist:in';

  @override
  String get roleConductor => 'Dirigent:in';

  @override
  String get roleSoloist => 'Solist:in';

  @override
  String get roleChoirmaster => 'Chorleiter:in';

  @override
  String get roleModerator => 'Moderator:in';

  @override
  String get roleEnsemble => 'Ensemble';

  @override
  String get eventFree => 'Kostenlos';

  @override
  String eventMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get eventIncludingIntermission => ' inkl. Pause';

  @override
  String eventDateTimeLine(String weekday, String date, String time) {
    return '$weekday, $date · $time Uhr';
  }

  @override
  String get weekdayMonShort => 'Mo';

  @override
  String get weekdayTueShort => 'Di';

  @override
  String get weekdayWedShort => 'Mi';

  @override
  String get weekdayThuShort => 'Do';

  @override
  String get weekdayFriShort => 'Fr';

  @override
  String get weekdaySatShort => 'Sa';

  @override
  String get weekdaySunShort => 'So';

  @override
  String get weekdayMonday => 'Montag';

  @override
  String get weekdayTuesday => 'Dienstag';

  @override
  String get weekdayWednesday => 'Mittwoch';

  @override
  String get weekdayThursday => 'Donnerstag';

  @override
  String get weekdayFriday => 'Freitag';

  @override
  String get weekdaySaturday => 'Samstag';

  @override
  String get weekdaySunday => 'Sonntag';

  @override
  String get monthJanuary => 'Januar';

  @override
  String get monthFebruary => 'Februar';

  @override
  String get monthMarch => 'März';

  @override
  String get monthApril => 'April';

  @override
  String get monthMay => 'Mai';

  @override
  String get monthJune => 'Juni';

  @override
  String get monthJuly => 'Juli';

  @override
  String get monthAugust => 'August';

  @override
  String get monthSeptember => 'September';

  @override
  String get monthOctober => 'Oktober';

  @override
  String get monthNovember => 'November';

  @override
  String get monthDecember => 'Dezember';

  @override
  String get eventOtherDates => 'Weitere Termine';

  @override
  String eventOtherDateSemanticsLabel(
    String weekday,
    String date,
    String time,
  ) {
    return '$weekday, $date, $time';
  }

  @override
  String eventOtherDateTime(String time) {
    return '$time Uhr';
  }

  @override
  String get eventProgramTitle => 'Programm';

  @override
  String get eventIntermission => '— PAUSE —';

  @override
  String get eventParticipantsTitle => 'Mitwirkende';

  @override
  String get eventAccessibilityTitle => 'Barrierefreiheit';

  @override
  String get eventAccessibilityWheelchair => 'Rollstuhlgerecht';

  @override
  String get eventAccessibilityHearingLoop => 'Induktionsschleife';

  @override
  String get eventAccessibilitySignLanguage => 'Gebärdensprache';

  @override
  String eventLastVerified(String date) {
    return 'Zuletzt geprüft: $date';
  }

  @override
  String get eventVenueSectionTitle => 'Veranstaltungsort';

  @override
  String eventDataSource(String notice) {
    return 'Datenquelle: $notice';
  }

  @override
  String get eventDataSourceUnknown => 'Fotograf/Quelle nicht bekannt';

  @override
  String get eventSimilarEvents => 'Ähnliche Veranstaltungen';

  @override
  String get ticketStatusAvailable => 'Tickets verfügbar';

  @override
  String get ticketStatusFewLeft => 'Nur noch wenige Tickets';

  @override
  String get ticketStatusSoldOut => 'Ausverkauft';

  @override
  String get ticketStatusBoxOfficeOnly => 'Nur an der Abendkasse';

  @override
  String eventDateTimeShort(String date, String time) {
    return '$date · $time Uhr';
  }

  @override
  String get eventChangeStartDatetime => 'Beginn geändert';

  @override
  String get eventChangeVenue => 'Veranstaltungsort geändert';

  @override
  String get eventChangeStatus => 'Status geändert';

  @override
  String get eventRecentlyChanged => 'Kürzlich geändert';

  @override
  String get eventPriceFree => 'Kostenlos';

  @override
  String eventPriceRange(String min, String max) {
    return '$min–$max €';
  }

  @override
  String eventPriceFrom(String price) {
    return 'ab $price €';
  }

  @override
  String get eventPriceOnRequest => 'Preis auf Anfrage';

  @override
  String get eventGoToPage => 'Zur Veranstaltungsseite';

  @override
  String get eventBuyTickets => 'Tickets kaufen';

  @override
  String get venueNotFound => 'Venue nicht gefunden';

  @override
  String venueSeats(int count) {
    return '$count Plätze';
  }

  @override
  String get venueHistory => 'Geschichte';

  @override
  String get venueAccessibilityTitle => 'Barrierefreiheit';

  @override
  String get venueAccessibilityWheelchair => 'Rollstuhlgerecht';

  @override
  String get venueAccessibilityHearingLoop => 'Induktionsschleife';

  @override
  String get venueAccessibilitySignLanguage => 'Gebärdensprache';

  @override
  String get venueAccessibilityStepFree => 'Stufenloser Zugang';

  @override
  String get venueAccessibilityElevator => 'Aufzug';

  @override
  String get venueAccessibilityToilet => 'Barrierefreies WC';

  @override
  String get venueArrival => 'Anreise';

  @override
  String get venuePracticalInfo => 'Praktische Hinweise';

  @override
  String get venueUpcomingEvents => 'Kommende Veranstaltungen';

  @override
  String get venueNothingPlanned => 'Aktuell nichts geplant.';

  @override
  String venueWalkMinutes(int minutes) {
    return '$minutes Min. zu Fuß';
  }

  @override
  String get venueRoute => 'Route';

  @override
  String get venueTypeConcertHall => 'Konzertsaal';

  @override
  String get venueTypeChurch => 'Kirche';

  @override
  String get venueTypeTheater => 'Theater';

  @override
  String get venueTypeMuseum => 'Museum';

  @override
  String get venueTypeCastle => 'Schloss';

  @override
  String get venueTypeCulturalCenter => 'Kulturzentrum';

  @override
  String get ensembleTypeChoir => 'Chor';

  @override
  String get ensembleTypeOrchestra => 'Orchester';

  @override
  String get ensembleTypeChamberEnsemble => 'Kammerensemble';

  @override
  String get ensembleTypeBigBand => 'Big Band';

  @override
  String get ensembleTypeOther => 'Ensemble';

  @override
  String get personNotFound => 'Person nicht gefunden';

  @override
  String get personBiography => 'Biografie';

  @override
  String get personEducationCareer => 'Ausbildung & Karriere';

  @override
  String get personRepertoireHighlights => 'Repertoire-Schwerpunkte';

  @override
  String get personAwards => 'Auszeichnungen';

  @override
  String get personNotableRecordings => 'Bekannte Aufnahmen';

  @override
  String get personUpcomingEvents => 'Kommende Veranstaltungen';

  @override
  String get personNothingPlanned => 'Aktuell nichts geplant.';

  @override
  String get personWorksInProgram => 'Werke im Programm';

  @override
  String get personSimilarArtists => 'Ähnliche Künstler:innen';

  @override
  String get ensembleNotFound => 'Ensemble nicht gefunden';

  @override
  String ensembleFoundedYear(String year) {
    return 'seit $year';
  }

  @override
  String ensembleMemberCount(int count) {
    return '$count Mitglieder';
  }

  @override
  String get ensembleAbout => 'Über das Ensemble';

  @override
  String get ensembleRepertoire => 'Repertoire';

  @override
  String get ensembleUpcomingEvents => 'Kommende Veranstaltungen';

  @override
  String get ensembleNothingPlanned => 'Aktuell nichts geplant.';

  @override
  String get ensembleSimilar => 'Ähnliche Ensembles';

  @override
  String get workAppBarTitle => 'Werk';

  @override
  String get workNotFound => 'Werk nicht gefunden';

  @override
  String workMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get workAbout => 'Über das Werk';

  @override
  String get workInstrumentation => 'Besetzung';

  @override
  String get workMovements => 'Sätze';

  @override
  String get workUpcomingPerformances => 'Kommende Aufführungen';

  @override
  String get workNothingPlanned => 'Aktuell nichts geplant.';

  @override
  String workPastPerformances(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vergangene Aufführungen',
      one: '1 vergangene Aufführung',
    );
    return '$_temp0';
  }

  @override
  String get collectionAppBarTitle => 'Sammlung';

  @override
  String get collectionNotFound => 'Sammlung nicht gefunden';

  @override
  String get collectionNoEvents =>
      'Noch keine Veranstaltungen in dieser Sammlung.';

  @override
  String eveningPlanAppBarTitle(String date) {
    return 'Abendplanung — $date';
  }

  @override
  String get eveningPlanNoEvents => 'Keine Veranstaltungen an diesem Tag.';

  @override
  String eveningPlanDurationUntil(int minutes, String time) {
    return '$minutes Min. — bis ca. $time';
  }

  @override
  String eveningPlanUntil(String time) {
    return 'bis ca. $time';
  }

  @override
  String eveningPlanOverlapsWith(String titles) {
    return 'Überschneidet sich mit $titles';
  }

  @override
  String get eveningPlanAfter => 'Danach noch:';

  @override
  String get filterSheetTitle => 'Filter';

  @override
  String get filterSheetReset => 'Zurücksetzen';

  @override
  String get filterSheetDate => 'Datum';

  @override
  String get filterSheetDateAny => 'Beliebig';

  @override
  String get filterSheetGenre => 'Genre';

  @override
  String get filterSheetPrice => 'Preis';

  @override
  String get filterSheetPriceAll => 'Alle';

  @override
  String filterSheetPriceUpTo(String price) {
    return 'bis $price €';
  }

  @override
  String get filterSheetDistance => 'Entfernung';

  @override
  String get filterSheetDistanceAny => 'Egal';

  @override
  String filterSheetDistanceKm(String km) {
    return '$km km';
  }

  @override
  String get filterSheetDistanceHint =>
      'Ab deinem im Profil hinterlegten Standort.';

  @override
  String get filterSheetAccessible => 'Barrierefrei';

  @override
  String get filterSheetOpenAir => 'Open Air';

  @override
  String get filterSheetApply => 'Filter anwenden';

  @override
  String get favoriteSignInPrompt =>
      'Zum Favorisieren bitte im Profil-Tab anmelden.';

  @override
  String get favoriteLabelActive => 'Favorisiert';

  @override
  String get favoriteLabelInactive => 'Nicht favorisiert';

  @override
  String get reportReasonWrongImage => 'Falsches Bild';

  @override
  String get reportReasonWrongTime => 'Falsche Uhrzeit';

  @override
  String get reportReasonCancelled => 'Veranstaltung abgesagt';

  @override
  String get reportReasonWrongArtist => 'Falsche Künstler-/Werkzuordnung';

  @override
  String get reportReasonBrokenTicketLink => 'Ticketlink defekt';

  @override
  String get reportReasonMissingProgram => 'Programminformation fehlt';

  @override
  String get reportReasonOther => 'Sonstiges';

  @override
  String get reportLinkText => 'Fehler melden';

  @override
  String get reportThankYou => 'Danke für den Hinweis!';

  @override
  String get reportReviewNotice =>
      'Die Redaktion prüft das — Daten ändern sich dadurch nicht sofort.';

  @override
  String get reportWhatIsWrong => 'Was stimmt nicht?';

  @override
  String get reportDetailsHint => 'Zusätzliche Details (optional)';

  @override
  String get reportSubmit => 'Melden';

  @override
  String get sourceUnknown => 'Unbekannte Quelle';

  @override
  String get sourceConfidenceConfirmed => 'Bestätigt';

  @override
  String get sourceConfidenceLikely => 'Wahrscheinlich zutreffend';

  @override
  String get sourceConfidenceUncertain => 'Unsicher';

  @override
  String get sourceSheetTitle => 'Quelle';

  @override
  String sourceRetrievedOn(String date) {
    return 'Recherchiert am $date';
  }

  @override
  String get sourceAutomatedNotice =>
      'Automatisiert recherchiert — bitte bei Zweifeln an der Quelle prüfen.';

  @override
  String calendarSyncSynced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Veranstaltungen synchronisiert.',
      one: '1 Veranstaltung synchronisiert.',
    );
    return '$_temp0';
  }

  @override
  String get calendarSyncPermissionDenied =>
      'Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.';

  @override
  String calendarSyncFailed(String message) {
    return 'Synchronisierung fehlgeschlagen: $message';
  }

  @override
  String get calendarSyncFailedGeneric => 'Synchronisierung fehlgeschlagen.';

  @override
  String calendarExportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get calendarExportFileName => 'klangradar-favoriten.ics';

  @override
  String get calendarExportSubject => 'Meine Klangradar-Favoriten';

  @override
  String get calendarSyncSheetTitle => 'Kalender synchronisieren';

  @override
  String get calendarSyncSheetSubtitle =>
      'Trägt deine anstehenden Favoriten in deinen Kalender ein.';

  @override
  String get calendarSyncNoFavorites =>
      'Noch keine anstehenden Favoriten. Favorisiere Veranstaltungen, um sie hier zu synchronisieren.';

  @override
  String get calendarSyncAppleCalendar => 'Apple Kalender';

  @override
  String get calendarSyncGoogleCalendar => 'Google Kalender';

  @override
  String get calendarSyncDeviceHint =>
      'Direkt in deinen Gerätekalender eintragen';

  @override
  String get calendarSyncIcsExport => 'ICS-Export';

  @override
  String get calendarSyncIcsHint => 'Als Datei teilen oder speichern';

  @override
  String get interestsAppBarTitle => 'Interessen';

  @override
  String get interestsSignInPrompt =>
      'Bitte im Profil-Tab anmelden, um Interessen auszuwählen.';

  @override
  String get interestsIntro =>
      'Wähle aus, was dich interessiert — das hilft uns, dir passende Veranstaltungen zu zeigen.';

  @override
  String get interestCategoryGenres => 'Genres';

  @override
  String get interestCategoryComposers => 'Komponisten';

  @override
  String get interestCategoryEnsembles => 'Ensembles';

  @override
  String get interestCategoryVenues => 'Venues';

  @override
  String get interestsSearchHint => 'Suchen…';

  @override
  String interestsSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get interestsNoResults => 'Keine Treffer.';

  @override
  String get followSignInPrompt => 'Zum Folgen bitte im Profil-Tab anmelden.';

  @override
  String get followLabelActive => 'Gefolgt';

  @override
  String get followLabelInactive => 'Nicht gefolgt';

  @override
  String get myFollowsAppBarTitle => 'Meine Verfolgungen';

  @override
  String get myFollowsSignInPrompt =>
      'Bitte im Profil-Tab anmelden, um deine Verfolgungen zu sehen.';

  @override
  String get myFollowsEmptyState =>
      'Du folgst noch niemandem. Tippe auf einer Personen-, Ensemble- oder Venue-Seite auf das Lesezeichen-Symbol.';

  @override
  String get myFollowsSectionPersons => 'Personen';

  @override
  String get myFollowsSectionEnsembles => 'Ensembles';

  @override
  String get myFollowsSectionVenues => 'Venues';

  @override
  String get myFollowsNotifyTooltipOn =>
      'Benachrichtigungen bei neuen Konzerten an';

  @override
  String get myFollowsNotifyTooltipOff =>
      'Benachrichtigungen bei neuen Konzerten aus';

  @override
  String get myFollowsUnfollowTooltip => 'Entfolgen';

  @override
  String get mapAttribution => '© OpenStreetMap-Mitwirkende';

  @override
  String get mapFilterLabel => 'Filter';

  @override
  String mapFilterLabelCount(int count) {
    return 'Filter ($count)';
  }

  @override
  String get mapFilterReset => 'Zurücksetzen';

  @override
  String mapLoadError(String message) {
    return 'Karte konnte nicht geladen werden: $message';
  }

  @override
  String mapVenueUpcomingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kommende Veranstaltungen',
      one: '1 kommende Veranstaltung',
    );
    return '$_temp0';
  }

  @override
  String get mapVenueNoUpcoming => 'Keine kommenden Veranstaltungen';

  @override
  String get mapViewDetails => 'Details ansehen';

  @override
  String get notificationsAppBarTitle => 'Benachrichtigungen';

  @override
  String get notificationsSignInPrompt =>
      'Bitte im Profil-Tab anmelden, um Benachrichtigungen einzustellen.';

  @override
  String get notificationNewMatchingTitle => 'Neue passende Veranstaltungen';

  @override
  String get notificationNewMatchingSubtitle =>
      'Basierend auf deinen Interessen (Genres, Komponisten, Venues)';

  @override
  String get notificationPriceChangesTitle => 'Preisänderungen';

  @override
  String get notificationPriceChangesSubtitle =>
      'Bei Veranstaltungen, die du favorisiert hast';

  @override
  String get notificationAlmostSoldOutTitle => 'Fast ausverkauft';

  @override
  String get notificationAlmostSoldOutSubtitle =>
      'Letzte Tickets für favorisierte Veranstaltungen';

  @override
  String get notificationReminderTitle => 'Erinnerung am Vortag';

  @override
  String get notificationReminderSubtitle =>
      'Für favorisierte Veranstaltungen, die morgen stattfinden';

  @override
  String get notificationFollowedEnsembleTitle =>
      'Neue Termine gefolgter Ensembles';

  @override
  String get notificationFollowedEnsembleSubtitle =>
      'Wenn ein Ensemble oder eine Person, die dich interessiert, eine neue Veranstaltung ankündigt';

  @override
  String get onboardingGetStarted => 'Los geht\'s';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingWelcomeTitle => 'Willkommen bei\nKlangradar';

  @override
  String get onboardingWelcomeSubtitle =>
      'Alle klassischen Konzerte, Opern und Kirchenmusik-Veranstaltungen Münchens an einem Ort — immer aktuell.';

  @override
  String get onboardingInterestsTitle => 'Was interessiert dich?';

  @override
  String get onboardingInterestsSubtitle =>
      'Optional — hilft uns, dir passende Veranstaltungen zu zeigen. Du kannst das jederzeit im Profil ändern.';

  @override
  String get onboardingLocationDenied => 'Standortzugriff wurde nicht erlaubt.';

  @override
  String get onboardingLocationServiceDisabled =>
      'Ortungsdienste sind auf diesem Gerät deaktiviert.';

  @override
  String get onboardingLocationSaved => 'Standort gespeichert.';

  @override
  String get onboardingLocationFailed =>
      'Standort konnte nicht ermittelt werden.';

  @override
  String get onboardingLocationTitle => 'Veranstaltungen in deiner Nähe';

  @override
  String get onboardingLocationSubtitle =>
      'Mit deinem Standort können wir dir zeigen, was in deiner Nähe stattfindet, und die Karte danach sortieren.';

  @override
  String get onboardingLocationRequesting => 'Wird ermittelt…';

  @override
  String get onboardingLocationShare => 'Standort teilen';

  @override
  String get onboardingNotificationsTitle => 'Nichts mehr verpassen';

  @override
  String get onboardingNotificationsSubtitle =>
      'Wir benachrichtigen dich bei neuen passenden Veranstaltungen, Preisänderungen und bevor Tickets ausverkauft sind.';

  @override
  String get onboardingNotificationsDone => 'Aktiviert';

  @override
  String get onboardingNotificationsRequesting => 'Wird angefragt…';

  @override
  String get onboardingNotificationsEnable => 'Benachrichtigungen aktivieren';

  @override
  String get authSignInTitle => 'Anmelden';

  @override
  String get authSignInSubtitle =>
      'Für Favoriten, Benachrichtigungen & Empfehlungen';

  @override
  String get authEmailHint => 'E-Mail-Adresse';

  @override
  String get authSendingCode => 'Sende Code…';

  @override
  String get authSendCode => 'Anmeldecode senden';

  @override
  String authCodeSentTo(String email) {
    return 'Code an $email gesendet';
  }

  @override
  String get authCheckingCode => 'Prüfe Code…';

  @override
  String get authConfirm => 'Bestätigen';

  @override
  String get authUseOtherEmail => 'Andere E-Mail-Adresse verwenden';

  @override
  String get authOr => 'oder';

  @override
  String get authSignInWithApple => 'Mit Apple anmelden';

  @override
  String get authSignInWithGoogle => 'Mit Google anmelden';

  @override
  String get themeModeSheetTitle => 'Darstellung';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Hell';

  @override
  String get themeModeDark => 'Dunkel';

  @override
  String get profileSignedIn => 'Angemeldet';

  @override
  String get profileMyFavorites => 'Meine Favoriten';

  @override
  String get profileMyFollows => 'Meine Verfolgungen';

  @override
  String get profileInterests => 'Interessen';

  @override
  String get profileNotifications => 'Benachrichtigungen';

  @override
  String get profileMyLists => 'Meine Listen';

  @override
  String get profileMyListsComingSoon =>
      '„Meine Listen\" folgt in einer der nächsten Phasen.';

  @override
  String get profileAppearance => 'Darstellung';

  @override
  String get profileSignOut => 'Abmelden';

  @override
  String get homeHeroBadgeUpcoming => 'DEMNÄCHST';

  @override
  String get homeHeroBadgeToday => 'EMPFEHLUNG DES TAGES';

  @override
  String get homeHeroNothingPlanned => 'Noch nichts geplant';

  @override
  String get monthJanShort => 'Jan';

  @override
  String get monthFebShort => 'Feb';

  @override
  String get monthMarShort => 'Mär';

  @override
  String get monthAprShort => 'Apr';

  @override
  String get monthMayShort => 'Mai';

  @override
  String get monthJunShort => 'Jun';

  @override
  String get monthJulShort => 'Jul';

  @override
  String get monthAugShort => 'Aug';

  @override
  String get monthSepShort => 'Sep';

  @override
  String get monthOctShort => 'Okt';

  @override
  String get monthNovShort => 'Nov';

  @override
  String get monthDecShort => 'Dez';

  @override
  String get externalLinkWebsite => 'Website';

  @override
  String get externalLinkWikipedia => 'Wikipedia';

  @override
  String get mapRecenter => 'Karte auf München-Zentrum zurücksetzen';

  @override
  String calendarSyncCalendarListError(String errors) {
    return 'Kalenderliste konnte nicht gelesen werden: $errors';
  }

  @override
  String calendarSyncExistingEventsError(String errors) {
    return 'Bestehende Kalendereinträge konnten nicht gelesen werden — Abbruch, um keine Duplikate zu erzeugen: $errors';
  }

  @override
  String calendarSyncDeleteOldEventError(String errors) {
    return 'Alter Kalendereintrag konnte nicht entfernt werden — Abbruch, um keine Duplikate zu erzeugen: $errors';
  }

  @override
  String get calendarSyncNoneCreated =>
      'Keine Veranstaltung konnte eingetragen werden.';

  @override
  String calendarSyncSomeFailed(int count) {
    return '$count Veranstaltung(en) konnten nicht eingetragen werden.';
  }

  @override
  String get profileAdminPortal => 'Admin-Portal';

  @override
  String get adminPortalTitle => 'Admin-Portal öffnen';

  @override
  String get adminPortalPasswordHint => 'Passwort';

  @override
  String get adminPortalCancel => 'Abbrechen';

  @override
  String get adminPortalOpen => 'Öffnen';

  @override
  String get adminPortalWrongPassword => 'Falsches Passwort.';

  @override
  String get adminPortalError =>
      'Verbindung fehlgeschlagen. Bitte später erneut versuchen.';

  @override
  String get homeSectionMyLists => 'Meine Listen';

  @override
  String myListsEventCount(int count) {
    return '$count Veranstaltungen';
  }

  @override
  String get notifyLabelActive => 'Benachrichtigungen an';

  @override
  String get notifyLabelInactive => 'Benachrichtigungen aus';

  @override
  String get myListsPickerTitle => 'Veranstaltungen auswählen';

  @override
  String get myListsSave => 'Speichern';

  @override
  String get myListsPickerSearchHint => 'Veranstaltungen suchen';

  @override
  String get myListsRenameTitle => 'Liste umbenennen';

  @override
  String get myListsCancel => 'Abbrechen';

  @override
  String get myListsDeleteConfirmTitle => 'Liste löschen?';

  @override
  String get myListsDelete => 'Löschen';

  @override
  String get myListsNotFound => 'Liste nicht gefunden';

  @override
  String get myListsAddEvents => 'Veranstaltungen hinzufügen';

  @override
  String get myListsRename => 'Umbenennen';

  @override
  String get myListsListEmptyState =>
      'Noch keine Veranstaltungen in dieser Liste.';

  @override
  String get myListsAddCoverImage => 'Titelbild hinzufügen';

  @override
  String get myListsCoverFromLibrary => 'Aus Mediathek wählen';

  @override
  String get myListsCoverRemove => 'Titelbild entfernen';

  @override
  String get myListsCoverCropTitle => 'Titelbild zuschneiden';

  @override
  String myListsCoverError(String error) {
    return 'Titelbild konnte nicht gespeichert werden: $error';
  }

  @override
  String get myListsCreateTitle => 'Neue Liste';

  @override
  String get myListsNameHint => 'Name der Liste';

  @override
  String get myListsCreate => 'Erstellen';

  @override
  String get myListsAppBarTitle => 'Meine Listen';

  @override
  String get myListsSignInPrompt => 'Melde dich an, um Listen zu speichern.';

  @override
  String get myListsEmptyState => 'Noch keine Listen angelegt.';
}
