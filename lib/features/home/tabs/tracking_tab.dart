import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_compras/features/purchase/purchase_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TrackingTab extends StatefulWidget {
  final String? constructionIdFilter;

  const TrackingTab({super.key, this.constructionIdFilter});

  @override
  State<TrackingTab> createState() => _TrackingTabState();
}

class _TrackingTabState extends State<TrackingTab> {
  final _nfController = TextEditingController();
  String? _generalStatusFilter;
  String? _paymentStatusFilter;
  String? _deliveryStatusFilter;
  late Stream<QuerySnapshot> _purchasesStream;

  @override
  void initState() {
    super.initState();
    _purchasesStream = const Stream.empty();
    _nfController.addListener(() => _updateStream());
    _updateStream();
  }

  void _updateStream() {
    Query query = FirebaseFirestore.instance.collection('purchase_requests');

    if (widget.constructionIdFilter != null) {
      query = query.where('constructionId', isEqualTo: widget.constructionIdFilter);
    }

    if (_generalStatusFilter != null) {
      query = query.where('status', isEqualTo: _generalStatusFilter);
    }
    if (_nfController.text.isNotEmpty) {
      query = query.where('invoiceNumber', isEqualTo: _nfController.text.trim());
    }
    if (_paymentStatusFilter != null) {
      query = query.where('paymentStatus', isEqualTo: _paymentStatusFilter);
    }
    if (_deliveryStatusFilter != null) {
      query = query.where('deliveryStatus', isEqualTo: _deliveryStatusFilter);
    }

    query = query.orderBy('requestDate', descending: true);

    setState(() {
      _purchasesStream = query.snapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (widget.constructionIdFilter == null) _buildFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _purchasesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Ocorreu um erro.'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhuma compra encontrada.'));

                return ListView(children: snapshot.data!.docs.map((doc) => _buildTrackingCard(context, doc)).toList());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final status = data['status'] ?? 'N/A';
    
    String getSupplierDisplayName() {
      final legacySupplierName = data['selectedSupplierName'];
      if (legacySupplierName != null) return legacySupplierName;
      final items = data['finalItems'] as List<dynamic>?;
      if (items == null || items.isEmpty) return 'N/A';
      final supplierNames = items.map((item) => item['supplierName'] as String?).toSet();
      supplierNames.removeWhere((name) => name == null);
      if (supplierNames.isEmpty) return 'N/A';
      if (supplierNames.length == 1) return supplierNames.first!;
      return 'Compra Mista (${supplierNames.length})';
    }

    final supplierName = getSupplierDisplayName();
    
    Widget content;
    if (status == 'Solicitado') {
      final items = (data['items'] as List<dynamic>?) ?? [];
      content = Text('Aguardando cotação de ${items.length} itens.');
    } else {
      final startDate = (data['orderCreationDate'] as Timestamp?)?.toDate();
      final endDate = (data['expectedDeliveryDate'] as Timestamp?)?.toDate();
      double progress = 0.0;
      Color progressColor = Colors.grey;

      if (startDate != null && endDate != null) {
        final totalDuration = endDate.difference(startDate).inDays;
        if (totalDuration > 0) {
          final passedDuration = DateTime.now().difference(startDate).inDays;
          progress = (passedDuration / totalDuration).clamp(0.0, 1.0);
        }
        progressColor = DateTime.now().isAfter(endDate) ? Colors.red : Colors.blue;
      }
      if (data['deliveryStatus'] == 'Entregue') {
        progress = 1.0;
        progressColor = Colors.green;
      }
      
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (endDate != null) ...[
            LinearProgressIndicator(value: progress, backgroundColor: Colors.grey[300], color: progressColor),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd/MM/yy').format(startDate!)), Text(DateFormat('dd/MM/yy').format(endDate))]),
          ],
          const SizedBox(height: 8),
          Text('Fornecedor: $supplierName'),
          Text('NF: ${data['invoiceNumber'] ?? '-'}'),
          Text('Pag.: ${data['paymentStatus'] ?? '-'} | Entrega: ${data['deliveryStatus'] ?? '-'}'),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => PurchaseDetailPage(purchaseRequestId: doc.id))),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $status', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Filtrar por Status Geral'),
            value: _generalStatusFilter,
            onChanged: (value) {
              setState(() {
                _generalStatusFilter = value;
                _paymentStatusFilter = null;
                _deliveryStatusFilter = null;
                _nfController.clear();
                _updateStream();
              });
            },
            items: ['Solicitado', 'Pedido Criado', 'Finalizado'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          ),
          const SizedBox(height: 12),
          TextField(controller: _nfController, decoration: const InputDecoration(labelText: 'Buscar por Nº da Nota Fiscal')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Pagamento'), value: _paymentStatusFilter, items: ['Aguardando Aprovação', 'Pendente', 'Pago', 'Atrasado'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() { _paymentStatusFilter = v; _updateStream(); }))),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Entrega'), value: _deliveryStatusFilter, items: ['Aguardando Entrega', 'Entregue', 'Em Trânsito', 'Retirar Material'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() { _deliveryStatusFilter = v; _updateStream(); }))),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nfController.dispose();
    super.dispose();
  }
}
