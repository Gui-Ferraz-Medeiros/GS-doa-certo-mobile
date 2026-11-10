import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:doacerto_mobile/main.dart';
import 'package:doacerto_mobile/territorial_dashboards.dart';

void main() {
  test('Organization reads nested backend coordinates and builds a route', () {
    final organization = Organization.fromJson({
      'id': 'org_01',
      'nome': 'Arsenal da Esperança',
      'bairro': 'Mooca',
      'itens_aceitos': ['Alimentos não perecíveis'],
      'coordenadas': {'latitude': -23.5518, 'longitude': -46.6124},
    });

    expect(organization.name, 'Arsenal da Esperança');
    expect(organization.latitude, -23.5518);
    expect(organization.longitude, -46.6124);
    expect(organization.routeUrl, contains('destination=-23.5518,-46.6124'));
  });

  test('Territorial urgency and impact use donation records transparently', () {
    final now = DateTime.now();
    final critical = DonationItem(
      id: 'critical',
      title: 'Roupas',
      category: 'Vestuário',
      quantity: 0,
      location: 'Mooca - São Paulo',
      description: 'Doação de roupas em bom estado.',
      deadline: DateTime(now.year, now.month, now.day + 2).toIso8601String(),
      latitude: -23.55,
      longitude: -46.61,
      status: 'Disponível',
      donor: 'Empresa',
      createdAt: now,
    );
    final delivered = DonationItem(
      id: 'delivered',
      title: 'Agasalhos',
      category: 'Vestuário',
      quantity: 0,
      location: 'Centro - São Paulo',
      description: 'Agasalhos entregues.',
      deadline: '2026-11-20',
      latitude: -23.55,
      longitude: -46.63,
      status: 'Entregue',
      donor: 'Empresa',
      createdAt: now,
      offeredQuantity: 12,
    );
    final state = DonationState(initialDonations: [critical, delivered]);

    expect(state.donationUrgencies, hasLength(1));
    expect(state.donationUrgencies.single.level, UrgencyLevel.critical);
    expect(state.donationUrgencies.single.availableCount, 1);
    expect(state.deliveredItems, 12);
    expect(state.totalDelivered, 1);
  });

  test('Donation schedule and receipt survive JSON serialization', () {
    final schedule = DateTime(2026, 12, 1, 14, 30);
    final donation = DonationItem(
      id: 'scheduled',
      title: 'Cestas',
      category: 'Alimentos',
      quantity: 5,
      location: 'São Paulo - SP',
      description: 'Cestas para entrega agendada.',
      deadline: '2026-12-10',
      latitude: -23.55,
      longitude: -46.63,
      status: 'Disponível',
      donor: 'Empresa',
      createdAt: DateTime(2026, 11, 10),
      scheduledAt: schedule,
      receiptCode: 'DS-TESTE',
    );
    final restored = DonationItem.fromJson(donation.toJson());

    expect(restored.scheduledAt, schedule);
    expect(restored.receiptCode, 'DS-TESTE');
  });

  testWidgets('DoaCerto app loads login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DonationState()..loadData(),
        child: const DoaCertoApp(),
      ),
    );

    expect(find.text('DoaCerto'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('territorial hub opens named dashboard with selected territory', (
    WidgetTester tester,
  ) async {
    String? openedRoute;
    String? openedTerritory;
    await tester.pumpWidget(
      MaterialApp(
        home: TerritorialDashboardHub(
          onOpenDashboard: (route, territory) {
            openedRoute = route;
            openedTerritory = territory;
          },
        ),
      ),
    );

    expect(find.text('Recursos e doações'), findsOneWidget);
    expect(find.text('Clima local'), findsOneWidget);
    expect(find.text('Serviços e demanda'), findsOneWidget);
    await tester.tap(find.text('Clima local'));

    expect(openedRoute, climateDashboardRoute);
    expect(openedTerritory, 'São Paulo - SP');
  });

  testWidgets('climate dashboard explains synthetic data and alert limits', (
    WidgetTester tester,
  ) async {
    const args = TerritorialDashboardArgs(
      territory: 'São Paulo - SP',
      availableDonations: 2,
      pendingDonations: 1,
      deliveredItems: 5,
      completedDonations: 1,
      organizationCount: 3,
      urgentAreas: 1,
      monthlyDonationCounts: [0, 0, 1, 0, 0, 2],
    );
    await tester.pumpWidget(
      const MaterialApp(home: ClimateDashboardScreen(args: args)),
    );
    expect(find.text('São Paulo - SP'), findsOneWidget);
    expect(find.textContaining('Série inteiramente sintética'), findsOneWidget);
    expect(find.textContaining('Confiança: Baixa'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('A decisão final é humana.'),
      250,
    );
    expect(find.text('A decisão final é humana.'), findsOneWidget);
  });

  testWidgets('resources dashboard fits a narrow mobile viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const args = TerritorialDashboardArgs(
      territory: 'São Paulo - SP',
      availableDonations: 2,
      pendingDonations: 1,
      deliveredItems: 5,
      completedDonations: 1,
      organizationCount: 3,
      urgentAreas: 1,
      monthlyDonationCounts: [0, 0, 1, 0, 0, 2],
    );
    await tester.pumpWidget(
      const MaterialApp(home: ResourcesDashboardScreen(args: args)),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Campanhas disponíveis'), findsOneWidget);
  });
}
