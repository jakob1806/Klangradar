// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navMap => 'Map';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navProfile => 'Profile';

  @override
  String get homeTitle => 'Munich';

  @override
  String get homeSectionToday => 'Today in Munich';

  @override
  String get homeSectionRecommendations => 'Recommended for you';

  @override
  String get homeSectionDiscover => 'Discover';

  @override
  String get homeSectionAlmostSoldOut => 'Selling out soon';

  @override
  String get homeSectionEntityNews => 'News from your places & ensembles';

  @override
  String get homeSectionFestival => 'Festival happening now in Munich';

  @override
  String get homeSectionFree => 'Free concerts';

  @override
  String get homeSectionPopular => 'Popular in Munich right now';

  @override
  String get homeSectionCollections => 'Curated for you';

  @override
  String get homeEmptyState => 'No events found right now.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileLanguage => 'Language';

  @override
  String get profileLanguageGerman => 'Deutsch';

  @override
  String get profileLanguageEnglish => 'English';

  @override
  String get profileLanguageSystem => 'System language';

  @override
  String get entityTypeEvents => 'Events';

  @override
  String get entityTypePersons => 'People';

  @override
  String get entityTypeArtists => 'Artists';

  @override
  String get entityTypeEnsembles => 'Ensembles';

  @override
  String get entityTypeVenues => 'Venues';

  @override
  String get searchHint => 'Work, composer, ensemble, venue …';

  @override
  String get searchClearTooltip => 'Clear search';

  @override
  String get searchFilterLabel => 'Filter';

  @override
  String searchFilterLabelActive(int count) {
    return 'Filter, $count active';
  }

  @override
  String get searchNoFilterResults => 'No events match these filters.';

  @override
  String get searchHistoryTitle => 'Recent searches';

  @override
  String get searchTrendingTitle => 'Popular searches';

  @override
  String get searchBrowseTitle => 'Browse';

  @override
  String get searchDirectoryEmpty => 'No entries.';

  @override
  String get searchNoResults => 'No results.';

  @override
  String searchDetectedFilters(String labels) {
    return 'Detected: $labels';
  }

  @override
  String get searchFilterFree => 'Free';

  @override
  String searchFilterUpTo(String price) {
    return 'up to €$price';
  }

  @override
  String loadingFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get calendarTitle => 'Calendar';

  @override
  String get calendarSyncTooltip => 'Sync calendar';

  @override
  String get calendarViewMonth => 'Month';

  @override
  String get calendarViewWeek => 'Week';

  @override
  String get calendarViewAgenda => 'Agenda';

  @override
  String get calendarPlanEvening => 'Plan this evening';

  @override
  String get calendarMoreThisWeek => 'More this week';

  @override
  String get calendarNoEventsUpcoming => 'No upcoming events.';

  @override
  String calendarNoEventsOnDay(String day) {
    return 'No events on $day.';
  }

  @override
  String get calendarMoreEventsHint =>
      'More events available — please check back later or use search.';

  @override
  String errorLoadingGeneric(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get favoritesTitle => 'My Favorites';

  @override
  String get favoritesSignInPrompt =>
      'Please sign in on the Profile tab to see your favorites.';

  @override
  String get favoritesEmptyState =>
      'No favorites yet. Tap the heart on an event to save it here.';

  @override
  String get favoritesSearchHint => 'Search by venue, artist, or work…';

  @override
  String get favoritesStatusAttending => 'Attending';

  @override
  String get favoritesStatusInterested => 'Interested';

  @override
  String favoritesNoSearchResults(String query) {
    return 'No matches for \"$query\".';
  }

  @override
  String get eventCalendarAddFailed => 'Could not open calendar.';

  @override
  String get eventNotFound => 'Event not found';

  @override
  String get eventAddToCalendarTooltip => 'Add to calendar';

  @override
  String get eventShareTooltip => 'Share';

  @override
  String get eventStatusSoldOut => 'Sold out';

  @override
  String get eventStatusCancelled => 'Cancelled';

  @override
  String get eventStatusPostponed => 'Postponed';

  @override
  String get roleComposer => 'Composer';

  @override
  String get roleConductor => 'Conductor';

  @override
  String get roleSoloist => 'Soloist';

  @override
  String get roleChoirmaster => 'Choirmaster';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleEnsemble => 'Ensemble';

  @override
  String get eventFree => 'Free';

  @override
  String eventMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get eventIncludingIntermission => ' incl. intermission';

  @override
  String eventDateTimeLine(String weekday, String date, String time) {
    return '$weekday, $date · $time';
  }

  @override
  String get weekdayMonShort => 'Mon';

  @override
  String get weekdayTueShort => 'Tue';

  @override
  String get weekdayWedShort => 'Wed';

  @override
  String get weekdayThuShort => 'Thu';

  @override
  String get weekdayFriShort => 'Fri';

  @override
  String get weekdaySatShort => 'Sat';

  @override
  String get weekdaySunShort => 'Sun';

  @override
  String get weekdayMonday => 'Monday';

  @override
  String get weekdayTuesday => 'Tuesday';

  @override
  String get weekdayWednesday => 'Wednesday';

  @override
  String get weekdayThursday => 'Thursday';

  @override
  String get weekdayFriday => 'Friday';

  @override
  String get weekdaySaturday => 'Saturday';

  @override
  String get weekdaySunday => 'Sunday';

  @override
  String get monthJanuary => 'January';

  @override
  String get monthFebruary => 'February';

  @override
  String get monthMarch => 'March';

  @override
  String get monthApril => 'April';

  @override
  String get monthMay => 'May';

  @override
  String get monthJune => 'June';

  @override
  String get monthJuly => 'July';

  @override
  String get monthAugust => 'August';

  @override
  String get monthSeptember => 'September';

  @override
  String get monthOctober => 'October';

  @override
  String get monthNovember => 'November';

  @override
  String get monthDecember => 'December';

  @override
  String get eventOtherDates => 'Other dates';

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
    return '$time';
  }

  @override
  String get eventProgramTitle => 'Program';

  @override
  String get eventIntermission => '— INTERMISSION —';

  @override
  String get eventParticipantsTitle => 'Performers';

  @override
  String get eventAccessibilityTitle => 'Accessibility';

  @override
  String get eventAccessibilityWheelchair => 'Wheelchair accessible';

  @override
  String get eventAccessibilityHearingLoop => 'Hearing loop';

  @override
  String get eventAccessibilitySignLanguage => 'Sign language';

  @override
  String eventLastVerified(String date) {
    return 'Last checked: $date';
  }

  @override
  String get eventVenueSectionTitle => 'Venue';

  @override
  String eventDataSource(String notice) {
    return 'Source: $notice';
  }

  @override
  String get eventSimilarEvents => 'Similar events';

  @override
  String get ticketStatusAvailable => 'Tickets available';

  @override
  String get ticketStatusFewLeft => 'Few tickets left';

  @override
  String get ticketStatusSoldOut => 'Sold out';

  @override
  String get ticketStatusBoxOfficeOnly => 'Box office only';

  @override
  String eventDateTimeShort(String date, String time) {
    return '$date · $time';
  }

  @override
  String get eventChangeStartDatetime => 'Start time changed';

  @override
  String get eventChangeVenue => 'Venue changed';

  @override
  String get eventChangeStatus => 'Status changed';

  @override
  String get eventRecentlyChanged => 'Recently changed';

  @override
  String get eventPriceFree => 'Free';

  @override
  String eventPriceRange(String min, String max) {
    return '$min–$max €';
  }

  @override
  String eventPriceFrom(String price) {
    return 'from $price €';
  }

  @override
  String get eventPriceOnRequest => 'Price on request';

  @override
  String get eventGoToPage => 'Go to event page';

  @override
  String get eventBuyTickets => 'Buy tickets';

  @override
  String get venueNotFound => 'Venue not found';

  @override
  String venueSeats(int count) {
    return '$count seats';
  }

  @override
  String get venueHistory => 'History';

  @override
  String get venueAccessibilityTitle => 'Accessibility';

  @override
  String get venueAccessibilityWheelchair => 'Wheelchair accessible';

  @override
  String get venueAccessibilityHearingLoop => 'Hearing loop';

  @override
  String get venueAccessibilitySignLanguage => 'Sign language';

  @override
  String get venueAccessibilityStepFree => 'Step-free access';

  @override
  String get venueAccessibilityElevator => 'Elevator';

  @override
  String get venueAccessibilityToilet => 'Accessible restroom';

  @override
  String get venueArrival => 'Getting there';

  @override
  String get venuePracticalInfo => 'Practical information';

  @override
  String get venueUpcomingEvents => 'Upcoming events';

  @override
  String get venueNothingPlanned => 'Nothing planned right now.';

  @override
  String venueWalkMinutes(int minutes) {
    return '$minutes min walk';
  }

  @override
  String get venueRoute => 'Route';

  @override
  String get venueTypeConcertHall => 'Concert hall';

  @override
  String get venueTypeChurch => 'Church';

  @override
  String get venueTypeTheater => 'Theater';

  @override
  String get venueTypeMuseum => 'Museum';

  @override
  String get venueTypeCastle => 'Castle';

  @override
  String get venueTypeCulturalCenter => 'Cultural center';

  @override
  String get ensembleTypeChoir => 'Choir';

  @override
  String get ensembleTypeOrchestra => 'Orchestra';

  @override
  String get ensembleTypeChamberEnsemble => 'Chamber ensemble';

  @override
  String get ensembleTypeBigBand => 'Big band';

  @override
  String get ensembleTypeOther => 'Ensemble';

  @override
  String get personNotFound => 'Person not found';

  @override
  String get personBiography => 'Biography';

  @override
  String get personEducationCareer => 'Education & career';

  @override
  String get personRepertoireHighlights => 'Repertoire highlights';

  @override
  String get personAwards => 'Awards';

  @override
  String get personNotableRecordings => 'Notable recordings';

  @override
  String get personUpcomingEvents => 'Upcoming events';

  @override
  String get personNothingPlanned => 'Nothing planned right now.';

  @override
  String get personWorksInProgram => 'Works in the program';

  @override
  String get personSimilarArtists => 'Similar artists';

  @override
  String get ensembleNotFound => 'Ensemble not found';

  @override
  String ensembleFoundedYear(String year) {
    return 'since $year';
  }

  @override
  String ensembleMemberCount(int count) {
    return '$count members';
  }

  @override
  String get ensembleAbout => 'About the ensemble';

  @override
  String get ensembleRepertoire => 'Repertoire';

  @override
  String get ensembleUpcomingEvents => 'Upcoming events';

  @override
  String get ensembleNothingPlanned => 'Nothing planned right now.';

  @override
  String get ensembleSimilar => 'Similar ensembles';

  @override
  String get workAppBarTitle => 'Work';

  @override
  String get workNotFound => 'Work not found';

  @override
  String workMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get workAbout => 'About the work';

  @override
  String get workInstrumentation => 'Instrumentation';

  @override
  String get workMovements => 'Movements';

  @override
  String get workUpcomingPerformances => 'Upcoming performances';

  @override
  String get workNothingPlanned => 'Nothing planned right now.';

  @override
  String workPastPerformances(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count past performances',
      one: '1 past performance',
    );
    return '$_temp0';
  }

  @override
  String get collectionAppBarTitle => 'Collection';

  @override
  String get collectionNotFound => 'Collection not found';

  @override
  String get collectionNoEvents => 'No events in this collection yet.';

  @override
  String eveningPlanAppBarTitle(String date) {
    return 'Evening plan — $date';
  }

  @override
  String get eveningPlanNoEvents => 'No events on this day.';

  @override
  String eveningPlanDurationUntil(int minutes, String time) {
    return '$minutes min — until approx. $time';
  }

  @override
  String eveningPlanUntil(String time) {
    return 'until approx. $time';
  }

  @override
  String eveningPlanOverlapsWith(String titles) {
    return 'Overlaps with $titles';
  }

  @override
  String get eveningPlanAfter => 'Afterwards:';

  @override
  String get filterSheetTitle => 'Filter';

  @override
  String get filterSheetReset => 'Reset';

  @override
  String get filterSheetDate => 'Date';

  @override
  String get filterSheetDateAny => 'Any';

  @override
  String get filterSheetGenre => 'Genre';

  @override
  String get filterSheetPrice => 'Price';

  @override
  String get filterSheetPriceAll => 'All';

  @override
  String filterSheetPriceUpTo(String price) {
    return 'up to $price €';
  }

  @override
  String get filterSheetDistance => 'Distance';

  @override
  String get filterSheetDistanceAny => 'Any';

  @override
  String filterSheetDistanceKm(String km) {
    return '$km km';
  }

  @override
  String get filterSheetDistanceHint =>
      'From the location saved in your profile.';

  @override
  String get filterSheetAccessible => 'Accessible';

  @override
  String get filterSheetOpenAir => 'Open air';

  @override
  String get filterSheetApply => 'Apply filters';

  @override
  String get favoriteSignInPrompt =>
      'Please sign in on the Profile tab to add favorites.';

  @override
  String get favoriteLabelActive => 'Favorited';

  @override
  String get favoriteLabelInactive => 'Not favorited';

  @override
  String get reportReasonWrongImage => 'Wrong image';

  @override
  String get reportReasonWrongTime => 'Wrong time';

  @override
  String get reportReasonCancelled => 'Event cancelled';

  @override
  String get reportReasonWrongArtist => 'Wrong artist/work attribution';

  @override
  String get reportReasonBrokenTicketLink => 'Broken ticket link';

  @override
  String get reportReasonMissingProgram => 'Missing program information';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportLinkText => 'Report an issue';

  @override
  String get reportThankYou => 'Thanks for the heads up!';

  @override
  String get reportReviewNotice =>
      'Our editors will review this — data won\'t change immediately.';

  @override
  String get reportWhatIsWrong => 'What\'s wrong?';

  @override
  String get reportDetailsHint => 'Additional details (optional)';

  @override
  String get reportSubmit => 'Report';

  @override
  String get sourceUnknown => 'Unknown source';

  @override
  String get sourceConfidenceConfirmed => 'Confirmed';

  @override
  String get sourceConfidenceLikely => 'Likely accurate';

  @override
  String get sourceConfidenceUncertain => 'Uncertain';

  @override
  String get sourceSheetTitle => 'Source';

  @override
  String sourceRetrievedOn(String date) {
    return 'Retrieved on $date';
  }

  @override
  String get sourceAutomatedNotice =>
      'Automatically researched — please verify if you doubt the source.';

  @override
  String calendarSyncSynced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events synced.',
      one: '1 event synced.',
    );
    return '$_temp0';
  }

  @override
  String get calendarSyncPermissionDenied =>
      'Calendar access denied. Please allow it in system settings.';

  @override
  String calendarSyncFailed(String message) {
    return 'Sync failed: $message';
  }

  @override
  String get calendarSyncFailedGeneric => 'Sync failed.';

  @override
  String calendarExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get calendarExportFileName => 'klangradar-favorites.ics';

  @override
  String get calendarExportSubject => 'My Klangradar favorites';

  @override
  String get calendarSyncSheetTitle => 'Sync calendar';

  @override
  String get calendarSyncSheetSubtitle =>
      'Adds your upcoming favorites to your calendar.';

  @override
  String get calendarSyncNoFavorites =>
      'No upcoming favorites yet. Favorite events to sync them here.';

  @override
  String get calendarSyncAppleCalendar => 'Apple Calendar';

  @override
  String get calendarSyncGoogleCalendar => 'Google Calendar';

  @override
  String get calendarSyncDeviceHint => 'Add directly to your device calendar';

  @override
  String get calendarSyncIcsExport => 'ICS export';

  @override
  String get calendarSyncIcsHint => 'Share or save as a file';

  @override
  String get interestsAppBarTitle => 'Interests';

  @override
  String get interestsSignInPrompt =>
      'Please sign in on the Profile tab to choose interests.';

  @override
  String get interestsIntro =>
      'Choose what interests you — this helps us show you events you\'ll like.';

  @override
  String get interestCategoryGenres => 'Genres';

  @override
  String get interestCategoryComposers => 'Composers';

  @override
  String get interestCategoryEnsembles => 'Ensembles';

  @override
  String get interestCategoryVenues => 'Venues';

  @override
  String get interestsSearchHint => 'Search…';

  @override
  String interestsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get interestsNoResults => 'No matches.';

  @override
  String get followSignInPrompt =>
      'Please sign in on the Profile tab to follow.';

  @override
  String get followLabelActive => 'Following';

  @override
  String get followLabelInactive => 'Not following';

  @override
  String get myFollowsAppBarTitle => 'Following';

  @override
  String get myFollowsSignInPrompt =>
      'Please sign in on the Profile tab to see who you follow.';

  @override
  String get myFollowsEmptyState =>
      'You\'re not following anyone yet. Tap the bookmark icon on a person, ensemble or venue page.';

  @override
  String get myFollowsSectionPersons => 'People';

  @override
  String get myFollowsSectionEnsembles => 'Ensembles';

  @override
  String get myFollowsSectionVenues => 'Venues';

  @override
  String get myFollowsNotifyTooltipOn => 'Notifications for new concerts on';

  @override
  String get myFollowsNotifyTooltipOff => 'Notifications for new concerts off';

  @override
  String get myFollowsUnfollowTooltip => 'Unfollow';

  @override
  String get mapAttribution => '© OpenStreetMap contributors';

  @override
  String get mapFilterLabel => 'Filter';

  @override
  String mapFilterLabelCount(int count) {
    return 'Filter ($count)';
  }

  @override
  String get mapFilterReset => 'Reset';

  @override
  String mapLoadError(String message) {
    return 'Could not load map: $message';
  }

  @override
  String mapVenueUpcomingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count upcoming events',
      one: '1 upcoming event',
    );
    return '$_temp0';
  }

  @override
  String get mapVenueNoUpcoming => 'No upcoming events';

  @override
  String get mapViewDetails => 'View details';

  @override
  String get notificationsAppBarTitle => 'Notifications';

  @override
  String get notificationsSignInPrompt =>
      'Please sign in on the Profile tab to manage notifications.';

  @override
  String get notificationNewMatchingTitle => 'New matching events';

  @override
  String get notificationNewMatchingSubtitle =>
      'Based on your interests (genres, composers, venues)';

  @override
  String get notificationPriceChangesTitle => 'Price changes';

  @override
  String get notificationPriceChangesSubtitle => 'For events you\'ve favorited';

  @override
  String get notificationAlmostSoldOutTitle => 'Almost sold out';

  @override
  String get notificationAlmostSoldOutSubtitle =>
      'Last tickets for favorited events';

  @override
  String get notificationReminderTitle => 'Reminder the day before';

  @override
  String get notificationReminderSubtitle =>
      'For favorited events happening tomorrow';

  @override
  String get notificationFollowedEnsembleTitle =>
      'New dates from followed ensembles';

  @override
  String get notificationFollowedEnsembleSubtitle =>
      'When an ensemble or person you\'re interested in announces a new event';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingWelcomeTitle => 'Welcome to\nKlangradar';

  @override
  String get onboardingWelcomeSubtitle =>
      'All of Munich\'s classical concerts, operas, and sacred music events in one place — always up to date.';

  @override
  String get onboardingInterestsTitle => 'What interests you?';

  @override
  String get onboardingInterestsSubtitle =>
      'Optional — helps us show you events you\'ll like. You can change this anytime in your profile.';

  @override
  String get onboardingLocationDenied => 'Location access was not granted.';

  @override
  String get onboardingLocationServiceDisabled =>
      'Location services are disabled on this device.';

  @override
  String get onboardingLocationSaved => 'Location saved.';

  @override
  String get onboardingLocationFailed => 'Could not determine location.';

  @override
  String get onboardingLocationTitle => 'Events near you';

  @override
  String get onboardingLocationSubtitle =>
      'With your location we can show you what\'s happening nearby and sort the map accordingly.';

  @override
  String get onboardingLocationRequesting => 'Determining…';

  @override
  String get onboardingLocationShare => 'Share location';

  @override
  String get onboardingNotificationsTitle => 'Never miss out';

  @override
  String get onboardingNotificationsSubtitle =>
      'We\'ll notify you about new matching events, price changes, and before tickets sell out.';

  @override
  String get onboardingNotificationsDone => 'Enabled';

  @override
  String get onboardingNotificationsRequesting => 'Requesting…';

  @override
  String get onboardingNotificationsEnable => 'Enable notifications';

  @override
  String get authSignInTitle => 'Sign in';

  @override
  String get authSignInSubtitle =>
      'For favorites, notifications & recommendations';

  @override
  String get authEmailHint => 'Email address';

  @override
  String get authSendingCode => 'Sending code…';

  @override
  String get authSendCode => 'Send sign-in code';

  @override
  String authCodeSentTo(String email) {
    return 'Code sent to $email';
  }

  @override
  String get authCheckingCode => 'Checking code…';

  @override
  String get authConfirm => 'Confirm';

  @override
  String get authUseOtherEmail => 'Use a different email address';

  @override
  String get authOr => 'or';

  @override
  String get authSignInWithApple => 'Sign in with Apple';

  @override
  String get authSignInWithGoogle => 'Sign in with Google';

  @override
  String get themeModeSheetTitle => 'Appearance';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get profileSignedIn => 'Signed in';

  @override
  String get profileMyFavorites => 'My favorites';

  @override
  String get profileMyFollows => 'Following';

  @override
  String get profileInterests => 'Interests';

  @override
  String get profileNotifications => 'Notifications';

  @override
  String get profileMyLists => 'My lists';

  @override
  String get profileMyListsComingSoon =>
      '\"My lists\" is coming in a future update.';

  @override
  String get profileAppearance => 'Appearance';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get homeHeroBadgeUpcoming => 'COMING UP';

  @override
  String get homeHeroBadgeToday => 'TODAY\'S PICK';

  @override
  String get homeHeroNothingPlanned => 'Nothing planned yet';

  @override
  String get monthJanShort => 'Jan';

  @override
  String get monthFebShort => 'Feb';

  @override
  String get monthMarShort => 'Mar';

  @override
  String get monthAprShort => 'Apr';

  @override
  String get monthMayShort => 'May';

  @override
  String get monthJunShort => 'Jun';

  @override
  String get monthJulShort => 'Jul';

  @override
  String get monthAugShort => 'Aug';

  @override
  String get monthSepShort => 'Sep';

  @override
  String get monthOctShort => 'Oct';

  @override
  String get monthNovShort => 'Nov';

  @override
  String get monthDecShort => 'Dec';

  @override
  String get externalLinkWebsite => 'Website';

  @override
  String get externalLinkWikipedia => 'Wikipedia';

  @override
  String get mapRecenter => 'Reset map to Munich center';

  @override
  String calendarSyncCalendarListError(String errors) {
    return 'Could not read calendar list: $errors';
  }

  @override
  String calendarSyncExistingEventsError(String errors) {
    return 'Could not read existing calendar entries — aborting to avoid duplicates: $errors';
  }

  @override
  String calendarSyncDeleteOldEventError(String errors) {
    return 'Could not remove old calendar entry — aborting to avoid duplicates: $errors';
  }

  @override
  String get calendarSyncNoneCreated => 'No events could be added.';

  @override
  String calendarSyncSomeFailed(int count) {
    return '$count event(s) could not be added.';
  }

  @override
  String get profileAdminPortal => 'Admin portal';

  @override
  String get adminPortalTitle => 'Open admin portal';

  @override
  String get adminPortalPasswordHint => 'Password';

  @override
  String get adminPortalCancel => 'Cancel';

  @override
  String get adminPortalOpen => 'Open';

  @override
  String get adminPortalWrongPassword => 'Wrong password.';

  @override
  String get adminPortalError => 'Connection failed. Please try again later.';
}
