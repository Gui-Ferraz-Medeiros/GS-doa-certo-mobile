import 'package:flutter/material.dart';

const String resourcesDashboardRoute = '/territory/resources';
const String climateDashboardRoute = '/territory/climate';
const String servicesDashboardRoute = '/territory/services';

class TerritorialDashboardArgs {
  const TerritorialDashboardArgs({
    required this.territory,
    required this.availableDonations,
    required this.pendingDonations,
    required this.deliveredItems,
    required this.completedDonations,
    required this.organizationCount,
    required this.urgentAreas,
    required this.monthlyDonationCounts,
  });

  final String territory;
  final int availableDonations;
  final int pendingDonations;
  final int deliveredItems;
  final int completedDonations;
  final int organizationCount;
  final int urgentAreas;
  final List<int> monthlyDonationCounts;
}

typedef OpenTerritorialDashboard = void Function(
  String route,
  String territory,
);

class TerritorialDashboardHub extends StatefulWidget {
  const TerritorialDashboardHub({super.key, required this.onOpenDashboard});

  final OpenTerritorialDashboard onOpenDashboard;

  @override
  State<TerritorialDashboardHub> createState() =>
      _TerritorialDashboardHubState();
}

class _TerritorialDashboardHubState extends State<TerritorialDashboardHub> {
  static const _territories = [
    'São Paulo - SP',
    'Campinas - SP',
    'Rio de Janeiro - RJ',
  ];

  String _territory = _territories.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inteligência territorial')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Selecione o território',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _territory,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            items: _territories
                .map(
                  (territory) => DropdownMenuItem(
                    value: territory,
                    child: Text(territory),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _territory = value);
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Explore recursos, clima e serviços. Dados reais do app e séries '
            'sintéticas estão identificados em cada painel.',
          ),
          const SizedBox(height: 12),
          _DashboardLink(
            icon: Icons.inventory_2_outlined,
            title: 'Recursos e doações',
            subtitle: 'Campanhas, entregas e histórico registrado',
            onTap: () =>
                widget.onOpenDashboard(resourcesDashboardRoute, _territory),
          ),
          _DashboardLink(
            icon: Icons.cloud_outlined,
            title: 'Clima local',
            subtitle: 'Série demonstrativa de precipitação e alerta',
            onTap: () =>
                widget.onOpenDashboard(climateDashboardRoute, _territory),
          ),
          _DashboardLink(
            icon: Icons.apartment_outlined,
            title: 'Serviços e demanda',
            subtitle: 'Organizações, campanhas e tendência de demanda',
            onTap: () =>
                widget.onOpenDashboard(servicesDashboardRoute, _territory),
          ),
          const SizedBox(height: 8),
          const Text(
            'Os painéis apoiam a análise; não substituem dados oficiais '
            'atualizados nem a decisão de gestores e cidadãos.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class ResourcesDashboardScreen extends StatelessWidget {
  const ResourcesDashboardScreen({super.key, required this.args});

  final TerritorialDashboardArgs args;

  @override
  Widget build(BuildContext context) {
    return _DashboardPage(
      title: 'Recursos e doações',
      territory: args.territory,
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              'Campanhas disponíveis',
              args.availableDonations.toString(),
              Icons.inventory_2_outlined,
            ),
            _MetricData(
              'Em análise',
              args.pendingDonations.toString(),
              Icons.hourglass_bottom,
            ),
            _MetricData(
              'Itens entregues',
              args.deliveredItems.toString(),
              Icons.volunteer_activism_outlined,
            ),
            _MetricData(
              'Doações concluídas',
              args.completedDonations.toString(),
              Icons.check_circle_outline,
            ),
          ],
        ),
        _TrendChartCard(
          title: 'Campanhas cadastradas por mês',
          values: args.monthlyDonationCounts
              .map((value) => value.toDouble())
              .toList(),
          labels: _monthLabels,
          unit: 'campanhas',
          source:
              'Histórico calculado dos registros locais de doações nos últimos '
              'seis meses. Uma série curta ou vazia não permite inferir tendência.',
        ),
        _TransparentAlert(
          title: args.urgentAreas > 0
              ? 'Campanhas com prazo próximo'
              : 'Sem prazo crítico identificado',
          evidence:
              '${args.urgentAreas} áreas têm campanha disponível vencida ou '
              'com prazo em até três dias, conforme as datas cadastradas.',
          confidence:
              'Baixa a moderada: depende do preenchimento correto dos prazos '
              'e da cobertura dos registros locais.',
          limitations:
              'O indicador não mede demanda social nem disponibilidade real '
              'de estoque; campanhas não cadastradas ficam fora da análise.',
        ),
      ],
    );
  }
}

class ClimateDashboardScreen extends StatelessWidget {
  const ClimateDashboardScreen({super.key, required this.args});

  final TerritorialDashboardArgs args;

  List<double> _precipitationFor(String territory) {
    if (territory.startsWith('Campinas')) {
      return const [82, 94, 76, 118, 132, 145];
    }
    if (territory.startsWith('Rio')) {
      return const [110, 98, 126, 134, 152, 160];
    }
    return const [74, 88, 91, 107, 121, 138];
  }

