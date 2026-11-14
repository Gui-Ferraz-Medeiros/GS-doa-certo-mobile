import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doacerto_mobile/territorial_dashboards.dart';

const String _configuredApiUrl = String.fromEnvironment('DOACERTO_API_URL');

String get _apiBaseUrl {
  final configuredUrl = _configuredApiUrl.trim();
  if (configuredUrl.isNotEmpty) {
    return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
  }
  if (kIsWeb) {
    return 'http://localhost:3001';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3001';
  }
  return 'http://localhost:3001';
}

String _newConversationId() =>
    'mobile-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ChangeNotifierProvider(
      create: (_) => DonationState()..loadData(),
      child: const DoaCertoApp(),
    ),
  );
}

class DoaCertoApp extends StatelessWidget {
  const DoaCertoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DonationState>(
      builder: (context, state, _) {
        final colors = state.highContrast
            ? const ColorScheme.light(
                primary: Colors.black,
                onPrimary: Colors.white,
                secondary: Color(0xFF202020),
                onSecondary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
                error: Color(0xFFB00020),
              )
            : ColorScheme.fromSeed(
                seedColor: const Color(0xFF1F8A70),
                brightness: Brightness.light,
              );
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DoaCerto',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: colors,
            scaffoldBackgroundColor: state.highContrast
                ? Colors.white
                : const Color(0xFFF4F8F5),
            appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                foregroundColor: state.highContrast ? Colors.white : null,
                backgroundColor: state.highContrast ? Colors.black : null,
              ),
            ),
          ),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(
                  mediaQuery.textScaler.scale(1) * state.fontScale,
                ),
              ),
              child: child!,
            );
          },
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/territory':
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (context) => TerritorialDashboardHub(
                    onOpenDashboard: (route, territory) {
                      final args = _territorialDashboardArgs(
                        context.read<DonationState>(),
                        territory,
                      );
                      Navigator.of(context).pushNamed(route, arguments: args);
                    },
                  ),
                );
              case resourcesDashboardRoute:
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) =>
                      ResourcesDashboardScreen(args: _dashboardArgs(settings)),
                );
              case climateDashboardRoute:
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) =>
                      ClimateDashboardScreen(args: _dashboardArgs(settings)),
                );
              case servicesDashboardRoute:
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) =>
                      ServicesDashboardScreen(args: _dashboardArgs(settings)),
                );
              default:
                return null;
            }
          },
          home: const AuthScreen(),
        );
      },
    );
  }
}

class DonationState extends ChangeNotifier {
  DonationState({List<DonationItem>? initialDonations})
    : _donations = initialDonations ?? _defaultDonations();

  List<DonationItem> _donations;
  List<Organization> organizations = [];
  List<ChatMessage> assistantMessages = [];
  String conversationId = '';
  String? organizationsError;
  String? assistantError;
  bool highContrast = false;
  double fontScale = 1;
  bool locationConsentDecided = false;
  bool locationConsentGranted = false;
  String userRole = 'doador';
  String userName = 'Maria L.';
  bool isLoggedIn = false;
  bool isLoading = true;
  List<_DemoAccount>? _demoAccounts;

  List<DonationItem> get donations => [..._donations];

  Future<void> loadData() async {
    isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await _ensureDemoAccountsLoaded(prefs);
    highContrast = prefs.getBool('doacerto_high_contrast') ?? false;
    fontScale = prefs.getDouble('doacerto_font_scale') ?? 1;
    locationConsentDecided =
        prefs.getBool('doacerto_location_consent_decided') ?? false;
    locationConsentGranted =
        prefs.getBool('doacerto_location_consent_granted') ?? false;
    final raw = prefs.getString('doacerto_data');

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final items = decoded['donations'] as List<dynamic>? ?? [];
        _donations = items
            .map((item) => DonationItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _donations = _defaultDonations();
      }
    } else {
      _donations = _defaultDonations();
    }

    final savedConversationId = prefs.getString('doacerto_conversation_id');
    conversationId = savedConversationId ?? _newConversationId();
    await prefs.setString('doacerto_conversation_id', conversationId);

    final savedMessages = prefs.getString('doacerto_assistant_messages');
    if (savedMessages != null) {
      try {
        final decodedMessages = jsonDecode(savedMessages) as List<dynamic>;
        assistantMessages = decodedMessages
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .skip(max(0, decodedMessages.length - 30))
            .toList();
      } catch (error) {
        debugPrint(
          'Não foi possível restaurar o histórico do assistente: $error',
        );
        assistantMessages = [];
      }
    }

