import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/client_app_info.dart';
import '../models/client_backend.dart';
import '../models/common.dart';
import '../services/client_backend_api_client.dart';

class ClientBackendRepository {
  ClientBackendRepository({
    ClientBackendApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _apiClient = apiClient ?? ClientBackendApiClient(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _feedbackTicketsKey = 'client.backend.feedback.tickets';
  static const _deviceIdKey = 'client.backend.device.id';
  static const _lastPromptedBuildKey = 'client.backend.update.last_prompted';
  static const _updateBaselineInitializedKey =
      'client.backend.update.baseline_initialized';
  static const _lastPromptedAnnouncementIdKey =
      'client.backend.announcement.last_prompted';
  static const _announcementBaselineInitializedKey =
      'client.backend.announcement.baseline_initialized';

  final ClientBackendApiClient _apiClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Random _random = Random.secure();

  ClientBootstrapInfo? _cachedBootstrap;
  DateTime? _cachedBootstrapAt;

  Future<ClientBootstrapInfo> fetchBootstrap(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedBootstrap != null &&
        _cachedBootstrapAt != null &&
        DateTime.now().difference(_cachedBootstrapAt!) <
            const Duration(minutes: 5)) {
      return _cachedBootstrap!;
    }
    final bootstrap = await _apiClient.fetchBootstrap();
    _cachedBootstrap = bootstrap;
    _cachedBootstrapAt = DateTime.now();
    return bootstrap;
  }

  Future<ClientUpdateInfo?> checkForUpdate({
    bool forceRefresh = false,
  }) async {
    final bootstrap = await fetchBootstrap(forceRefresh: forceRefresh);
    final version = bootstrap.version;
    if (version.isNewerThan(ClientAppInfo.buildNumber)) {
      return version;
    }
    return null;
  }

  Future<bool> shouldPromptUpdate(int buildNumber) async {
    final prefs = await _preferencesLoader();
    final initialized = prefs.getBool(_updateBaselineInitializedKey) ?? false;
    if (!initialized) {
      final lastPrompted = prefs.getInt(_lastPromptedBuildKey);
      await prefs.setBool(_updateBaselineInitializedKey, true);
      if (lastPrompted != null) {
        return lastPrompted != buildNumber;
      }
      await prefs.setInt(_lastPromptedBuildKey, buildNumber);
      return false;
    }
    return prefs.getInt(_lastPromptedBuildKey) != buildNumber;
  }

  Future<void> markUpdatePrompted(int buildNumber) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(_updateBaselineInitializedKey, true);
    await prefs.setInt(_lastPromptedBuildKey, buildNumber);
  }

  Future<void> ensureUpdateBaselineInitialized(int buildNumber) async {
    final prefs = await _preferencesLoader();
    final initialized = prefs.getBool(_updateBaselineInitializedKey) ?? false;
    if (initialized) {
      return;
    }
    await prefs.setBool(_updateBaselineInitializedKey, true);
    if (prefs.getInt(_lastPromptedBuildKey) == null) {
      await prefs.setInt(_lastPromptedBuildKey, buildNumber);
    }
  }

  Future<bool> shouldPromptAnnouncement(String announcementId) async {
    final prefs = await _preferencesLoader();
    final initialized =
        prefs.getBool(_announcementBaselineInitializedKey) ?? false;
    if (!initialized) {
      final lastPrompted = prefs.getString(_lastPromptedAnnouncementIdKey);
      await prefs.setBool(_announcementBaselineInitializedKey, true);
      if (lastPrompted != null && lastPrompted.isNotEmpty) {
        return lastPrompted != announcementId;
      }
      await prefs.setString(_lastPromptedAnnouncementIdKey, announcementId);
      return false;
    }
    return prefs.getString(_lastPromptedAnnouncementIdKey) != announcementId;
  }

  Future<void> ensureAnnouncementBaselineInitialized() async {
    final prefs = await _preferencesLoader();
    final initialized =
        prefs.getBool(_announcementBaselineInitializedKey) ?? false;
    if (!initialized) {
      await prefs.setBool(_announcementBaselineInitializedKey, true);
    }
  }

  Future<void> markAnnouncementPrompted(String announcementId) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_lastPromptedAnnouncementIdKey, announcementId);
  }

  Future<List<ClientFeedbackTicket>> loadFeedbackTickets() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_feedbackTicketsKey);
    if (raw == null || raw.isEmpty) {
      return const <ClientFeedbackTicket>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <ClientFeedbackTicket>[];
    }
    final tickets = decoded
        .whereType<JsonMap>()
        .map(ClientFeedbackTicket.fromJson)
        .toList(growable: false);
    return _sortedTickets(tickets);
  }

  Future<List<ClientFeedbackTicket>> refreshFeedbackTickets() async {
    final tickets = await loadFeedbackTickets();
    if (tickets.isEmpty) {
      return tickets;
    }
    final refreshed = <ClientFeedbackTicket>[];
    for (final ticket in tickets) {
      final token = ticket.lookupToken;
      if (token.isEmpty) {
        refreshed.add(ticket);
        continue;
      }
      try {
        refreshed.add(
          await _apiClient.fetchFeedback(ticket.id, token),
        );
      } on Object {
        refreshed.add(ticket);
      }
    }
    await _saveFeedbackTickets(refreshed);
    return refreshed;
  }

  Future<ClientFeedbackTicket> refreshFeedbackTicket(
    ClientFeedbackTicket ticket,
  ) async {
    final token = ticket.lookupToken;
    if (token.isEmpty) {
      return ticket;
    }
    final refreshed = await _apiClient.fetchFeedback(ticket.id, token);
    final tickets = await loadFeedbackTickets();
    final nextTickets = [
      refreshed,
      ...tickets.where((item) => item.id != refreshed.id),
    ];
    await _saveFeedbackTickets(nextTickets);
    return refreshed;
  }

  Future<ClientFeedbackTicket> submitFeedback({
    required String title,
    required String content,
    required String contact,
  }) async {
    final draft = ClientFeedbackDraft(
      title: title,
      content: content,
      contact: contact,
      deviceId: await _deviceId(),
      appVersion: ClientAppInfo.displayVersion,
      platform: Platform.operatingSystem,
    );
    final result = await _apiClient.submitFeedback(draft);
    final ticket = ClientFeedbackTicket.fromSubmission(
      draft: draft,
      result: result,
    );
    final tickets = await loadFeedbackTickets();
    final nextTickets = [
      ticket,
      ...tickets.where((item) => item.id != ticket.id),
    ];
    await _saveFeedbackTickets(nextTickets);
    return ticket;
  }

  Future<void> _saveFeedbackTickets(
    List<ClientFeedbackTicket> tickets,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(
      _feedbackTicketsKey,
      jsonEncode(tickets.map((ticket) => ticket.toJson()).toList()),
    );
  }

  Future<String> _deviceId() async {
    final prefs = await _preferencesLoader();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    final deviceId = 'lehu-$encoded';
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  List<ClientFeedbackTicket> _sortedTickets(
    List<ClientFeedbackTicket> tickets,
  ) {
    final copy = [...tickets];
    copy.sort((a, b) {
      final aTime = a.updatedAt ?? a.createdAt;
      final bTime = b.updatedAt ?? b.createdAt;
      if (aTime == null && bTime == null) {
        return b.id.compareTo(a.id);
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      return bTime.compareTo(aTime);
    });
    return copy;
  }
}
