import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('Donation offers preserve quantities, photos, and delivery details', () {
    final schedule = DateTime(2026, 12, 1, 14, 30);
    final donation = DonationItem(
      id: 'with-offer',
      title: 'Roupas',
      category: 'Vestuário',
      quantity: 3,
      location: 'São Paulo - SP',
      description: 'Roupas em bom estado para doação.',
      deadline: '2026-12-10',
      latitude: -23.55,
      longitude: -46.63,
      status: 'Disponível',
      donor: 'Instituição',
      createdAt: DateTime(2026, 11, 10),
      offeredQuantity: 2,
      offers: [
        DonationOffer(
          id: 'offer-1',
          donor: 'Ana',
          quantity: 2,
          photos: ['aGVsbG8='],
          note: 'Tamanho infantil',
          deliveryOption: 'Entregar no local indicado',
          createdAt: DateTime(2026, 11, 11),
          scheduledAt: schedule,
        ),
      ],
    );

    final restored = DonationItem.fromJson(donation.toJson());
    expect(restored.offers, hasLength(1));
    expect(restored.offers.single.donor, 'Ana');
    expect(restored.offers.single.quantity, 2);
    expect(restored.offers.single.photos, ['aGVsbG8=']);
    expect(restored.offers.single.note, 'Tamanho infantil');
    expect(restored.offers.single.scheduledAt, schedule);
  });

  test(
    'Offering a partial quantity updates the listing and validates stock',
    () async {
      SharedPreferences.setMockInitialValues({});
      final donation = DonationItem(
        id: 'available',
        title: 'Cestas básicas',
        category: 'Alimentos',
        quantity: 5,
        location: 'São Paulo - SP',
        description: 'Cestas para famílias em situação vulnerável.',
        deadline: '2026-12-10',
        latitude: -23.55,
        longitude: -46.63,
        status: 'Disponível',
        donor: 'Instituição',
        createdAt: DateTime(2026, 11, 10),
      );
      final state = DonationState(initialDonations: [donation]);
      final offered = await state.offerDonation(
        donation.id,
        quantity: 3,
        photos: ['aGVsbG8='],
        note: 'Itens novos',
        deliveryOption: 'Entregar no local indicado',
      );

      expect(offered, isTrue);
      expect(state.donations.single.quantity, 2);
      expect(state.donations.single.offeredQuantity, 3);
      expect(state.donations.single.offers.single.quantity, 3);
      expect(state.donations.single.offers.single.photos, ['aGVsbG8=']);
      expect(state.donations.single.status, 'Disponível');
      expect(state.totalDelivered, 1);
      expect(state.deliveredItems, 3);
      expect(state.myDeliveredDonations, 1);
      expect(state.myDeliveredItems, 3);

      expect(
        await state.offerDonation(
          donation.id,
          quantity: 3,
          deliveryOption: 'Entregar no local indicado',
        ),
        isFalse,
      );
      expect(state.donations.single.quantity, 2);

      expect(
        await state.offerDonation(
          donation.id,
          quantity: 2,
          deliveryOption: 'Preciso combinar a retirada',
        ),
        isTrue,
      );
      expect(state.donations.single.status, 'Entregue');
      expect(state.totalDelivered, 2);
      expect(state.deliveredItems, 5);
      expect(state.myDeliveredDonations, 2);
      expect(state.myDeliveredItems, 5);
      expect(state.donationHistory, hasLength(2));
    },
  );

  test(
    'Demo accounts validate credentials and persist account roles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = DonationState();

      expect(
        await state.login(
          email: 'maria@doacerto.com',
          password: 'senha-incorreta',
        ),
        isNotNull,
      );
      expect(
        await state.login(email: 'maria@doacerto.com', password: '123456'),
        isNull,
      );
      await state.logout();

      expect(
        await state.registerUser(
          name: 'Ana Costa',
          email: 'ANA@EXAMPLE.COM',
          password: 'senha123',
          role: 'empresa',
        ),
        isNull,
      );
      expect(state.isLoggedIn, isTrue);
      expect(state.userName, 'Ana Costa');
      expect(state.userRole, 'empresa');
      expect(
        await state.registerUser(
          name: 'Outra Pessoa',
          email: 'ana@example.com',
          password: 'senha123',
          role: 'doador',
        ),
        isNotNull,
      );

      await state.logout();
      expect(
        await state.login(email: 'ana@example.com', password: 'incorreta'),
        isNotNull,
      );
      expect(state.isLoggedIn, isFalse);
      expect(
        await state.login(email: 'ana@example.com', password: 'senha123'),
        isNull,
      );
      expect(state.isLoggedIn, isTrue);
      expect(state.userRole, 'empresa');
    },
  );

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

  testWidgets('Donation card opens details and offer form', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final donation = DonationItem(
      id: 'card-donation',
      title: 'Cestas básicas',
      category: 'Alimentos',
      quantity: 5,
      location: 'São Paulo - SP',
      description: 'Cestas para famílias em situação vulnerável.',
      deadline: '2026-12-10',
      latitude: -23.55,
      longitude: -46.63,
      status: 'Disponível',
      donor: 'Instituição',
      createdAt: DateTime(2026, 11, 10),
      receiptCode: 'DS-TESTE',
    );
    final state = DonationState(initialDonations: [donation]);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(body: DonationCard(donation: donation)),
        ),
      ),
    );

    await tester.tap(find.text('Detalhes'));
    await tester.pumpAndSettle();
    expect(find.text('Detalhes da doação'), findsOneWidget);
    expect(find.text('Código'), findsOneWidget);
    expect(find.text('DS-TESTE'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ofertar'));
    await tester.pumpAndSettle();
    expect(find.text('Ofertar doação'), findsOneWidget);
    expect(find.textContaining('5 itens disponíveis'), findsOneWidget);
    expect(find.text('Selecionar fotos'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar oferta').last);
    await tester.pumpAndSettle();

    expect(state.donations.single.quantity, 4);
    expect(state.donations.single.offers.single.quantity, 1);
    expect(state.totalDelivered, 1);
    expect(state.deliveredItems, 1);
    expect(state.myDeliveredDonations, 1);
    expect(state.myDeliveredItems, 1);
    expect(find.text('Oferta registrada como entregue.'), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DonationHistoryScreen()),
      ),
    );
    expect(find.text('Histórico de ofertas'), findsOneWidget);
    expect(find.text('Cestas básicas'), findsOneWidget);
    expect(find.textContaining('1 item entregue'), findsOneWidget);
    expect(find.text('Entregue'), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.tap(find.text('Histórico de ofertas'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico de ofertas'), findsOneWidget);
    expect(find.text('Cestas básicas'), findsOneWidget);
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