    await loadOrganizations();
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadOrganizations() async {
    organizationsError = null;
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/dados'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Servidor respondeu com status ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = payload['organizacoes'] as List<dynamic>? ?? [];
      organizations = entries
          .whereType<Map<String, dynamic>>()
          .map(Organization.fromJson)
          .where(
            (organization) =>
                organization.latitude != 0 && organization.longitude != 0,
          )
          .toList();
    } catch (error) {
      organizationsError = 'Não foi possível carregar as organizações. Verifique a conexão com o servidor.';
      debugPrint('Erro ao carregar organizações: $error');
    }
    notifyListeners();
  }

  Future<void> sendAssistantMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;

    assistantError = null;
    final history = assistantMessages
        .where((item) => !item.isError)
        .map(
          (item) => {'role': item.isUser ? 'user' : 'model', 'text': item.text},
        )
        .toList();
    _appendAssistantMessage(
      ChatMessage(text: message, isUser: true, createdAt: DateTime.now()),
    );
    notifyListeners();
    await _persistAssistant();

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mensagem': message,
              'historico': history,
              'conversationId': conversationId,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          payload['erro'] ?? 'Erro ao conversar com o assistente.',
        );
      }

      conversationId = payload['conversationId'] as String? ?? conversationId;
      final recommendations = (payload['recomendacoes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Organization.fromJson)
          .toList();
      _appendAssistantMessage(
        ChatMessage(
          text:
              payload['resposta'] as String? ??
              'Não recebi uma resposta válida.',
          isUser: false,
          createdAt: DateTime.now(),
          recommendations: recommendations,
        ),
      );
      await _persistAssistant();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doacerto_conversation_id', conversationId);
    } catch (error) {
      assistantError = error.toString().replaceFirst('Exception: ', '');
      debugPrint('Erro ao enviar mensagem ao assistente: $error');
    }
    notifyListeners();
  }

  Future<void> clearAssistantHistory() async {
    final oldConversationId = conversationId;
    assistantError = null;
    assistantMessages = [];
    conversationId = _newConversationId();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('doacerto_assistant_messages');
    await prefs.setString('doacerto_conversation_id', conversationId);

    try {
      final response = await http
          .delete(Uri.parse('$_apiBaseUrl/api/chat/$oldConversationId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Servidor respondeu com status ${response.statusCode}.',
        );
      }
    } catch (error) {
      assistantError = 'Histórico removido deste aparelho, mas não foi possível limpar a sessão no servidor.';
      debugPrint('Erro ao limpar histórico remoto: $error');
    }
    notifyListeners();
  }

  Future<void> _persistAssistant() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'doacerto_assistant_messages',
      jsonEncode(
        assistantMessages
            .skip(max(0, assistantMessages.length - 30))
            .map((message) => message.toJson())
            .toList(),
      ),
    );
  }

  void _appendAssistantMessage(ChatMessage message) {
    assistantMessages = [...assistantMessages, message];
    if (assistantMessages.length > 30) {
      assistantMessages = assistantMessages.sublist(
        assistantMessages.length - 30,
      );
    }
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'donations': _donations.map((d) => d.toJson()).toList(),
      'userRole': userRole,
      'userName': userName,
    };
    await prefs.setString('doacerto_data', jsonEncode(payload));
  }

  Future<void> setHighContrast(bool enabled) async {
    highContrast = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('doacerto_high_contrast', enabled);
  }

  Future<void> setFontScale(double scale) async {
    fontScale = scale.clamp(0.9, 1.5);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('doacerto_font_scale', fontScale);
  }

  Future<void> saveLocationConsent({
    required bool decided,
    required bool granted,
  }) async {
    locationConsentDecided = decided;
    locationConsentGranted = granted;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('doacerto_location_consent_decided', decided);
    await prefs.setBool('doacerto_location_consent_granted', granted);
  }

  Future<String?> registerUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (name.trim().isEmpty) return 'Informe seu nome.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      return 'Informe um e-mail válido.';
    }
    if (password.length < 6) {
      return 'A senha deve ter pelo menos 6 caracteres.';
    }
    if (role != 'doador' && role != 'empresa') {
      return 'Selecione um perfil válido.';
    }

    final prefs = await SharedPreferences.getInstance();
    await _ensureDemoAccountsLoaded(prefs);
    if (_demoAccounts!.any((account) => account.email == normalizedEmail)) {
      return 'Já existe uma conta cadastrada com este e-mail.';
    }

    final salt =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    final account = _DemoAccount(
      name: name.trim(),
      email: normalizedEmail,
      role: role,
      salt: salt,
      passwordHash: _hashPassword(salt, password),
    );
    _demoAccounts!.add(account);
    await _saveDemoAccounts(prefs);
    await _startSession(account, prefs);
    return null;
  }

  void markDonationDelivered(String id) {
    final index = _donations.indexWhere((item) => item.id == id);
    if (index == -1 || _donations[index].status != 'Pendente') return;
    _donations[index] = _donations[index].copyWith(status: 'Entregue');
    notifyListeners();
    persist();
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureDemoAccountsLoaded(prefs);
    final normalizedEmail = email.trim().toLowerCase();
    _DemoAccount? matchedAccount;
    for (final account in _demoAccounts!) {
      if (account.email == normalizedEmail &&
          account.passwordHash == _hashPassword(account.salt, password)) {
        matchedAccount = account;
        break;
      }
    }

    if (matchedAccount == null) return 'E-mail ou senha inválidos.';
    await _startSession(matchedAccount, prefs);
    return null;
  }

  Future<void> logout() async {
    isLoggedIn = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('doacerto_auth_session');
  }

  Future<void> _ensureDemoAccountsLoaded(SharedPreferences prefs) async {
    if (_demoAccounts != null) return;

    final savedAccounts = prefs.getString('doacerto_demo_users');
    if (savedAccounts == null) {
      const demoSalt = 'doacerto-demo-account';
      _demoAccounts = [
        _DemoAccount(
          name: 'Maria L.',
          email: 'maria@doacerto.com',
          role: 'doador',
          salt: demoSalt,
          passwordHash: _hashPassword(demoSalt, '123456'),
        ),
      ];
      await _saveDemoAccounts(prefs);
    } else {
      try {
        final decoded = jsonDecode(savedAccounts) as List<dynamic>;
        _demoAccounts = decoded
            .map((item) => _DemoAccount.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (error) {
        debugPrint('Não foi possível ler as contas demonstrativas: $error');
        rethrow;
      }
    }

    final savedEmail = prefs.getString('doacerto_auth_session');
    if (savedEmail != null) {
      for (final account in _demoAccounts!) {
        if (account.email == savedEmail) {
          _applyAccount(account);
          notifyListeners();
          break;
        }
      }
    }
  }

  Future<void> _saveDemoAccounts(SharedPreferences prefs) async {
    await prefs.setString(
      'doacerto_demo_users',
      jsonEncode(_demoAccounts!.map((account) => account.toJson()).toList()),
    );
  }

  Future<void> _startSession(
    _DemoAccount account,
    SharedPreferences prefs,
  ) async {
    _applyAccount(account);
    await prefs.setString('doacerto_auth_session', account.email);
    notifyListeners();
    await persist();
  }

  void _applyAccount(_DemoAccount account) {
    userName = account.name;
    userRole = account.role;
    isLoggedIn = true;
  }

  static String _hashPassword(String salt, String password) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  DonationItem addDonation({
    required String title,
    required String category,
    required String location,
    required int quantity,
    required String description,
    required String deadline,
    required double latitude,
    required double longitude,
    DateTime? scheduledAt,
  }) {
    final item = DonationItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      category: category,
      quantity: quantity,
      location: location,
      description: description,
      deadline: deadline,
      latitude: latitude,
      longitude: longitude,
      status: 'Disponível',
      donor: userName,
      createdAt: DateTime.now(),
      scheduledAt: scheduledAt,
      receiptCode:
          'DS-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
    );

    _donations.insert(0, item);
    notifyListeners();
    persist();
    return item;
  }

  void offerDonation(String id) {
    final index = _donations.indexWhere((item) => item.id == id);
    if (index == -1) return;

    final item = _donations[index];
    if (item.quantity <= 1) {
      _donations[index] = item.copyWith(
        status: 'Pendente',
        quantity: 0,
        offeredQuantity: item.offeredQuantity + item.quantity,
      );
    } else {
      _donations[index] = item.copyWith(
        quantity: item.quantity - 1,
        offeredQuantity: item.offeredQuantity + 1,
      );
    }

    notifyListeners();
    persist();
  }

  List<DonationItem> get visibleDonations {
    if (userRole == 'empresa') {
      return _donations.where((item) => item.status != 'Entregue').toList();
    }
    return _donations;
  }

  List<Marker> buildDonationMarkers() {
    return _donations
        .where((item) => item.latitude != 0 || item.longitude != 0)
        .map(
          (item) => Marker(
            point: LatLng(item.latitude, item.longitude),
            width: 30,
            height: 30,
            child: const Icon(
              Icons.location_on,
              color: Color(0xFF1F8A70),
              size: 28,
            ),
          ),
        )
        .toList();
  }

  List<DonationItem> get recentDonations => _donations.take(3).toList();

  int get totalAvailable =>
      _donations.where((item) => item.status == 'Disponível').length;
  int get totalPending =>
      _donations.where((item) => item.status == 'Pendente').length;
  int get totalDelivered =>
      _donations.where((item) => item.status == 'Entregue').length;
  int get deliveredItems => _donations
      .where((item) => item.status == 'Entregue')
      .fold(
        0,
        (total, item) =>
            total +
            (item.offeredQuantity > 0 ? item.offeredQuantity : item.quantity),
      );
  int get scheduledDonations =>
      _donations.where((item) => item.scheduledAt != null).length;

  List<DonationUrgency> get donationUrgencies {
    final areas = <String, List<DonationItem>>{};
    for (final donation in _donations.where(
      (item) =>
          item.status == 'Disponível' &&
          item.latitude.abs() <= 90 &&
          item.longitude.abs() <= 180,
    )) {
      final area = donation.location.trim().isEmpty
          ? 'Localização não informada'
          : donation.location;
      areas.putIfAbsent(area, () => []).add(donation);
    }

    return areas.entries.map((entry) {
      final donations = entry.value;
      final coordinates = donations.fold<List<double>>(
        [0, 0],
        (sum, donation) => [
          sum[0] + donation.latitude,
          sum[1] + donation.longitude,
        ],
      );
      final nearestDeadline = donations
          .map((item) => DateTime.tryParse(item.deadline))
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (nearest, deadline) => nearest == null || deadline.isBefore(nearest)
                ? deadline
                : nearest,
          );
      final days = nearestDeadline?.difference(DateTime.now()).inDays;
      final urgency = days == null
          ? UrgencyLevel.unspecified
          : days <= 3
          ? UrgencyLevel.critical
          : days <= 7
          ? UrgencyLevel.attention
          : UrgencyLevel.supplied;

      return DonationUrgency(
        area: entry.key,
        point: LatLng(
          coordinates[0] / donations.length,
          coordinates[1] / donations.length,
        ),
        availableCount: donations.length,
        nearestDeadline: nearestDeadline,
        level: urgency,
      );
    }).toList();
  }

  static List<DonationItem> _defaultDonations() {
    return [
      DonationItem(
        id: '1',
        title: 'Cestas básicas',
        category: 'Alimentos',
        quantity: 18,
        location: 'São Paulo - SP',
        description:
            'Cestas para famílias em situação de vulnerabilidade social.',
        deadline: '2026-11-20',
        latitude: -23.5489,
        longitude: -46.6388,
        status: 'Disponível',
        donor: 'Aliança Social',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      DonationItem(
        id: '2',
        title: 'Roupas infantis',
        category: 'Vestuário',
        quantity: 14,
        location: 'Campinas - SP',
        description: 'Conjuntos em bom estado para crianças de 4 a 12 anos.',
        deadline: '2026-11-18',
        latitude: -22.9068,
        longitude: -47.0616,
        status: 'Disponível',
        donor: 'Lar do Bem',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      DonationItem(
        id: '3',
        title: 'Kit escolar',
        category: 'Educação',
        quantity: 9,
        location: 'Rio de Janeiro - RJ',
        description: 'Mochilas, cadernos e materiais de apoio acadêmico.',
        deadline: '2026-11-22',
        latitude: -22.9068,
        longitude: -43.1729,
        status: 'Pendente',
        donor: 'Ação Solidária',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];
  }
}

class _DemoAccount {
  const _DemoAccount({
    required this.name,
    required this.email,
    required this.role,
    required this.salt,
    required this.passwordHash,
  });

  final String name;
  final String email;
  final String role;
  final String salt;
  final String passwordHash;

  factory _DemoAccount.fromJson(Map<String, dynamic> json) => _DemoAccount(
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    salt: json['salt'] as String,
    passwordHash: json['passwordHash'] as String,
  );

  Map<String, String> toJson() => {
    'name': name,
    'email': email,
    'role': role,
    'salt': salt,
    'passwordHash': passwordHash,
  };
}

TerritorialDashboardArgs _dashboardArgs(RouteSettings settings) {
  final arguments = settings.arguments;
  if (arguments is! TerritorialDashboardArgs) {
    throw FlutterError(
      'A rota ${settings.name} exige TerritorialDashboardArgs.',
    );
  }
  return arguments;
}

TerritorialDashboardArgs _territorialDashboardArgs(
  DonationState state,
  String territory,
) {
  final city = territory.split(' - ').first.toLowerCase();
  bool matchesTerritory(String value) => value.toLowerCase().contains(city);
  final donations = state.donations
      .where((donation) => matchesTerritory(donation.location))
      .toList();
  final organizations = state.organizations.where(
    (organization) => [
      organization.address,
      organization.neighborhood,
      organization.zone,
    ].any(matchesTerritory),
  );
  final now = DateTime.now();
  final monthlyCounts = List<int>.generate(6, (index) {
    final month = DateTime(now.year, now.month - 5 + index);
    return donations
        .where(
          (donation) =>
              donation.createdAt.year == month.year &&
              donation.createdAt.month == month.month,
        )
        .length;
  });
  final urgentAreas = state.donationUrgencies
      .where(
        (urgency) =>
            matchesTerritory(urgency.area) &&
            urgency.level == UrgencyLevel.critical,
      )
      .length;
  return TerritorialDashboardArgs(
    territory: territory,
    availableDonations: donations
        .where((donation) => donation.status == 'Disponível')
        .length,
    pendingDonations: donations
        .where((donation) => donation.status == 'Pendente')
        .length,
    deliveredItems: donations
        .where((donation) => donation.status == 'Entregue')
        .fold(
          0,
          (total, donation) =>
              total +
              (donation.offeredQuantity > 0
                  ? donation.offeredQuantity
                  : donation.quantity),
        ),
    completedDonations: donations
        .where((donation) => donation.status == 'Entregue')
        .length,
    organizationCount: organizations.length,
    urgentAreas: urgentAreas,
    monthlyDonationCounts: monthlyCounts,
  );
}

enum UrgencyLevel { critical, attention, supplied, unspecified }

class DonationUrgency {
  const DonationUrgency({
    required this.area,
    required this.point,
    required this.availableCount,
    required this.nearestDeadline,
    required this.level,
  });

  final String area;
  final LatLng point;
  final int availableCount;
  final DateTime? nearestDeadline;
  final UrgencyLevel level;

  Color get color => switch (level) {
    UrgencyLevel.critical => const Color(0xFFD32F2F),
    UrgencyLevel.attention => const Color(0xFFF9A825),
    UrgencyLevel.supplied => const Color(0xFF2E7D32),
    UrgencyLevel.unspecified => const Color(0xFF616161),
  };

  String get label => switch (level) {
    UrgencyLevel.critical => 'Crítica',
    UrgencyLevel.attention => 'Atenção',
    UrgencyLevel.supplied => 'Prazo posterior',
    UrgencyLevel.unspecified => 'Sem prazo informado',
  };
}

class DonationItem {
  final String id;
  final String title;
  final String category;
  final int quantity;
  final String location;
  final String description;
  final String deadline;
  final double latitude;
  final double longitude;
  final String status;
  final String donor;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final String? receiptCode;
  final int offeredQuantity;

  const DonationItem({
    required this.id,
    required this.title,
    required this.category,
    required this.quantity,
    required this.location,
    required this.description,
    required this.deadline,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.donor,
    required this.createdAt,
    this.scheduledAt,
    this.receiptCode,
    this.offeredQuantity = 0,
  });

  DonationItem copyWith({
    String? id,
    String? title,
    String? category,
    int? quantity,
    String? location,
    String? description,
    String? deadline,
    double? latitude,
    double? longitude,
    String? status,
    String? donor,
    DateTime? createdAt,
    DateTime? scheduledAt,
    String? receiptCode,
    int? offeredQuantity,
  }) {
    return DonationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      description: description ?? this.description,
      deadline: deadline ?? this.deadline,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      donor: donor ?? this.donor,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      receiptCode: receiptCode ?? this.receiptCode,
      offeredQuantity: offeredQuantity ?? this.offeredQuantity,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'quantity': quantity,
    'location': location,
    'description': description,
    'deadline': deadline,
    'latitude': latitude,
    'longitude': longitude,
    'status': status,
    'donor': donor,
    'createdAt': createdAt.toIso8601String(),
    'scheduledAt': scheduledAt?.toIso8601String(),
    'receiptCode': receiptCode,
    'offeredQuantity': offeredQuantity,
  };

  factory DonationItem.fromJson(Map<String, dynamic> json) {
    return DonationItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      category: json['category'] ?? 'Diversos',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      location: json['location'] ?? '',
      description: json['description'] ?? '',
      deadline: json['deadline'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      status: json['status'] ?? 'Disponível',
      donor: json['donor'] ?? 'N/A',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      scheduledAt: DateTime.tryParse(json['scheduledAt'] ?? ''),
      receiptCode: json['receiptCode']?.toString(),
      offeredQuantity: (json['offeredQuantity'] as num?)?.toInt() ?? 0,
    );
  }
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.neighborhood,
    required this.zone,
    required this.acceptedItems,
    required this.urgency,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String category;
  final String address;
  final String neighborhood;
  final String zone;
  final List<String> acceptedItems;
  final String urgency;
  final double latitude;
  final double longitude;

  String get routeUrl =>
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=walking';

  factory Organization.fromJson(Map<String, dynamic> json) {
    final coordinates = json['coordenadas'] as Map<String, dynamic>? ?? {};
    return Organization(
      id: json['id']?.toString() ?? json['nome']?.toString() ?? '',
      name: json['nome']?.toString() ?? 'Organização',
      category: json['categoria']?.toString() ?? '',
      address: json['endereco']?.toString() ?? '',
      neighborhood: json['bairro']?.toString() ?? '',
      zone: json['zona']?.toString() ?? '',
      acceptedItems: (json['itens_aceitos'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      urgency: json['urgencia_atual']?.toString() ?? '',
      latitude:
          ((json['latitude'] ?? coordinates['latitude'] ?? json['lat']) as num?)
              ?.toDouble() ??
          0,
      longitude:
          ((json['longitude'] ?? coordinates['longitude'] ?? json['lng'])
                  as num?)
              ?.toDouble() ??
          0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': name,
    'categoria': category,
    'endereco': address,
    'bairro': neighborhood,
    'zona': zone,
    'itens_aceitos': acceptedItems,
    'urgencia_atual': urgency,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.createdAt,
    this.recommendations = const [],
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final DateTime createdAt;
  final List<Organization> recommendations;
  final bool isError;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'createdAt': createdAt.toIso8601String(),
    'recommendations': recommendations.map((item) => item.toJson()).toList(),
    'isError': isError,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text']?.toString() ?? '',
    isUser: json['isUser'] == true,
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    recommendations: (json['recommendations'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Organization.fromJson)
        .toList(),
    isError: json['isError'] == true,
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'maria@doacerto.com');
  final _passwordController = TextEditingController(text: '123456');
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String _selectedRole = 'doador';
  String? _authError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _authError = null;
    });

    try {
      final state = context.read<DonationState>();
      final error = _isRegistering
          ? await state.registerUser(
              name: _nameController.text,
              email: _emailController.text,
              password: _passwordController.text,
              role: _selectedRole,
            )
          : await state.login(
              email: _emailController.text,
              password: _passwordController.text,
            );
      if (!mounted) return;
      setState(() => _authError = error);
    } catch (error) {
      debugPrint('Erro ao autenticar conta demonstrativa: $error');
      if (!mounted) return;
      setState(
        () => _authError = 'Não foi possível acessar as contas deste aparelho.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Consumer<DonationState>(
      builder: (context, state, _) {
        if (state.isLoggedIn) return const MainNavigationScreen();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Acessibilidade'),
            actions: const [_AccessibilityMenu()],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8F5F1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite,
                              color: Color(0xFF1F8A70),
                              size: 52,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'DoaCerto',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF123E35),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Conectando doações reais com quem precisa.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Acesso demonstrativo: contas ficam apenas neste '
                            'aparelho; nenhum e-mail de verificação é enviado.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_isRegistering) ...[
                            TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 80,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Informe seu nome.'
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Nome',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(email)
                                  ? null
                                  : 'Informe um e-mail válido.';
                            },
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            validator: (value) =>
                                value == null || value.length < 6
                                ? 'Senha com mínimo de 6 caracteres.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_isRegistering) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              validator: (value) =>
                                  value != _passwordController.text
                                  ? 'As senhas não conferem.'
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar senha',
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'doador',
                                  label: Text('Doador'),
                                ),
                                ButtonSegment(
                                  value: 'empresa',
                                  label: Text('Empresa'),
                                ),
                              ],
                              selected: {_selectedRole},
                              onSelectionChanged: (selection) {
                                setState(() => _selectedRole = selection.first);
                              },
                            ),
                          ],
                          if (!_isRegistering) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Conta de teste: maria@doacerto.com · senha: 123456',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.black54,
                              ),
                            ),
                          ],
                          if (_authError != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _authError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _submit(context),
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isRegistering
                                        ? Icons.person_add_alt_1
                                        : Icons.login_rounded,
                                  ),
                            label: Text(
                              _isRegistering ? 'Criar conta' : 'Entrar',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: const Color(0xFF1F8A70),
                            ),
                          ),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _isRegistering = !_isRegistering;
                                      _authError = null;
                                    });
                                    _formKey.currentState?.reset();
                                  },
                            child: Text(
                              _isRegistering
                                  ? 'Já tenho uma conta · Entrar'
                                  : 'Criar uma conta',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    HomeScreen(),
    DonationsScreen(),
    MapScreen(),
    ChatScreen(),
    AddDonationScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLocationConsentIfNeeded(),
    );
  }

  Future<void> _showLocationConsentIfNeeded() async {
    final state = context.read<DonationState>();
    if (state.locationConsentDecided || !mounted) return;
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Privacidade e localização'),
        content: const Text(
          'Se você autorizar, sua localização será usada somente para calcular pontos de coleta próximos e não será armazenada nem compartilhada com terceiros. O app ainda não coleta a localização do dispositivo; você pode mudar sua escolha nas configurações de privacidade.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Concordo'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await state.saveLocationConsent(decided: true, granted: consent == true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.volunteer_activism_outlined),
            selectedIcon: Icon(Icons.volunteer_activism),
            label: 'Doações',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistente',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Adicionar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();
    final stats = [
      _StatCard(
        title: 'Disponíveis',
        value: state.totalAvailable.toString(),
        color: const Color(0xFF1F8A70),
      ),
      _StatCard(
        title: 'Pendentes',
        value: state.totalPending.toString(),
        color: const Color(0xFFB38A00),
      ),
      _StatCard(
        title: 'Entregues',
        value: state.totalDelivered.toString(),
        color: const Color(0xFF3A7BD5),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          const _AccessibilityMenu(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, ${state.userName}!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Você tem ${state.totalAvailable} campanhas ativas e ${state.totalPending} solicitações em análise.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5F1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      color: Color(0xFF1F8A70),
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) => stats[index],
            ),
          ),
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Inteligência territorial'),
              subtitle: const Text(
                'Explore os painéis de recursos, clima e serviços.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/territory'),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Doações em destaque',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Text(
                'Ver tudo',
                style: TextStyle(
                  color: Color(0xFF1F8A70),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...state.recentDonations.map(
            (donation) => _DonationCard(donation: donation),
          ),
          const SizedBox(height: 22),
          const Text(
            'Impacto social confirmado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Indicadores calculados a partir de doações marcadas como entregues. Não incluem estimativas de CO₂ ou peso.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ImpactCard(
                  label: 'Itens entregues',
                  value: state.deliveredItems.toString(),
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ImpactCard(
                  label: 'Doações concluídas',
                  value: state.totalDelivered.toString(),
                  icon: Icons.volunteer_activism_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                state.donationUrgencies.any(
                      (item) => item.level == UrgencyLevel.critical,
                    )
                    ? Icons.warning_amber_rounded
                    : Icons.insights_outlined,
                color:
                    state.donationUrgencies.any(
                      (item) => item.level == UrgencyLevel.critical,
                    )
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF1F8A70),
              ),
              title: const Text('Urgência territorial'),
              subtitle: Text(
                '${state.donationUrgencies.where((item) => item.level == UrgencyLevel.critical).length} áreas com prazo vencido ou em até 3 dias. Consulte o mapa para ver as datas.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DonationsScreen extends StatelessWidget {
  const DonationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doações disponíveis'),
        actions: const [_AccessibilityMenu()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Todas'),
                selected: true,
                onSelected: (_) {},
              ),
              FilterChip(
                label: const Text('Disponíveis'),
                selected: false,
                onSelected: (_) {},
              ),
              FilterChip(
                label: const Text('Pendentes'),
                selected: false,
                onSelected: (_) {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...state.visibleDonations.map(
            (donation) => _DonationCard(donation: donation),
          ),
        ],
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  void _showOrganization(Organization organization) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: _OrganizationDetails(organization: organization),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();
    final urgencies = state.donationUrgencies;
    final markers = [
      ...state.buildDonationMarkers(),
      ...state.organizations.map(
        (organization) => Marker(
          point: LatLng(organization.latitude, organization.longitude),
          width: 42,
          height: 48,
          child: GestureDetector(
            onTap: () => _showOrganization(organization),
            child: const Icon(
              Icons.volunteer_activism,
              color: Color(0xFFB05A00),
              size: 34,
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de doações'),
        actions: [
          const _AccessibilityMenu(),
          IconButton(
            tooltip: 'Atualizar organizações',
            onPressed: state.loadOrganizations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.organizationsError != null)
            MaterialBanner(
              content: Text(state.organizationsError!),
              actions: [
                TextButton(
                  onPressed: state.loadOrganizations,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          Expanded(
            flex: 3,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(-23.5489, -46.6388),
                initialZoom: 10,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.doacerto_mobile',
                ),
                CircleLayer(
                  circles: urgencies
                      .map(
                        (area) => CircleMarker(
                          point: area.point,
                          radius: 48,
                          useRadiusInMeter: false,
                          color: area.color.withValues(alpha: 0.25),
                          borderColor: area.color,
                          borderStrokeWidth: 2,
                        ),
                      )
                      .toList(),
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 12, color: Color(0xFF1F8A70)),
                const SizedBox(width: 6),
                const Text('Doações', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(
                  Icons.volunteer_activism,
                  size: 14,
                  color: Color(0xFFB05A00),
                ),
                const SizedBox(width: 6),
                Text(
                  'Organizações (${state.organizations.length})',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 12,
              children: UrgencyLevel.values.map((level) {
                final sample = DonationUrgency(
                  area: '',
                  point: const LatLng(0, 0),
                  availableCount: 0,
                  nearestDeadline: null,
                  level: level,
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 11, color: sample.color),
                    const SizedBox(width: 4),
                    Text(sample.label, style: const TextStyle(fontSize: 11)),
                  ],
                );
              }).toList(),
            ),
          ),
          if (urgencies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Círculos agrupam campanhas disponíveis por localização. Vermelho: prazo vencido ou em até 3 dias; amarelo: 4–7 dias; verde: prazo posterior; cinza: sem prazo. É uma regra por datas cadastradas, não uma previsão de demanda. A confiança depende da qualidade do cadastro; a decisão é humana.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            flex: 2,
            child: state.organizations.isEmpty && urgencies.isEmpty
                ? Center(
                    child: Text(
                      state.organizationsError == null
                          ? 'Nenhuma organização carregada. Inicie o servidor DoaCerto.'
                          : 'Não foi possível carregar as organizações.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: urgencies.length + state.organizations.length,
                    itemBuilder: (context, index) {
                      if (index < urgencies.length) {
                        final area = urgencies[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.circle,
                              color: area.color,
                              size: 20,
                            ),
                            title: Text('${area.area} • ${area.label}'),
                            subtitle: Text(
                              '${area.availableCount} campanhas disponíveis'
                              '${area.nearestDeadline == null ? '' : ' • prazo mais próximo: ${DateFormat('dd/MM/yyyy').format(area.nearestDeadline!)}'}',
                            ),
                          ),
                        );
                      }
                      final organization =
                          state.organizations[index - urgencies.length];
                      return _OrganizationListCard(
                        organization: organization,
                        onTap: () => _showOrganization(organization),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send(DonationState state, [String? suggestedMessage]) async {
    final message = suggestedMessage ?? _messageController.text;
    if (message.trim().isEmpty || _sending) return;
    _messageController.clear();
    setState(() => _sending = true);
    await state.sendAssistantMessage(message);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();
    final messages = state.assistantMessages;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente DoaCerto'),
        actions: [
          const _AccessibilityMenu(),
          if (messages.isNotEmpty)
            IconButton(
              tooltip: 'Limpar conversa',
              onPressed: () async {
                final donationState = context.read<DonationState>();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Limpar conversa?'),
                    content: const Text(
                      'O histórico salvo neste aparelho e no servidor será removido.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await donationState.clearAssistantHistory();
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const _AssistantBubble(
                        text: 'Olá! Posso ajudar a encontrar instituições, verificar quais itens elas aceitam e indicar como chegar.',
                      ),
                      const SizedBox(height: 16),
                      ActionChip(
                        avatar: const Icon(Icons.checkroom_outlined),
                        label: const Text('Onde doar roupas?'),
                        onPressed: _sending
                            ? null
                            : () => _send(
                                state,
                                'Recomende instituições para doar roupas',
                              ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.restaurant_outlined),
                        label: const Text('Onde doar alimentos?'),
                        onPressed: _sending
                            ? null
                            : () => _send(state, 'Onde posso doar alimentos?'),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: message.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 340),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: message.isUser
                                    ? const Color(0xFF1F8A70)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                message.text,
                                style: TextStyle(
                                  color: message.isUser
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          ...message.recommendations.map(
                            (organization) => _OrganizationListCard(
                              organization: organization,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (state.assistantError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                state.assistantError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(state),
                      decoration: const InputDecoration(
                        hintText: 'Pergunte sobre doações ou instituições...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar mensagem',
                    onPressed: _sending ? null : () => _send(state),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text),
  );
}

class _OrganizationListCard extends StatelessWidget {
  const _OrganizationListCard({required this.organization, this.onTap});

  final Organization organization;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF1DF),
          child: Icon(Icons.volunteer_activism, color: Color(0xFFB05A00)),
        ),
        title: Text(
          organization.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${organization.neighborhood}${organization.zone.isNotEmpty ? ' • ${organization.zone}' : ''}'
          '${organization.acceptedItems.isNotEmpty ? '\nAceita: ${organization.acceptedItems.take(3).join(', ')}' : ''}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Traçar rota',
          onPressed: () => _openOrganizationRoute(context, organization),
          icon: const Icon(Icons.directions, color: Color(0xFF1F8A70)),
        ),
      ),
    );
  }
}

class _OrganizationDetails extends StatelessWidget {
  const _OrganizationDetails({required this.organization});

  final Organization organization;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(organization.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text('${organization.address}, ${organization.neighborhood}'),
      if (organization.category.isNotEmpty) Text(organization.category),
      if (organization.urgency.isNotEmpty)
        Text('Urgência: ${organization.urgency}'),
      if (organization.acceptedItems.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Itens aceitos: ${organization.acceptedItems.join(', ')}'),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => _openOrganizationRoute(context, organization),
        icon: const Icon(Icons.directions),
        label: const Text('Traçar rota'),
      ),
    ],
  );
}

Future<void> _openOrganizationRoute(
  BuildContext context,
  Organization organization,
) async {
  final uri = Uri.parse(organization.routeUrl);
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o aplicativo de mapas.'),
        ),
      );
    }
  } catch (error) {
    debugPrint('Erro ao abrir rota: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro ao abrir a rota. Verifique se há um navegador disponível.',
          ),
        ),
      );
    }
  }
}

class AddDonationScreen extends StatefulWidget {
  const AddDonationScreen({super.key});

  @override
  State<AddDonationScreen> createState() => _AddDonationScreenState();
}

class _AddDonationScreenState extends State<AddDonationScreen> {
  final _titleController = TextEditingController();
  final _quantityController = TextEditingController(text: '10');
  final _locationController = TextEditingController(text: 'São Paulo - SP');
  final _descController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String category = 'Alimentos';
  DateTime? _scheduledAt;

  @override
  void dispose() {
    _titleController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _descController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_scheduledAt!),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha um horário futuro para o agendamento.'),
        ),
      );
      return;
    }
    setState(() => _scheduledAt = selected);
  }

  void _submit(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;

    final state = context.read<DonationState>();
    final createdDonation = state.addDonation(
      title: _titleController.text.trim(),
      category: category,
      location: _locationController.text.trim(),
      quantity: int.parse(_quantityController.text),
      description: _descController.text.trim(),
      deadline: _deadlineController.text.trim().isEmpty
          ? DateFormat('yyyy-MM-dd')
                .format(DateTime.now().add(const Duration(days: 21)))
          : _deadlineController.text.trim(),
      latitude: -23.5489,
      longitude: -46.6388,
      scheduledAt: _scheduledAt,
    );

    _showDonationReceipt(context, createdDonation);

    _titleController.clear();
    _quantityController.text = '10';
    _locationController.clear();
    _descController.clear();
    _deadlineController.clear();
    setState(() => _scheduledAt = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova doação'),
        actions: const [_AccessibilityMenu()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleController,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o título.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Título da doação',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              items: const [
                DropdownMenuItem(value: 'Alimentos', child: Text('Alimentos')),
                DropdownMenuItem(value: 'Vestuário', child: Text('Vestuário')),
                DropdownMenuItem(value: 'Educação', child: Text('Educação')),
                DropdownMenuItem(
                  value: 'Itens de higiene',
                  child: Text('Itens de higiene'),
                ),
              ],
              onChanged: (value) => category = value ?? category,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              validator: (value) =>
                  value == null ||
                      int.tryParse(value) == null ||
                      int.parse(value) <= 0
                  ? 'Quantidade inválida.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe a localização.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Localização',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _deadlineController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Prazo final',
                border: OutlineInputBorder(),
              ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) {
                  _deadlineController.text = DateFormat('yyyy-MM-dd')
                      .format(picked);
                }
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _scheduledAt != null,
              title: const Text('Agendar entrega ou recolhimento'),
              subtitle: Text(
                _scheduledAt == null
                    ? 'Escolha uma data e horário (opcional).'
                    : DateFormat('dd/MM/yyyy às HH:mm').format(_scheduledAt!),
              ),
              onChanged: (enabled) async {
                if (enabled == true) {
                  await _pickSchedule();
                } else {
                  setState(() => _scheduledAt = null);
                }
              },
            ),
            if (_scheduledAt != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickSchedule,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Alterar data e horário'),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              minLines: 3,
              maxLines: 5,
              validator: (value) => value == null || value.trim().length < 10
                  ? 'Descreva a doação com pelo menos 10 caracteres.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _submit(context),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Publicar doação'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: const [_AccessibilityMenu()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFE8F5F1),
                    child: Text(
                      state.userName.substring(0, 1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F8A70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.userName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          state.userRole == 'empresa'
                              ? 'Empresa parceira'
                              : 'Doador individual',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: Text('Impacto social'),
            subtitle: Text(
              '${state.deliveredItems} itens entregues em ${state.totalDelivered} doações concluídas',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('Histórico'),
            subtitle: Text(
              '${state.scheduledDonations} doações com entrega ou recolhimento agendado',
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacidade e acessibilidade'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast_outlined),
            title: const Text('Alto contraste'),
            value: state.highContrast,
            onChanged: state.setHighContrast,
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Tamanho do texto'),
            subtitle: Text('${(state.fontScale * 100).round()}%'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Diminuir texto',
                  onPressed: () => state.setFontScale(state.fontScale - 0.1),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Aumentar texto',
                  onPressed: () => state.setFontScale(state.fontScale + 0.1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Consentimento de localização'),
            subtitle: Text(
              state.locationConsentGranted
                  ? 'Autorizado para uso futuro; localização ainda não é coletada pelo app.'
                  : state.locationConsentDecided
                  ? 'Não autorizado; nenhuma localização do dispositivo é coletada.'
                  : 'Ainda não definido.',
            ),
            onTap: () => _editLocationConsent(context, state),
          ),
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text('Sair'),
            onTap: () async {
              await context.read<DonationState>().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DonationCard extends StatelessWidget {
  const _DonationCard({required this.donation});

  final DonationItem donation;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    donation.category == 'Alimentos'
                        ? Icons.local_grocery_store
                        : Icons.card_giftcard,
                    color: const Color(0xFF1F8A70),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        donation.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${donation.category} • ${donation.location}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: donation.status == 'Disponível'
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    donation.status,
                    style: TextStyle(
                      color: donation.status == 'Disponível'
                          ? const Color(0xFF166534)
                          : const Color(0xFF92400E),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              donation.description,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Colors.black54,
                ),
                const SizedBox(width: 6),
                Text('${donation.quantity} itens disponíveis'),
                const SizedBox(width: 18),
                const Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: Colors.black54,
                ),
                const SizedBox(width: 6),
                Text(donation.deadline),
              ],
            ),
            if (donation.scheduledAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.event_available_outlined,
                    size: 18,
                    color: Color(0xFF1F8A70),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Agendada: ${DateFormat('dd/MM/yyyy HH:mm').format(donation.scheduledAt!)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Detalhes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      state.userRole == 'empresa' &&
                          donation.status == 'Pendente'
                      ? FilledButton.icon(
                          onPressed: () =>
                              state.markDonationDelivered(donation.id),
                          icon: const Icon(Icons.task_alt),
                          label: const Text('Confirmar entrega'),
                        )
                      : FilledButton(
                          onPressed:
                              donation.status == 'Disponível' &&
                                  donation.quantity > 0
                              ? () => state.offerDonation(donation.id)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1F8A70),
                          ),
                          child: const Text('Ofertar'),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class _AccessibilityMenu extends StatelessWidget {
  const _AccessibilityMenu();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DonationState>();
    return PopupMenuButton<String>(
      tooltip: 'Acessibilidade',
      icon: const Icon(Icons.accessibility_new),
      onSelected: (value) {
        switch (value) {
          case 'contrast':
            state.setHighContrast(!state.highContrast);
          case 'font_down':
            state.setFontScale(state.fontScale - 0.1);
          case 'font_up':
            state.setFontScale(state.fontScale + 0.1);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'contrast',
          child: Text(
            state.highContrast
                ? 'Desativar alto contraste'
                : 'Ativar alto contraste',
          ),
        ),
        const PopupMenuItem(value: 'font_down', child: Text('Diminuir texto')),
        const PopupMenuItem(value: 'font_up', child: Text('Aumentar texto')),
      ],
    );
  }
}

Future<void> _showDonationReceipt(
  BuildContext context,
  DonationItem donation,
) async {
  final receiptText = [
    'COMPROVANTE DIGITAL DE DOAÇÃO',
    'Código: ${donation.receiptCode ?? donation.id}',
    'Item: ${donation.title}',
    'Categoria: ${donation.category}',
    'Quantidade: ${donation.quantity}',
    'Responsável: ${donation.donor}',
    'Local: ${donation.location}',
    if (donation.scheduledAt != null)
      'Agendamento: ${DateFormat('dd/MM/yyyy HH:mm').format(donation.scheduledAt!)}',
    'Emitido em: ${DateFormat('dd/MM/yyyy HH:mm').format(donation.createdAt)}',
    'Status: ${donation.status}',
  ].join('\n');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Comprovante digital'),
      content: SelectableText(receiptText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: receiptText));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Comprovante copiado.')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
      ],
    ),
  );
}

Future<void> _editLocationConsent(
  BuildContext context,
  DonationState state,
) async {
  final consent = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Consentimento de localização'),
      content: const Text(
        'Se você autorizar, sua localização será usada somente para calcular pontos de coleta próximos e não será armazenada nem compartilhada com terceiros. O app ainda não coleta a localização do dispositivo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Revogar / não autorizar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Autorizar uso futuro'),
        ),
      ],
    ),
  );
  if (consent != null && context.mounted) {
    await state.saveLocationConsent(decided: true, granted: consent);
  }
}
