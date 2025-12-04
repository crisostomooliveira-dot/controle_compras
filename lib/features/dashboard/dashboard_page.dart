import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_compras/features/home/tabs/tracking_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _dashboardData;

  @override
  void initState() {
    super.initState();
    _dashboardData = _fetchDashboardData();
  }

  Future<Map<String, dynamic>> _fetchDashboardData() async {
    final constructionsFuture = FirebaseFirestore.instance.collection('constructions').get();
    final requestsFuture = FirebaseFirestore.instance.collection('purchase_requests').get();
    final results = await Future.wait([constructionsFuture, requestsFuture]);

    final constructions = (results[0] as QuerySnapshot).docs;
    final requests = (results[1] as QuerySnapshot).docs;

    double totalPurchasedValue = 0;
    final Map<String, List<DocumentSnapshot>> requestsByConstruction = {};
    final Map<String, double> valueByConstruction = {};

    for (var req in requests) {
      final data = req.data() as Map<String, dynamic>;
      final constructionId = data['constructionId'];
      final value = (data['finalValue'] ?? data['totalPrice'] as num?)?.toDouble() ?? 0.0;

      if (constructionId != null) {
        (requestsByConstruction[constructionId] ??= []).add(req);
        valueByConstruction[constructionId] = (valueByConstruction[constructionId] ?? 0) + value;
      }
      totalPurchasedValue += value;
    }

    return {
      'constructions': constructions,
      'requestsByConstructionId': requestsByConstruction,
      'valueByConstruction': valueByConstruction,
      'totalPurchasedValue': totalPurchasedValue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: Text('Nenhum dado para exibir.'));

          final constructions = snapshot.data!['constructions'] as List<DocumentSnapshot>;
          final valueByConstruction = snapshot.data!['valueByConstruction'] as Map<String, double>;
          final totalPurchasedValue = snapshot.data!['totalPurchasedValue'] as double;

          return RefreshIndicator(
            onRefresh: () async => setState(() => _dashboardData = _fetchDashboardData()),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 350, childAspectRatio: 2.0, crossAxisSpacing: 16, mainAxisSpacing: 16),
                itemCount: constructions.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildTotalValueCard(totalPurchasedValue);
                  }
                  final constructionDoc = constructions[index - 1];
                  final totalValue = valueByConstruction[constructionDoc.id] ?? 0.0;
                  return _buildConstructionCard(context, constructionDoc, totalValue);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTotalValueCard(double totalValue) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).primaryColor, width: 2)),
      elevation: 0,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('VALOR TOTAL GERAL', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalValue), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildConstructionCard(BuildContext context, DocumentSnapshot constructionDoc, double totalValue) {
    final constructionData = constructionDoc.data()! as Map<String, dynamic>;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300, width: 1)),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: Text('Pedidos para ${constructionData['name']}')), body: TrackingTab(constructionIdFilter: constructionDoc.id)))),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(constructionData['name'] ?? 'Obra sem nome', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalValue), style: TextStyle(fontSize: 22, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
