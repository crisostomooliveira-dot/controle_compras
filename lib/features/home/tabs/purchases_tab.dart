import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_compras/features/purchase/purchase_detail_page.dart';
import 'package:controle_compras/features/purchase/purchase_request_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PurchasesTab extends StatefulWidget {
  const PurchasesTab({super.key});

  @override
  State<PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<PurchasesTab> {
  Map<String, String> _constructionNames = {};

  @override
  void initState() {
    super.initState();
    _fetchConstructionNames();
  }

  Future<void> _fetchConstructionNames() async {
    final snapshot = await FirebaseFirestore.instance.collection('constructions').get();
    final names = { for (var doc in snapshot.docs) doc.id : doc.data()['name'] as String? ?? 'Nome não encontrado' };
    if (mounted) setState(() => _constructionNames = names);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('purchase_requests').orderBy('sequentialId', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Ocorreu um erro.'));
            if (snapshot.connectionState == ConnectionState.waiting || _constructionNames.isEmpty) return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhuma solicitação encontrada.'));

            return SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Pedido')),
                  DataColumn(label: Text('Obra')),
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: snapshot.data!.docs.map((doc) => _buildRequestRow(context, doc)).toList(),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PurchaseRequestPage())), child: const Icon(Icons.add), tooltip: 'Nova Solicitação'),
    );
  }

  DataRow _buildRequestRow(BuildContext context, DocumentSnapshot document) {
    final data = document.data()! as Map<String, dynamic>;
    final sequentialId = data['sequentialId']?.toString() ?? 'N/A';
    final status = data['status'] ?? 'N/A';
    final date = (data['requestDate'] as Timestamp?)?.toDate();
    final formattedDate = date != null ? DateFormat('dd/MM/yy').format(date) : '-';
    final constructionName = _constructionNames[data['constructionId']] ?? '-';

    return DataRow(
      cells: [
        DataCell(Text(sequentialId)),
        DataCell(Text(constructionName)),
        DataCell(Text(formattedDate)),
        DataCell(Chip(label: Text(status), backgroundColor: _getStatusColor(status).withOpacity(0.2))),
        DataCell(
          Row(
            children: [
              if (status == 'Solicitado') IconButton(icon: const Icon(Icons.attach_money), color: Colors.amber[800], tooltip: 'Cotar Preços', onPressed: () => _navigateToDetails(context, document.id)),
              IconButton(icon: const Icon(Icons.visibility), color: Colors.blue, tooltip: 'Ver Detalhes', onPressed: () => _navigateToDetails(context, document.id)),
              IconButton(icon: const Icon(Icons.delete), color: Colors.red, tooltip: 'Excluir', onPressed: () => _showDeleteConfirmationDialog(context, document.id)),
            ],
          ),
        ),
      ],
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Solicitado': return Colors.amber;
      case 'Pedido Criado': return Colors.blue;
      case 'Finalizado': return Colors.green;
      default: return Colors.grey;
    }
  }

  void _navigateToDetails(BuildContext context, String purchaseRequestId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => PurchaseDetailPage(purchaseRequestId: purchaseRequestId)));
  }

  void _showDeleteConfirmationDialog(BuildContext context, String purchaseRequestId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza de que deseja excluir esta solicitação?'),
        actions: [
          TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(ctx).pop()),
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Excluir'), onPressed: () {
            Navigator.of(ctx).pop();
            _deletePurchaseRequest(context, purchaseRequestId);
          }),
        ],
      ),
    );
  }

  void _deletePurchaseRequest(BuildContext context, String purchaseRequestId) async {
    try {
      final requestRef = FirebaseFirestore.instance.collection('purchase_requests').doc(purchaseRequestId);
      final quotations = await requestRef.collection('quotations').get();
      for (var doc in quotations.docs) {
        await doc.reference.delete();
      }
      await requestRef.delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitação excluída com sucesso!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }
}
