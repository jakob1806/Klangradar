import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Bottom-Nav-Tab: Home
  ///
  /// In de, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom-Nav-Tab: Suche
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get navSearch;

  /// Bottom-Nav-Tab: Karte
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get navMap;

  /// Bottom-Nav-Tab: Kalender
  ///
  /// In de, this message translates to:
  /// **'Kalender'**
  String get navCalendar;

  /// Bottom-Nav-Tab: Profil
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// Titel oben auf dem Home-Screen
  ///
  /// In de, this message translates to:
  /// **'München'**
  String get homeTitle;

  /// No description provided for @homeSectionToday.
  ///
  /// In de, this message translates to:
  /// **'Heute in München'**
  String get homeSectionToday;

  /// No description provided for @homeSectionRecommendations.
  ///
  /// In de, this message translates to:
  /// **'Empfehlungen für dich'**
  String get homeSectionRecommendations;

  /// No description provided for @homeSectionDiscover.
  ///
  /// In de, this message translates to:
  /// **'Entdecken'**
  String get homeSectionDiscover;

  /// No description provided for @homeSectionAlmostSoldOut.
  ///
  /// In de, this message translates to:
  /// **'Demnächst ausverkauft'**
  String get homeSectionAlmostSoldOut;

  /// No description provided for @homeSectionFree.
  ///
  /// In de, this message translates to:
  /// **'Kostenlose Konzerte'**
  String get homeSectionFree;

  /// No description provided for @homeSectionPopular.
  ///
  /// In de, this message translates to:
  /// **'Beliebt gerade in München'**
  String get homeSectionPopular;

  /// No description provided for @homeSectionCollections.
  ///
  /// In de, this message translates to:
  /// **'Für dich zusammengestellt'**
  String get homeSectionCollections;

  /// No description provided for @homeEmptyState.
  ///
  /// In de, this message translates to:
  /// **'Aktuell keine Veranstaltungen gefunden.'**
  String get homeEmptyState;

  /// No description provided for @profileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// Überschrift des Sprachauswahl-Abschnitts im Profil
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get profileLanguage;

  /// No description provided for @profileLanguageGerman.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get profileLanguageGerman;

  /// No description provided for @profileLanguageEnglish.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get profileLanguageEnglish;

  /// No description provided for @profileLanguageSystem.
  ///
  /// In de, this message translates to:
  /// **'Systemsprache'**
  String get profileLanguageSystem;

  /// No description provided for @entityTypeEvents.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltungen'**
  String get entityTypeEvents;

  /// No description provided for @entityTypePersons.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get entityTypePersons;

  /// Verzeichnis-Tab für Personen (bewusst 'Künstler' statt 'Personen', so wie im bisherigen Text)
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get entityTypeArtists;

  /// No description provided for @entityTypeEnsembles.
  ///
  /// In de, this message translates to:
  /// **'Ensembles'**
  String get entityTypeEnsembles;

  /// No description provided for @entityTypeVenues.
  ///
  /// In de, this message translates to:
  /// **'Orte'**
  String get entityTypeVenues;

  /// No description provided for @searchHint.
  ///
  /// In de, this message translates to:
  /// **'Werk, Komponist, Ensemble, Ort …'**
  String get searchHint;

  /// No description provided for @searchClearTooltip.
  ///
  /// In de, this message translates to:
  /// **'Suche löschen'**
  String get searchClearTooltip;

  /// No description provided for @searchFilterLabel.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get searchFilterLabel;

  /// No description provided for @searchFilterLabelActive.
  ///
  /// In de, this message translates to:
  /// **'Filter, {count} aktiv'**
  String searchFilterLabelActive(int count);

  /// No description provided for @searchNoFilterResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Veranstaltungen für diese Filter.'**
  String get searchNoFilterResults;

  /// No description provided for @searchHistoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Suchverlauf'**
  String get searchHistoryTitle;

  /// No description provided for @searchTrendingTitle.
  ///
  /// In de, this message translates to:
  /// **'Beliebte Suchen'**
  String get searchTrendingTitle;

  /// No description provided for @searchBrowseTitle.
  ///
  /// In de, this message translates to:
  /// **'Durchstöbern'**
  String get searchBrowseTitle;

  /// No description provided for @searchDirectoryEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Einträge.'**
  String get searchDirectoryEmpty;

  /// No description provided for @searchNoResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer.'**
  String get searchNoResults;

  /// No description provided for @searchDetectedFilters.
  ///
  /// In de, this message translates to:
  /// **'Erkannt: {labels}'**
  String searchDetectedFilters(String labels);

  /// No description provided for @searchFilterFree.
  ///
  /// In de, this message translates to:
  /// **'Kostenlos'**
  String get searchFilterFree;

  /// No description provided for @searchFilterUpTo.
  ///
  /// In de, this message translates to:
  /// **'bis {price} €'**
  String searchFilterUpTo(String price);

  /// No description provided for @loadingFailed.
  ///
  /// In de, this message translates to:
  /// **'Laden fehlgeschlagen: {error}'**
  String loadingFailed(String error);

  /// No description provided for @calendarTitle.
  ///
  /// In de, this message translates to:
  /// **'Kalender'**
  String get calendarTitle;

  /// No description provided for @calendarSyncTooltip.
  ///
  /// In de, this message translates to:
  /// **'Kalender synchronisieren'**
  String get calendarSyncTooltip;

  /// No description provided for @calendarViewMonth.
  ///
  /// In de, this message translates to:
  /// **'Monat'**
  String get calendarViewMonth;

  /// No description provided for @calendarViewWeek.
  ///
  /// In de, this message translates to:
  /// **'Woche'**
  String get calendarViewWeek;

  /// No description provided for @calendarViewAgenda.
  ///
  /// In de, this message translates to:
  /// **'Agenda'**
  String get calendarViewAgenda;

  /// No description provided for @calendarPlanEvening.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Abend planen'**
  String get calendarPlanEvening;

  /// No description provided for @calendarMoreThisWeek.
  ///
  /// In de, this message translates to:
  /// **'Mehr diese Woche'**
  String get calendarMoreThisWeek;

  /// No description provided for @calendarNoEventsUpcoming.
  ///
  /// In de, this message translates to:
  /// **'Keine anstehenden Veranstaltungen.'**
  String get calendarNoEventsUpcoming;

  /// No description provided for @calendarNoEventsOnDay.
  ///
  /// In de, this message translates to:
  /// **'Keine Veranstaltungen am {day}.'**
  String calendarNoEventsOnDay(String day);

  /// No description provided for @calendarMoreEventsHint.
  ///
  /// In de, this message translates to:
  /// **'Weitere Veranstaltungen vorhanden — bitte später erneut prüfen oder die Suche nutzen.'**
  String get calendarMoreEventsHint;

  /// Häufigste Fehlermeldung im ganzen Projekt — für async-Ladefehler wiederverwenden statt neuer Varianten.
  ///
  /// In de, this message translates to:
  /// **'Fehler beim Laden: {error}'**
  String errorLoadingGeneric(String error);

  /// No description provided for @favoritesTitle.
  ///
  /// In de, this message translates to:
  /// **'Meine Favoriten'**
  String get favoritesTitle;

  /// No description provided for @favoritesSignInPrompt.
  ///
  /// In de, this message translates to:
  /// **'Bitte im Profil-Tab anmelden, um Favoriten zu sehen.'**
  String get favoritesSignInPrompt;

  /// No description provided for @favoritesEmptyState.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Favoriten. Tippe auf das Herz bei einer Veranstaltung, um sie hier zu sammeln.'**
  String get favoritesEmptyState;

  /// No description provided for @favoritesSearchHint.
  ///
  /// In de, this message translates to:
  /// **'Suchen nach Ort, Künstler oder Werk…'**
  String get favoritesSearchHint;

  /// No description provided for @favoritesStatusAttending.
  ///
  /// In de, this message translates to:
  /// **'Besuche ich'**
  String get favoritesStatusAttending;

  /// No description provided for @favoritesStatusInterested.
  ///
  /// In de, this message translates to:
  /// **'Interessiert'**
  String get favoritesStatusInterested;

  /// No description provided for @favoritesNoSearchResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer für \"{query}\".'**
  String favoritesNoSearchResults(String query);

  /// No description provided for @eventCalendarAddFailed.
  ///
  /// In de, this message translates to:
  /// **'Kalender konnte nicht geöffnet werden.'**
  String get eventCalendarAddFailed;

  /// No description provided for @eventNotFound.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltung nicht gefunden'**
  String get eventNotFound;

  /// No description provided for @eventAddToCalendarTooltip.
  ///
  /// In de, this message translates to:
  /// **'Zum Kalender hinzufügen'**
  String get eventAddToCalendarTooltip;

  /// No description provided for @eventShareTooltip.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get eventShareTooltip;

  /// No description provided for @eventStatusSoldOut.
  ///
  /// In de, this message translates to:
  /// **'Ausverkauft'**
  String get eventStatusSoldOut;

  /// No description provided for @eventStatusCancelled.
  ///
  /// In de, this message translates to:
  /// **'Abgesagt'**
  String get eventStatusCancelled;

  /// No description provided for @eventStatusPostponed.
  ///
  /// In de, this message translates to:
  /// **'Verschoben'**
  String get eventStatusPostponed;

  /// No description provided for @roleComposer.
  ///
  /// In de, this message translates to:
  /// **'Komponist:in'**
  String get roleComposer;

  /// No description provided for @roleConductor.
  ///
  /// In de, this message translates to:
  /// **'Dirigent:in'**
  String get roleConductor;

  /// No description provided for @roleSoloist.
  ///
  /// In de, this message translates to:
  /// **'Solist:in'**
  String get roleSoloist;

  /// No description provided for @roleChoirmaster.
  ///
  /// In de, this message translates to:
  /// **'Chorleiter:in'**
  String get roleChoirmaster;

  /// No description provided for @roleModerator.
  ///
  /// In de, this message translates to:
  /// **'Moderator:in'**
  String get roleModerator;

  /// No description provided for @eventFree.
  ///
  /// In de, this message translates to:
  /// **'Kostenlos'**
  String get eventFree;

  /// No description provided for @eventMinutes.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min.'**
  String eventMinutes(int minutes);

  /// No description provided for @eventIncludingIntermission.
  ///
  /// In de, this message translates to:
  /// **' inkl. Pause'**
  String get eventIncludingIntermission;

  /// No description provided for @eventDateTimeLine.
  ///
  /// In de, this message translates to:
  /// **'{weekday}, {date} · {time} Uhr'**
  String eventDateTimeLine(String weekday, String date, String time);

  /// No description provided for @weekdayMonShort.
  ///
  /// In de, this message translates to:
  /// **'Mo'**
  String get weekdayMonShort;

  /// No description provided for @weekdayTueShort.
  ///
  /// In de, this message translates to:
  /// **'Di'**
  String get weekdayTueShort;

  /// No description provided for @weekdayWedShort.
  ///
  /// In de, this message translates to:
  /// **'Mi'**
  String get weekdayWedShort;

  /// No description provided for @weekdayThuShort.
  ///
  /// In de, this message translates to:
  /// **'Do'**
  String get weekdayThuShort;

  /// No description provided for @weekdayFriShort.
  ///
  /// In de, this message translates to:
  /// **'Fr'**
  String get weekdayFriShort;

  /// No description provided for @weekdaySatShort.
  ///
  /// In de, this message translates to:
  /// **'Sa'**
  String get weekdaySatShort;

  /// No description provided for @weekdaySunShort.
  ///
  /// In de, this message translates to:
  /// **'So'**
  String get weekdaySunShort;

  /// No description provided for @weekdayMonday.
  ///
  /// In de, this message translates to:
  /// **'Montag'**
  String get weekdayMonday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In de, this message translates to:
  /// **'Dienstag'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In de, this message translates to:
  /// **'Mittwoch'**
  String get weekdayWednesday;

  /// No description provided for @weekdayThursday.
  ///
  /// In de, this message translates to:
  /// **'Donnerstag'**
  String get weekdayThursday;

  /// No description provided for @weekdayFriday.
  ///
  /// In de, this message translates to:
  /// **'Freitag'**
  String get weekdayFriday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In de, this message translates to:
  /// **'Samstag'**
  String get weekdaySaturday;

  /// No description provided for @weekdaySunday.
  ///
  /// In de, this message translates to:
  /// **'Sonntag'**
  String get weekdaySunday;

  /// No description provided for @monthJanuary.
  ///
  /// In de, this message translates to:
  /// **'Januar'**
  String get monthJanuary;

  /// No description provided for @monthFebruary.
  ///
  /// In de, this message translates to:
  /// **'Februar'**
  String get monthFebruary;

  /// No description provided for @monthMarch.
  ///
  /// In de, this message translates to:
  /// **'März'**
  String get monthMarch;

  /// No description provided for @monthApril.
  ///
  /// In de, this message translates to:
  /// **'April'**
  String get monthApril;

  /// No description provided for @monthMay.
  ///
  /// In de, this message translates to:
  /// **'Mai'**
  String get monthMay;

  /// No description provided for @monthJune.
  ///
  /// In de, this message translates to:
  /// **'Juni'**
  String get monthJune;

  /// No description provided for @monthJuly.
  ///
  /// In de, this message translates to:
  /// **'Juli'**
  String get monthJuly;

  /// No description provided for @monthAugust.
  ///
  /// In de, this message translates to:
  /// **'August'**
  String get monthAugust;

  /// No description provided for @monthSeptember.
  ///
  /// In de, this message translates to:
  /// **'September'**
  String get monthSeptember;

  /// No description provided for @monthOctober.
  ///
  /// In de, this message translates to:
  /// **'Oktober'**
  String get monthOctober;

  /// No description provided for @monthNovember.
  ///
  /// In de, this message translates to:
  /// **'November'**
  String get monthNovember;

  /// No description provided for @monthDecember.
  ///
  /// In de, this message translates to:
  /// **'Dezember'**
  String get monthDecember;

  /// No description provided for @eventOtherDates.
  ///
  /// In de, this message translates to:
  /// **'Weitere Termine'**
  String get eventOtherDates;

  /// No description provided for @eventOtherDateSemanticsLabel.
  ///
  /// In de, this message translates to:
  /// **'{weekday}, {date}, {time}'**
  String eventOtherDateSemanticsLabel(String weekday, String date, String time);

  /// No description provided for @eventOtherDateTime.
  ///
  /// In de, this message translates to:
  /// **'{time} Uhr'**
  String eventOtherDateTime(String time);

  /// No description provided for @eventProgramTitle.
  ///
  /// In de, this message translates to:
  /// **'Programm'**
  String get eventProgramTitle;

  /// No description provided for @eventIntermission.
  ///
  /// In de, this message translates to:
  /// **'— PAUSE —'**
  String get eventIntermission;

  /// No description provided for @eventParticipantsTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitwirkende'**
  String get eventParticipantsTitle;

  /// No description provided for @eventAccessibilityTitle.
  ///
  /// In de, this message translates to:
  /// **'Barrierefreiheit'**
  String get eventAccessibilityTitle;

  /// No description provided for @eventAccessibilityWheelchair.
  ///
  /// In de, this message translates to:
  /// **'Rollstuhlgerecht'**
  String get eventAccessibilityWheelchair;

  /// No description provided for @eventAccessibilityHearingLoop.
  ///
  /// In de, this message translates to:
  /// **'Induktionsschleife'**
  String get eventAccessibilityHearingLoop;

  /// No description provided for @eventAccessibilitySignLanguage.
  ///
  /// In de, this message translates to:
  /// **'Gebärdensprache'**
  String get eventAccessibilitySignLanguage;

  /// No description provided for @eventLastVerified.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt geprüft: {date}'**
  String eventLastVerified(String date);

  /// No description provided for @eventVenueSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltungsort'**
  String get eventVenueSectionTitle;

  /// No description provided for @eventDataSource.
  ///
  /// In de, this message translates to:
  /// **'Datenquelle: {notice}'**
  String eventDataSource(String notice);

  /// No description provided for @eventSimilarEvents.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Veranstaltungen'**
  String get eventSimilarEvents;

  /// No description provided for @ticketStatusAvailable.
  ///
  /// In de, this message translates to:
  /// **'Tickets verfügbar'**
  String get ticketStatusAvailable;

  /// No description provided for @ticketStatusFewLeft.
  ///
  /// In de, this message translates to:
  /// **'Nur noch wenige Tickets'**
  String get ticketStatusFewLeft;

  /// No description provided for @ticketStatusSoldOut.
  ///
  /// In de, this message translates to:
  /// **'Ausverkauft'**
  String get ticketStatusSoldOut;

  /// No description provided for @ticketStatusBoxOfficeOnly.
  ///
  /// In de, this message translates to:
  /// **'Nur an der Abendkasse'**
  String get ticketStatusBoxOfficeOnly;

  /// No description provided for @eventDateTimeShort.
  ///
  /// In de, this message translates to:
  /// **'{date} · {time} Uhr'**
  String eventDateTimeShort(String date, String time);

  /// No description provided for @eventChangeStartDatetime.
  ///
  /// In de, this message translates to:
  /// **'Beginn geändert'**
  String get eventChangeStartDatetime;

  /// No description provided for @eventChangeVenue.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltungsort geändert'**
  String get eventChangeVenue;

  /// No description provided for @eventChangeStatus.
  ///
  /// In de, this message translates to:
  /// **'Status geändert'**
  String get eventChangeStatus;

  /// No description provided for @eventRecentlyChanged.
  ///
  /// In de, this message translates to:
  /// **'Kürzlich geändert'**
  String get eventRecentlyChanged;

  /// No description provided for @eventPriceFree.
  ///
  /// In de, this message translates to:
  /// **'Kostenlos'**
  String get eventPriceFree;

  /// No description provided for @eventPriceRange.
  ///
  /// In de, this message translates to:
  /// **'{min}–{max} €'**
  String eventPriceRange(String min, String max);

  /// No description provided for @eventPriceFrom.
  ///
  /// In de, this message translates to:
  /// **'ab {price} €'**
  String eventPriceFrom(String price);

  /// No description provided for @eventPriceOnRequest.
  ///
  /// In de, this message translates to:
  /// **'Preis auf Anfrage'**
  String get eventPriceOnRequest;

  /// No description provided for @eventGoToPage.
  ///
  /// In de, this message translates to:
  /// **'Zur Veranstaltungsseite'**
  String get eventGoToPage;

  /// No description provided for @eventBuyTickets.
  ///
  /// In de, this message translates to:
  /// **'Tickets kaufen'**
  String get eventBuyTickets;

  /// No description provided for @venueNotFound.
  ///
  /// In de, this message translates to:
  /// **'Venue nicht gefunden'**
  String get venueNotFound;

  /// No description provided for @venueSeats.
  ///
  /// In de, this message translates to:
  /// **'{count} Plätze'**
  String venueSeats(int count);

  /// No description provided for @venueHistory.
  ///
  /// In de, this message translates to:
  /// **'Geschichte'**
  String get venueHistory;

  /// No description provided for @venueAccessibilityTitle.
  ///
  /// In de, this message translates to:
  /// **'Barrierefreiheit'**
  String get venueAccessibilityTitle;

  /// No description provided for @venueAccessibilityWheelchair.
  ///
  /// In de, this message translates to:
  /// **'Rollstuhlgerecht'**
  String get venueAccessibilityWheelchair;

  /// No description provided for @venueAccessibilityHearingLoop.
  ///
  /// In de, this message translates to:
  /// **'Induktionsschleife'**
  String get venueAccessibilityHearingLoop;

  /// No description provided for @venueAccessibilitySignLanguage.
  ///
  /// In de, this message translates to:
  /// **'Gebärdensprache'**
  String get venueAccessibilitySignLanguage;

  /// No description provided for @venueAccessibilityStepFree.
  ///
  /// In de, this message translates to:
  /// **'Stufenloser Zugang'**
  String get venueAccessibilityStepFree;

  /// No description provided for @venueAccessibilityElevator.
  ///
  /// In de, this message translates to:
  /// **'Aufzug'**
  String get venueAccessibilityElevator;

  /// No description provided for @venueAccessibilityToilet.
  ///
  /// In de, this message translates to:
  /// **'Barrierefreies WC'**
  String get venueAccessibilityToilet;

  /// No description provided for @venueArrival.
  ///
  /// In de, this message translates to:
  /// **'Anreise'**
  String get venueArrival;

  /// No description provided for @venuePracticalInfo.
  ///
  /// In de, this message translates to:
  /// **'Praktische Hinweise'**
  String get venuePracticalInfo;

  /// No description provided for @venueUpcomingEvents.
  ///
  /// In de, this message translates to:
  /// **'Kommende Veranstaltungen'**
  String get venueUpcomingEvents;

  /// No description provided for @venueNothingPlanned.
  ///
  /// In de, this message translates to:
  /// **'Aktuell nichts geplant.'**
  String get venueNothingPlanned;

  /// No description provided for @venueWalkMinutes.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min. zu Fuß'**
  String venueWalkMinutes(int minutes);

  /// No description provided for @venueRoute.
  ///
  /// In de, this message translates to:
  /// **'Route'**
  String get venueRoute;

  /// No description provided for @venueTypeConcertHall.
  ///
  /// In de, this message translates to:
  /// **'Konzertsaal'**
  String get venueTypeConcertHall;

  /// No description provided for @venueTypeChurch.
  ///
  /// In de, this message translates to:
  /// **'Kirche'**
  String get venueTypeChurch;

  /// No description provided for @venueTypeTheater.
  ///
  /// In de, this message translates to:
  /// **'Theater'**
  String get venueTypeTheater;

  /// No description provided for @venueTypeMuseum.
  ///
  /// In de, this message translates to:
  /// **'Museum'**
  String get venueTypeMuseum;

  /// No description provided for @venueTypeCastle.
  ///
  /// In de, this message translates to:
  /// **'Schloss'**
  String get venueTypeCastle;

  /// No description provided for @venueTypeCulturalCenter.
  ///
  /// In de, this message translates to:
  /// **'Kulturzentrum'**
  String get venueTypeCulturalCenter;

  /// No description provided for @ensembleTypeChoir.
  ///
  /// In de, this message translates to:
  /// **'Chor'**
  String get ensembleTypeChoir;

  /// No description provided for @ensembleTypeOrchestra.
  ///
  /// In de, this message translates to:
  /// **'Orchester'**
  String get ensembleTypeOrchestra;

  /// No description provided for @ensembleTypeChamberEnsemble.
  ///
  /// In de, this message translates to:
  /// **'Kammerensemble'**
  String get ensembleTypeChamberEnsemble;

  /// No description provided for @ensembleTypeBigBand.
  ///
  /// In de, this message translates to:
  /// **'Big Band'**
  String get ensembleTypeBigBand;

  /// No description provided for @ensembleTypeOther.
  ///
  /// In de, this message translates to:
  /// **'Ensemble'**
  String get ensembleTypeOther;

  /// No description provided for @personNotFound.
  ///
  /// In de, this message translates to:
  /// **'Person nicht gefunden'**
  String get personNotFound;

  /// No description provided for @personBiography.
  ///
  /// In de, this message translates to:
  /// **'Biografie'**
  String get personBiography;

  /// No description provided for @personEducationCareer.
  ///
  /// In de, this message translates to:
  /// **'Ausbildung & Karriere'**
  String get personEducationCareer;

  /// No description provided for @personRepertoireHighlights.
  ///
  /// In de, this message translates to:
  /// **'Repertoire-Schwerpunkte'**
  String get personRepertoireHighlights;

  /// No description provided for @personAwards.
  ///
  /// In de, this message translates to:
  /// **'Auszeichnungen'**
  String get personAwards;

  /// No description provided for @personNotableRecordings.
  ///
  /// In de, this message translates to:
  /// **'Bekannte Aufnahmen'**
  String get personNotableRecordings;

  /// No description provided for @personUpcomingEvents.
  ///
  /// In de, this message translates to:
  /// **'Kommende Veranstaltungen'**
  String get personUpcomingEvents;

  /// No description provided for @personNothingPlanned.
  ///
  /// In de, this message translates to:
  /// **'Aktuell nichts geplant.'**
  String get personNothingPlanned;

  /// No description provided for @personWorksInProgram.
  ///
  /// In de, this message translates to:
  /// **'Werke im Programm'**
  String get personWorksInProgram;

  /// No description provided for @personSimilarArtists.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Künstler:innen'**
  String get personSimilarArtists;

  /// No description provided for @ensembleNotFound.
  ///
  /// In de, this message translates to:
  /// **'Ensemble nicht gefunden'**
  String get ensembleNotFound;

  /// No description provided for @ensembleFoundedYear.
  ///
  /// In de, this message translates to:
  /// **'seit {year}'**
  String ensembleFoundedYear(String year);

  /// No description provided for @ensembleMemberCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Mitglieder'**
  String ensembleMemberCount(int count);

  /// No description provided for @ensembleAbout.
  ///
  /// In de, this message translates to:
  /// **'Über das Ensemble'**
  String get ensembleAbout;

  /// No description provided for @ensembleRepertoire.
  ///
  /// In de, this message translates to:
  /// **'Repertoire'**
  String get ensembleRepertoire;

  /// No description provided for @ensembleUpcomingEvents.
  ///
  /// In de, this message translates to:
  /// **'Kommende Veranstaltungen'**
  String get ensembleUpcomingEvents;

  /// No description provided for @ensembleNothingPlanned.
  ///
  /// In de, this message translates to:
  /// **'Aktuell nichts geplant.'**
  String get ensembleNothingPlanned;

  /// No description provided for @ensembleSimilar.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Ensembles'**
  String get ensembleSimilar;

  /// No description provided for @workAppBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Werk'**
  String get workAppBarTitle;

  /// No description provided for @workNotFound.
  ///
  /// In de, this message translates to:
  /// **'Werk nicht gefunden'**
  String get workNotFound;

  /// No description provided for @workMinutes.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min.'**
  String workMinutes(int minutes);

  /// No description provided for @workAbout.
  ///
  /// In de, this message translates to:
  /// **'Über das Werk'**
  String get workAbout;

  /// No description provided for @workInstrumentation.
  ///
  /// In de, this message translates to:
  /// **'Besetzung'**
  String get workInstrumentation;

  /// No description provided for @workMovements.
  ///
  /// In de, this message translates to:
  /// **'Sätze'**
  String get workMovements;

  /// No description provided for @workUpcomingPerformances.
  ///
  /// In de, this message translates to:
  /// **'Kommende Aufführungen'**
  String get workUpcomingPerformances;

  /// No description provided for @workNothingPlanned.
  ///
  /// In de, this message translates to:
  /// **'Aktuell nichts geplant.'**
  String get workNothingPlanned;

  /// No description provided for @workPastPerformances.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, one{1 vergangene Aufführung} other{{count} vergangene Aufführungen}}'**
  String workPastPerformances(int count);

  /// No description provided for @collectionAppBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Sammlung'**
  String get collectionAppBarTitle;

  /// No description provided for @collectionNotFound.
  ///
  /// In de, this message translates to:
  /// **'Sammlung nicht gefunden'**
  String get collectionNotFound;

  /// No description provided for @collectionNoEvents.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Veranstaltungen in dieser Sammlung.'**
  String get collectionNoEvents;

  /// No description provided for @eveningPlanAppBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Abendplanung — {date}'**
  String eveningPlanAppBarTitle(String date);

  /// No description provided for @eveningPlanNoEvents.
  ///
  /// In de, this message translates to:
  /// **'Keine Veranstaltungen an diesem Tag.'**
  String get eveningPlanNoEvents;

  /// No description provided for @eveningPlanDurationUntil.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min. — bis ca. {time}'**
  String eveningPlanDurationUntil(int minutes, String time);

  /// No description provided for @eveningPlanUntil.
  ///
  /// In de, this message translates to:
  /// **'bis ca. {time}'**
  String eveningPlanUntil(String time);

  /// No description provided for @eveningPlanOverlapsWith.
  ///
  /// In de, this message translates to:
  /// **'Überschneidet sich mit {titles}'**
  String eveningPlanOverlapsWith(String titles);

  /// No description provided for @eveningPlanAfter.
  ///
  /// In de, this message translates to:
  /// **'Danach noch:'**
  String get eveningPlanAfter;

  /// No description provided for @filterSheetTitle.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get filterSheetTitle;

  /// No description provided for @filterSheetReset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get filterSheetReset;

  /// No description provided for @filterSheetDate.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get filterSheetDate;

  /// No description provided for @filterSheetDateAny.
  ///
  /// In de, this message translates to:
  /// **'Beliebig'**
  String get filterSheetDateAny;

  /// No description provided for @filterSheetGenre.
  ///
  /// In de, this message translates to:
  /// **'Genre'**
  String get filterSheetGenre;

  /// No description provided for @filterSheetPrice.
  ///
  /// In de, this message translates to:
  /// **'Preis'**
  String get filterSheetPrice;

  /// No description provided for @filterSheetPriceAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get filterSheetPriceAll;

  /// No description provided for @filterSheetPriceUpTo.
  ///
  /// In de, this message translates to:
  /// **'bis {price} €'**
  String filterSheetPriceUpTo(String price);

  /// No description provided for @filterSheetDistance.
  ///
  /// In de, this message translates to:
  /// **'Entfernung'**
  String get filterSheetDistance;

  /// No description provided for @filterSheetDistanceAny.
  ///
  /// In de, this message translates to:
  /// **'Egal'**
  String get filterSheetDistanceAny;

  /// No description provided for @filterSheetDistanceKm.
  ///
  /// In de, this message translates to:
  /// **'{km} km'**
  String filterSheetDistanceKm(String km);

  /// No description provided for @filterSheetDistanceHint.
  ///
  /// In de, this message translates to:
  /// **'Ab deinem im Profil hinterlegten Standort.'**
  String get filterSheetDistanceHint;

  /// No description provided for @filterSheetAccessible.
  ///
  /// In de, this message translates to:
  /// **'Barrierefrei'**
  String get filterSheetAccessible;

  /// No description provided for @filterSheetOpenAir.
  ///
  /// In de, this message translates to:
  /// **'Open Air'**
  String get filterSheetOpenAir;

  /// No description provided for @filterSheetApply.
  ///
  /// In de, this message translates to:
  /// **'Filter anwenden'**
  String get filterSheetApply;

  /// No description provided for @favoriteSignInPrompt.
  ///
  /// In de, this message translates to:
  /// **'Zum Favorisieren bitte im Profil-Tab anmelden.'**
  String get favoriteSignInPrompt;

  /// No description provided for @favoriteLabelActive.
  ///
  /// In de, this message translates to:
  /// **'Favorisiert'**
  String get favoriteLabelActive;

  /// No description provided for @favoriteLabelInactive.
  ///
  /// In de, this message translates to:
  /// **'Nicht favorisiert'**
  String get favoriteLabelInactive;

  /// No description provided for @reportReasonWrongImage.
  ///
  /// In de, this message translates to:
  /// **'Falsches Bild'**
  String get reportReasonWrongImage;

  /// No description provided for @reportReasonWrongTime.
  ///
  /// In de, this message translates to:
  /// **'Falsche Uhrzeit'**
  String get reportReasonWrongTime;

  /// No description provided for @reportReasonCancelled.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltung abgesagt'**
  String get reportReasonCancelled;

  /// No description provided for @reportReasonWrongArtist.
  ///
  /// In de, this message translates to:
  /// **'Falsche Künstler-/Werkzuordnung'**
  String get reportReasonWrongArtist;

  /// No description provided for @reportReasonBrokenTicketLink.
  ///
  /// In de, this message translates to:
  /// **'Ticketlink defekt'**
  String get reportReasonBrokenTicketLink;

  /// No description provided for @reportReasonMissingProgram.
  ///
  /// In de, this message translates to:
  /// **'Programminformation fehlt'**
  String get reportReasonMissingProgram;

  /// No description provided for @reportReasonOther.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get reportReasonOther;

  /// No description provided for @reportLinkText.
  ///
  /// In de, this message translates to:
  /// **'Fehler melden'**
  String get reportLinkText;

  /// No description provided for @reportThankYou.
  ///
  /// In de, this message translates to:
  /// **'Danke für den Hinweis!'**
  String get reportThankYou;

  /// No description provided for @reportReviewNotice.
  ///
  /// In de, this message translates to:
  /// **'Die Redaktion prüft das — Daten ändern sich dadurch nicht sofort.'**
  String get reportReviewNotice;

  /// No description provided for @reportWhatIsWrong.
  ///
  /// In de, this message translates to:
  /// **'Was stimmt nicht?'**
  String get reportWhatIsWrong;

  /// No description provided for @reportDetailsHint.
  ///
  /// In de, this message translates to:
  /// **'Zusätzliche Details (optional)'**
  String get reportDetailsHint;

  /// No description provided for @reportSubmit.
  ///
  /// In de, this message translates to:
  /// **'Melden'**
  String get reportSubmit;

  /// No description provided for @sourceUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannte Quelle'**
  String get sourceUnknown;

  /// No description provided for @sourceConfidenceConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Bestätigt'**
  String get sourceConfidenceConfirmed;

  /// No description provided for @sourceConfidenceLikely.
  ///
  /// In de, this message translates to:
  /// **'Wahrscheinlich zutreffend'**
  String get sourceConfidenceLikely;

  /// No description provided for @sourceConfidenceUncertain.
  ///
  /// In de, this message translates to:
  /// **'Unsicher'**
  String get sourceConfidenceUncertain;

  /// No description provided for @sourceSheetTitle.
  ///
  /// In de, this message translates to:
  /// **'Quelle'**
  String get sourceSheetTitle;

  /// No description provided for @sourceRetrievedOn.
  ///
  /// In de, this message translates to:
  /// **'Recherchiert am {date}'**
  String sourceRetrievedOn(String date);

  /// No description provided for @sourceAutomatedNotice.
  ///
  /// In de, this message translates to:
  /// **'Automatisiert recherchiert — bitte bei Zweifeln an der Quelle prüfen.'**
  String get sourceAutomatedNotice;

  /// No description provided for @calendarSyncSynced.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, one{1 Veranstaltung synchronisiert.} other{{count} Veranstaltungen synchronisiert.}}'**
  String calendarSyncSynced(int count);

  /// No description provided for @calendarSyncPermissionDenied.
  ///
  /// In de, this message translates to:
  /// **'Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.'**
  String get calendarSyncPermissionDenied;

  /// No description provided for @calendarSyncFailed.
  ///
  /// In de, this message translates to:
  /// **'Synchronisierung fehlgeschlagen: {message}'**
  String calendarSyncFailed(String message);

  /// No description provided for @calendarSyncFailedGeneric.
  ///
  /// In de, this message translates to:
  /// **'Synchronisierung fehlgeschlagen.'**
  String get calendarSyncFailedGeneric;

  /// No description provided for @calendarExportFailed.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen: {error}'**
  String calendarExportFailed(String error);

  /// No description provided for @calendarExportFileName.
  ///
  /// In de, this message translates to:
  /// **'klassik-muenchen-favoriten.ics'**
  String get calendarExportFileName;

  /// No description provided for @calendarExportSubject.
  ///
  /// In de, this message translates to:
  /// **'Meine Klassik München Favoriten'**
  String get calendarExportSubject;

  /// No description provided for @calendarSyncSheetTitle.
  ///
  /// In de, this message translates to:
  /// **'Kalender synchronisieren'**
  String get calendarSyncSheetTitle;

  /// No description provided for @calendarSyncSheetSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Trägt deine anstehenden Favoriten in deinen Kalender ein.'**
  String get calendarSyncSheetSubtitle;

  /// No description provided for @calendarSyncNoFavorites.
  ///
  /// In de, this message translates to:
  /// **'Noch keine anstehenden Favoriten. Favorisiere Veranstaltungen, um sie hier zu synchronisieren.'**
  String get calendarSyncNoFavorites;

  /// No description provided for @calendarSyncAppleCalendar.
  ///
  /// In de, this message translates to:
  /// **'Apple Kalender'**
  String get calendarSyncAppleCalendar;

  /// No description provided for @calendarSyncGoogleCalendar.
  ///
  /// In de, this message translates to:
  /// **'Google Kalender'**
  String get calendarSyncGoogleCalendar;

  /// No description provided for @calendarSyncDeviceHint.
  ///
  /// In de, this message translates to:
  /// **'Direkt in deinen Gerätekalender eintragen'**
  String get calendarSyncDeviceHint;

  /// No description provided for @calendarSyncIcsExport.
  ///
  /// In de, this message translates to:
  /// **'ICS-Export'**
  String get calendarSyncIcsExport;

  /// No description provided for @calendarSyncIcsHint.
  ///
  /// In de, this message translates to:
  /// **'Als Datei teilen oder speichern'**
  String get calendarSyncIcsHint;

  /// No description provided for @interestsAppBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Interessen'**
  String get interestsAppBarTitle;

  /// No description provided for @interestsSignInPrompt.
  ///
  /// In de, this message translates to:
  /// **'Bitte im Profil-Tab anmelden, um Interessen auszuwählen.'**
  String get interestsSignInPrompt;

  /// No description provided for @interestsIntro.
  ///
  /// In de, this message translates to:
  /// **'Wähle aus, was dich interessiert — das hilft uns, dir passende Veranstaltungen zu zeigen.'**
  String get interestsIntro;

  /// No description provided for @interestCategoryGenres.
  ///
  /// In de, this message translates to:
  /// **'Genres'**
  String get interestCategoryGenres;

  /// No description provided for @interestCategoryComposers.
  ///
  /// In de, this message translates to:
  /// **'Komponisten'**
  String get interestCategoryComposers;

  /// No description provided for @interestCategoryEnsembles.
  ///
  /// In de, this message translates to:
  /// **'Ensembles'**
  String get interestCategoryEnsembles;

  /// No description provided for @interestCategoryVenues.
  ///
  /// In de, this message translates to:
  /// **'Venues'**
  String get interestCategoryVenues;

  /// No description provided for @mapAttribution.
  ///
  /// In de, this message translates to:
  /// **'© OpenStreetMap-Mitwirkende'**
  String get mapAttribution;

  /// No description provided for @mapFilterLabel.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get mapFilterLabel;

  /// No description provided for @mapFilterLabelCount.
  ///
  /// In de, this message translates to:
  /// **'Filter ({count})'**
  String mapFilterLabelCount(int count);

  /// No description provided for @mapFilterReset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get mapFilterReset;

  /// No description provided for @mapLoadError.
  ///
  /// In de, this message translates to:
  /// **'Karte konnte nicht geladen werden: {message}'**
  String mapLoadError(String message);

  /// No description provided for @mapVenueUpcomingCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, one{1 kommende Veranstaltung} other{{count} kommende Veranstaltungen}}'**
  String mapVenueUpcomingCount(int count);

  /// No description provided for @mapVenueNoUpcoming.
  ///
  /// In de, this message translates to:
  /// **'Keine kommenden Veranstaltungen'**
  String get mapVenueNoUpcoming;

  /// No description provided for @mapViewDetails.
  ///
  /// In de, this message translates to:
  /// **'Details ansehen'**
  String get mapViewDetails;

  /// No description provided for @notificationsAppBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get notificationsAppBarTitle;

  /// No description provided for @notificationsSignInPrompt.
  ///
  /// In de, this message translates to:
  /// **'Bitte im Profil-Tab anmelden, um Benachrichtigungen einzustellen.'**
  String get notificationsSignInPrompt;

  /// No description provided for @notificationNewMatchingTitle.
  ///
  /// In de, this message translates to:
  /// **'Neue passende Veranstaltungen'**
  String get notificationNewMatchingTitle;

  /// No description provided for @notificationNewMatchingSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Basierend auf deinen Interessen (Genres, Komponisten, Venues)'**
  String get notificationNewMatchingSubtitle;

  /// No description provided for @notificationPriceChangesTitle.
  ///
  /// In de, this message translates to:
  /// **'Preisänderungen'**
  String get notificationPriceChangesTitle;

  /// No description provided for @notificationPriceChangesSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Bei Veranstaltungen, die du favorisiert hast'**
  String get notificationPriceChangesSubtitle;

  /// No description provided for @notificationAlmostSoldOutTitle.
  ///
  /// In de, this message translates to:
  /// **'Fast ausverkauft'**
  String get notificationAlmostSoldOutTitle;

  /// No description provided for @notificationAlmostSoldOutSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Letzte Tickets für favorisierte Veranstaltungen'**
  String get notificationAlmostSoldOutSubtitle;

  /// No description provided for @notificationReminderTitle.
  ///
  /// In de, this message translates to:
  /// **'Erinnerung am Vortag'**
  String get notificationReminderTitle;

  /// No description provided for @notificationReminderSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Für favorisierte Veranstaltungen, die morgen stattfinden'**
  String get notificationReminderSubtitle;

  /// No description provided for @notificationFollowedEnsembleTitle.
  ///
  /// In de, this message translates to:
  /// **'Neue Termine gefolgter Ensembles'**
  String get notificationFollowedEnsembleTitle;

  /// No description provided for @notificationFollowedEnsembleSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wenn ein Ensemble oder eine Person, die dich interessiert, eine neue Veranstaltung ankündigt'**
  String get notificationFollowedEnsembleSubtitle;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In de, this message translates to:
  /// **'Los geht\'s'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingNext.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get onboardingNext;

  /// No description provided for @onboardingSkip.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get onboardingSkip;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei\nKlassik München'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Alle klassischen Konzerte, Opern und Kirchenmusik-Veranstaltungen Münchens an einem Ort — immer aktuell.'**
  String get onboardingWelcomeSubtitle;

  /// No description provided for @onboardingInterestsTitle.
  ///
  /// In de, this message translates to:
  /// **'Was interessiert dich?'**
  String get onboardingInterestsTitle;

  /// No description provided for @onboardingInterestsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Optional — hilft uns, dir passende Veranstaltungen zu zeigen. Du kannst das jederzeit im Profil ändern.'**
  String get onboardingInterestsSubtitle;

  /// No description provided for @onboardingLocationDenied.
  ///
  /// In de, this message translates to:
  /// **'Standortzugriff wurde nicht erlaubt.'**
  String get onboardingLocationDenied;

  /// No description provided for @onboardingLocationServiceDisabled.
  ///
  /// In de, this message translates to:
  /// **'Ortungsdienste sind auf diesem Gerät deaktiviert.'**
  String get onboardingLocationServiceDisabled;

  /// No description provided for @onboardingLocationSaved.
  ///
  /// In de, this message translates to:
  /// **'Standort gespeichert.'**
  String get onboardingLocationSaved;

  /// No description provided for @onboardingLocationFailed.
  ///
  /// In de, this message translates to:
  /// **'Standort konnte nicht ermittelt werden.'**
  String get onboardingLocationFailed;

  /// No description provided for @onboardingLocationTitle.
  ///
  /// In de, this message translates to:
  /// **'Veranstaltungen in deiner Nähe'**
  String get onboardingLocationTitle;

  /// No description provided for @onboardingLocationSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Mit deinem Standort können wir dir zeigen, was in deiner Nähe stattfindet, und die Karte danach sortieren.'**
  String get onboardingLocationSubtitle;

  /// No description provided for @onboardingLocationRequesting.
  ///
  /// In de, this message translates to:
  /// **'Wird ermittelt…'**
  String get onboardingLocationRequesting;

  /// No description provided for @onboardingLocationShare.
  ///
  /// In de, this message translates to:
  /// **'Standort teilen'**
  String get onboardingLocationShare;

  /// No description provided for @onboardingNotificationsTitle.
  ///
  /// In de, this message translates to:
  /// **'Nichts mehr verpassen'**
  String get onboardingNotificationsTitle;

  /// No description provided for @onboardingNotificationsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wir benachrichtigen dich bei neuen passenden Veranstaltungen, Preisänderungen und bevor Tickets ausverkauft sind.'**
  String get onboardingNotificationsSubtitle;

  /// No description provided for @onboardingNotificationsDone.
  ///
  /// In de, this message translates to:
  /// **'Aktiviert'**
  String get onboardingNotificationsDone;

  /// No description provided for @onboardingNotificationsRequesting.
  ///
  /// In de, this message translates to:
  /// **'Wird angefragt…'**
  String get onboardingNotificationsRequesting;

  /// No description provided for @onboardingNotificationsEnable.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen aktivieren'**
  String get onboardingNotificationsEnable;

  /// No description provided for @authSignInTitle.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get authSignInTitle;

  /// No description provided for @authSignInSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Für Favoriten, Benachrichtigungen & Empfehlungen'**
  String get authSignInSubtitle;

  /// No description provided for @authEmailHint.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse'**
  String get authEmailHint;

  /// No description provided for @authSendingCode.
  ///
  /// In de, this message translates to:
  /// **'Sende Code…'**
  String get authSendingCode;

  /// No description provided for @authSendCode.
  ///
  /// In de, this message translates to:
  /// **'Anmeldecode senden'**
  String get authSendCode;

  /// No description provided for @authCodeSentTo.
  ///
  /// In de, this message translates to:
  /// **'Code an {email} gesendet'**
  String authCodeSentTo(String email);

  /// No description provided for @authCheckingCode.
  ///
  /// In de, this message translates to:
  /// **'Prüfe Code…'**
  String get authCheckingCode;

  /// No description provided for @authConfirm.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get authConfirm;

  /// No description provided for @authUseOtherEmail.
  ///
  /// In de, this message translates to:
  /// **'Andere E-Mail-Adresse verwenden'**
  String get authUseOtherEmail;

  /// No description provided for @authOr.
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get authOr;

  /// No description provided for @authSignInWithApple.
  ///
  /// In de, this message translates to:
  /// **'Mit Apple anmelden'**
  String get authSignInWithApple;

  /// No description provided for @authSignInWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get authSignInWithGoogle;

  /// No description provided for @themeModeSheetTitle.
  ///
  /// In de, this message translates to:
  /// **'Darstellung'**
  String get themeModeSheetTitle;

  /// No description provided for @themeModeSystem.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeModeDark;

  /// No description provided for @profileSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get profileSignedIn;

  /// No description provided for @profileMyFavorites.
  ///
  /// In de, this message translates to:
  /// **'Meine Favoriten'**
  String get profileMyFavorites;

  /// No description provided for @profileInterests.
  ///
  /// In de, this message translates to:
  /// **'Interessen'**
  String get profileInterests;

  /// No description provided for @profileNotifications.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get profileNotifications;

  /// No description provided for @profileMyLists.
  ///
  /// In de, this message translates to:
  /// **'Meine Listen'**
  String get profileMyLists;

  /// No description provided for @profileMyListsComingSoon.
  ///
  /// In de, this message translates to:
  /// **'„Meine Listen\" folgt in einer der nächsten Phasen.'**
  String get profileMyListsComingSoon;

  /// No description provided for @profileAppearance.
  ///
  /// In de, this message translates to:
  /// **'Darstellung'**
  String get profileAppearance;

  /// No description provided for @profileSignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get profileSignOut;

  /// No description provided for @homeHeroBadgeUpcoming.
  ///
  /// In de, this message translates to:
  /// **'DEMNÄCHST'**
  String get homeHeroBadgeUpcoming;

  /// No description provided for @homeHeroBadgeToday.
  ///
  /// In de, this message translates to:
  /// **'EMPFEHLUNG DES TAGES'**
  String get homeHeroBadgeToday;

  /// No description provided for @homeHeroNothingPlanned.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts geplant'**
  String get homeHeroNothingPlanned;

  /// No description provided for @monthJanShort.
  ///
  /// In de, this message translates to:
  /// **'Jan'**
  String get monthJanShort;

  /// No description provided for @monthFebShort.
  ///
  /// In de, this message translates to:
  /// **'Feb'**
  String get monthFebShort;

  /// No description provided for @monthMarShort.
  ///
  /// In de, this message translates to:
  /// **'Mär'**
  String get monthMarShort;

  /// No description provided for @monthAprShort.
  ///
  /// In de, this message translates to:
  /// **'Apr'**
  String get monthAprShort;

  /// No description provided for @monthMayShort.
  ///
  /// In de, this message translates to:
  /// **'Mai'**
  String get monthMayShort;

  /// No description provided for @monthJunShort.
  ///
  /// In de, this message translates to:
  /// **'Jun'**
  String get monthJunShort;

  /// No description provided for @monthJulShort.
  ///
  /// In de, this message translates to:
  /// **'Jul'**
  String get monthJulShort;

  /// No description provided for @monthAugShort.
  ///
  /// In de, this message translates to:
  /// **'Aug'**
  String get monthAugShort;

  /// No description provided for @monthSepShort.
  ///
  /// In de, this message translates to:
  /// **'Sep'**
  String get monthSepShort;

  /// No description provided for @monthOctShort.
  ///
  /// In de, this message translates to:
  /// **'Okt'**
  String get monthOctShort;

  /// No description provided for @monthNovShort.
  ///
  /// In de, this message translates to:
  /// **'Nov'**
  String get monthNovShort;

  /// No description provided for @monthDecShort.
  ///
  /// In de, this message translates to:
  /// **'Dez'**
  String get monthDecShort;

  /// No description provided for @externalLinkWebsite.
  ///
  /// In de, this message translates to:
  /// **'Website'**
  String get externalLinkWebsite;

  /// No description provided for @externalLinkWikipedia.
  ///
  /// In de, this message translates to:
  /// **'Wikipedia'**
  String get externalLinkWikipedia;

  /// No description provided for @mapRecenter.
  ///
  /// In de, this message translates to:
  /// **'Karte auf München-Zentrum zurücksetzen'**
  String get mapRecenter;

  /// No description provided for @calendarSyncCalendarListError.
  ///
  /// In de, this message translates to:
  /// **'Kalenderliste konnte nicht gelesen werden: {errors}'**
  String calendarSyncCalendarListError(String errors);

  /// No description provided for @calendarSyncExistingEventsError.
  ///
  /// In de, this message translates to:
  /// **'Bestehende Kalendereinträge konnten nicht gelesen werden — Abbruch, um keine Duplikate zu erzeugen: {errors}'**
  String calendarSyncExistingEventsError(String errors);

  /// No description provided for @calendarSyncDeleteOldEventError.
  ///
  /// In de, this message translates to:
  /// **'Alter Kalendereintrag konnte nicht entfernt werden — Abbruch, um keine Duplikate zu erzeugen: {errors}'**
  String calendarSyncDeleteOldEventError(String errors);

  /// No description provided for @calendarSyncNoneCreated.
  ///
  /// In de, this message translates to:
  /// **'Keine Veranstaltung konnte eingetragen werden.'**
  String get calendarSyncNoneCreated;

  /// No description provided for @calendarSyncSomeFailed.
  ///
  /// In de, this message translates to:
  /// **'{count} Veranstaltung(en) konnten nicht eingetragen werden.'**
  String calendarSyncSomeFailed(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