  @override
  Widget build(BuildContext context) {
    final values = _precipitationFor(args.territory);
    final increasing = values[5] > values[4] && values[4] > values[3];
    final latest = values.last.round();
    return _DashboardPage(
      title: 'Clima local',
      territory: args.territory,
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              'Precipitação no período',
              '$latest mm',
              Icons.water_drop_outlined,
            ),
            _MetricData(
              'Variação em 3 períodos',
              '${(values[5] - values[2]).round()} mm',
              Icons.trending_up,
            ),
          ],
        ),
        _TrendChartCard(
          title: 'Precipitação mensal demonstrativa',
          values: values,
          labels: _monthLabels,
          unit: 'mm',
          source:
              'Série inteiramente sintética, criada para demonstrar leitura '
              'de histórico. Não é uma observação meteorológica nem previsão.',
        ),
        _TransparentAlert(
          title: increasing
              ? 'Atenção: sequência de alta na série simulada'
              : 'Sem sequência de alta identificada',
          evidence:
              'A regra compara os três últimos valores demonstrativos: '
              '${values[3].round()} mm, ${values[4].round()} mm e '
              '${values[5].round()} mm.',
          confidence:
              'Baixa: série sintética e regra simples, sem calibração '
              'meteorológica.',
          limitations:
              'Não use para decisões de emergência, previsão de alagamento '
              'ou orientação de saúde. Consulte fontes oficiais.',
        ),
      ],
    );
  }
}

class ServicesDashboardScreen extends StatelessWidget {
  const ServicesDashboardScreen({super.key, required this.args});

  final TerritorialDashboardArgs args;

  static const _demandSeries = [34.0, 38.0, 36.0, 42.0, 47.0, 51.0];

  @override
  Widget build(BuildContext context) {
    final trendIncreasing =
        _demandSeries[5] > _demandSeries[4] &&
        _demandSeries[4] > _demandSeries[3];
    return _DashboardPage(
      title: 'Serviços e demanda',
      territory: args.territory,
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              'Organizações encontradas',
              args.organizationCount.toString(),
              Icons.apartment_outlined,
            ),
            _MetricData(
              'Campanhas disponíveis',
              args.availableDonations.toString(),
              Icons.volunteer_activism_outlined,
            ),
            _MetricData(
              'Áreas em atenção',
              args.urgentAreas.toString(),
              Icons.warning_amber_outlined,
            ),
          ],
        ),
        _TrendChartCard(
          title: 'Índice demonstrativo de procura',
          values: _demandSeries,
          labels: _monthLabels,
          unit: 'pontos',
          source:
              'Série sintética de referência, sem representar solicitações '
              'reais, fila de atendimento ou pessoas identificáveis.',
        ),
        _TransparentAlert(
          title: trendIncreasing
              ? 'Procura simulada em tendência de alta'
              : 'Sem tendência de alta na simulação',
          evidence:
              'A série de referência subiu de ${_demandSeries[3].round()} '
              'para ${_demandSeries[4].round()} e '
              '${_demandSeries[5].round()} pontos nos três períodos finais.',
          confidence:
              'Baixa: índice ilustrativo sem validação com dados de serviços '
              'públicos.',
          limitations:
              'O número de organizações depende da disponibilidade da API e '
              'não representa capacidade de atendimento. Nenhuma priorização '
              'automática é feita.',
        ),
      ],
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.title,
    required this.territory,
    required this.children,
  });

  final String title;
  final String territory;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(territory, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          ...children.expand((child) => [child, const SizedBox(height: 14)]),
          const _HumanDecisionNote(),
        ],
      ),
    );
  }
}

class _DashboardLink extends StatelessWidget {
  const _DashboardLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 360 ? 1 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(metric.icon, size: 20),
                          const SizedBox(height: 8),
                          Text(
                            metric.value,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(metric.label),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

List<String> get _monthLabels {
  const months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  final now = DateTime.now();
  return List.generate(
    6,
    (index) => months[DateTime(now.year, now.month - 5 + index).month - 1],
  );
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({
    required this.title,
    required this.values,
    required this.labels,
    required this.unit,
    required this.source,
  });

  final String title;
  final List<double> values;
  final List<String> labels;
  final String unit;
  final String source;

  @override
  Widget build(BuildContext context) {
    final chartDescription = values
        .asMap()
        .entries
        .map((entry) => '${labels[entry.key]}: ${entry.value.round()} $unit')
        .join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Semantics(
              label: '$title. $chartDescription',
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendChartPainter(
                    values: values,
                    labels: labels,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(source, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || labels.length != values.length) return;
    const horizontalPadding = 12.0;
    const topPadding = 12.0;
    const bottomPadding = 24.0;
    final plotHeight = size.height - topPadding - bottomPadding;
    final plotWidth = size.width - horizontalPadding * 2;
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final spread = maximum - minimum;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : horizontalPadding + plotWidth * index / (values.length - 1);
      final normalized = spread == 0 ? 0.5 : (values[index] - minimum) / spread;
      final y = topPadding + plotHeight * (1 - normalized);
      points.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var row = 0; row < 3; row++) {
      final y = topPadding + plotHeight * row / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(line, linePaint);

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(points[index], 4, pointPaint);
      final label = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            points[index].dx - label.width / 2,
            size.height - label.height,
            label.width,
            label.height,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white,
      );
      label.paint(
        canvas,
        Offset(points[index].dx - label.width / 2, size.height - label.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.color != color;
}

class _TransparentAlert extends StatelessWidget {
  const _TransparentAlert({
    required this.title,
    required this.evidence,
    required this.confidence,
    required this.limitations,
  });

  final String title;
  final String evidence;
  final String confidence;
  final String limitations;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _AlertDetail(label: 'Evidência', value: evidence),
            _AlertDetail(label: 'Confiança', value: confidence),
            _AlertDetail(label: 'Limitações', value: limitations),
          ],
        ),
      ),
    );
  }
}

class _AlertDetail extends StatelessWidget {
  const _AlertDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('$label: $value'),
    );
  }
}

class _HumanDecisionNote extends StatelessWidget {
  const _HumanDecisionNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline),
        title: const Text('A decisão final é humana.'),
        subtitle: Text(
          'Use os alertas como apoio e valide as informações antes de agir.',
        ),
      ),
    );
  }
}
