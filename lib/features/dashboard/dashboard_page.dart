import 'dart:async';
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
  StreamSubscription? _requestsSubscription;
  Map<String, dynamic>? _dashboardData;
  final StreamController<Map<String, dynamic>> _dashboardStreamController = StreamController.broadcast();

  final List<Color> _cardColors = [
    Colors.blue.shade100,
    Colors.green.shade100,
    Colors.orange.shade100,
    Colors.purple.shade100,
    Colors.teal.shade100,
    Colors.pink.shade100,
  ];

  @override
  void initState() {
    super.initState();
    _listenToDataChanges();
  }

  void _listenToDataChanges() {
    _requestsSubscription?.cancel();
    _requestsSubscription = FirebaseFirestore.instance.collection('purchase_requests').snapshots().listen((requestsSnapshot) async {
      final constructionsSnapshot = await FirebaseFirestore.instance.collection('constructions').get();
      _processData(constructionsSnapshot, requestsSnapshot);
    });
  }

  void _processData(QuerySnapshot constructionsSnapshot, QuerySnapshot requestsSnapshot) {
    final constructions = constructionsSnapshot.docs;
    final requests = requestsSnapshot.docs;

    double totalPurchasedValue = 0;
    final Map<String, List<DocumentSnapshot>> requestsByConstruction = {};
    final Map<String, double> valueByConstruction = {};

    for (var req in requests) {
      final data = req.data() as Map<String, dynamic>;
      final constructionId = data['constructionId'];
      final value = (data['totalPrice'] as num?)?.toDouble() ?? 0.0;

      if (constructionId != null) {
        (requestsByConstruction[constructionId] ??= []).add(req);
        valueByConstruction[constructionId] = (valueByConstruction[constructionId] ?? 0) + value;
      }
      totalPurchasedValue += value;
    }

    _dashboardData = {
      'constructions': constructions,
      'requestsByConstructionId': requestsByConstruction,
      'valueByConstruction': valueByConstruction,
      'totalPurchasedValue': totalPurchasedValue,
    };
    _dashboardStreamController.add(_dashboardData!);
  }

  Future<void> _refreshData() async {
    final constructionsSnapshot = await FirebaseFirestore.instance.collection('constructions').get();
    final requestsSnapshot = await FirebaseFirestore.instance.collection('purchase_requests').get();
    _processData(constructionsSnapshot, requestsSnapshot);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel de Controle'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _dashboardStreamController.stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _dashboardData == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum dado para exibir.'));

          final data = snapshot.data!;
          final constructions = data['constructions'] as List<DocumentSnapshot>;
          final valueByConstruction = data['valueByConstruction'] as Map<String, double>;
          final totalPurchasedValue = data['totalPurchasedValue'] as double;

          return RefreshIndicator(
            onRefresh: _refreshData,
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
                  final color = _cardColors[(index - 1) % _cardColors.length];
                  return _buildConstructionCard(context, constructionDoc, totalValue, color);
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
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('VALOR TOTAL GERAL', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalValue), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildConstructionCard(BuildContext context, DocumentSnapshot constructionDoc, double totalValue, Color color) {
    final constructionData = constructionDoc.data()! as Map<String, dynamic>;
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: Text('Pedidos para ${constructionData['name']}')), body: TrackingTab(constructionIdFilter: constructionDoc.id)))),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(constructionData['name'] ?? 'Obra sem nome', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalValue), style: TextStyle(fontSize: 22, color: Colors.black.withOpacity(0.7), fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _dashboardStreamController.close();
    super.dispose();
  }
}
