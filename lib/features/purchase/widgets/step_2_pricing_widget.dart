import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Step2PricingWidget extends StatefulWidget {
  final String purchaseRequestId;
  final Map<String, dynamic> requestData;

  const Step2PricingWidget({super.key, required this.purchaseRequestId, required this.requestData});

  @override
  State<Step2PricingWidget> createState() => _Step2PricingWidgetState();
}

class _Step2PricingWidgetState extends State<Step2PricingWidget> {
  String? _selectedSupplierId;
  late Map<String, TextEditingController> _priceControllers;

  @override
  void initState() {
    super.initState();
    final items = widget.requestData['items'] as List;
    _priceControllers = { for (var item in items) item['productId'] as String : TextEditingController() };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text('Etapa 2: Cotação de Preços', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildItemsTable(),
        const Divider(height: 30),
        _buildAddQuotationForm(),
        const Divider(height: 30),
        const Text('Quadro Comparativo de Preços', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _buildQuotationTable(),
      ],
    );
  }
  
  Widget _buildItemsTable() {
    final items = widget.requestData['items'] as List;
    num totalQuantity = items.fold(0, (sum, item) => sum + (item['quantity'] as num));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Itens da Solicitação:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        DataTable(
          columns: const [DataColumn(label: Text('Descrição')), DataColumn(label: Text('Unidade')), DataColumn(label: Text('Quantidade'))],
          rows: [
            ...items.map((item) => DataRow(cells: [DataCell(Text(item['productDescription'])), DataCell(Text(item['unit'])), DataCell(Text(item['quantity'].toString()))])),
            DataRow(cells: [const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))), const DataCell(Text('')), DataCell(Text(totalQuantity.toString(), style: const TextStyle(fontWeight: FontWeight.bold)))])
          ],
        ),
      ],
    );
  }

  Widget _buildAddQuotationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('suppliers').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();
            return DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Selecione um Fornecedor para Cotar'),
              items: snapshot.data!.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
              onChanged: (value) => setState(() => _selectedSupplierId = value),
            );
          },
        ),
        if (_selectedSupplierId != null) ..._buildPriceFields(),
        if (_selectedSupplierId != null)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: ElevatedButton.icon(onPressed: _addQuotation, icon: const Icon(Icons.add_shopping_cart), label: const Text('Salvar Cotação do Fornecedor')),
          ),
      ],
    );
  }
  
  List<Widget> _buildPriceFields() {
    return (widget.requestData['items'] as List).map((item) {
      final productId = item['productId'] as String;
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: TextFormField(
          controller: _priceControllers[productId],
          decoration: InputDecoration(labelText: 'Preço Unitário - ${item['productDescription']}'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );
    }).toList();
  }

  Widget _buildQuotationTable() {
    final List<dynamic> requestItems = widget.requestData['items'];
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).collection('quotations').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma cotação adicionada.')));
        final quotations = snapshot.data!.docs;
        final suppliers = quotations.map((doc) => doc.data() as Map<String, dynamic>).toList();
        final Map<String, double> minPrices = {};
        for (var item in requestItems) {
          double currentMin = double.infinity;
          for (var supplier in suppliers) {
            final supplierItem = (supplier['items'] as List).firstWhere((i) => i['productId'] == item['productId'], orElse: () => null);
            if (supplierItem != null) {
              final price = (supplierItem['unitPrice'] as num).toDouble();
              if (price > 0 && price < currentMin) currentMin = price;
            }
          }
          minPrices[item['productId']] = currentMin;
        }
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [const DataColumn(label: Text('Item')), const DataColumn(label: Text('Qtd')), ...suppliers.map((s) => DataColumn(label: Text(s['supplierName'] ?? 'N/A'))), const DataColumn(label: Text('Ações'))],
                rows: [
                  ...requestItems.map((item) => DataRow(cells: [DataCell(Text(item['productDescription'])), DataCell(Text('${item['quantity']} ${item['unit']}')), ...suppliers.map((supplier) { final supplierItem = (supplier['items'] as List).firstWhere((i) => i['productId'] == item['productId'], orElse: () => null); if (supplierItem == null) return const DataCell(Text('-')); final price = (supplierItem['unitPrice'] as num).toDouble(); final isMinPrice = price > 0 && price == minPrices[item['productId']]; return DataCell(Text(_formatCurrency(price), style: TextStyle(color: isMinPrice ? Colors.green : Colors.black, fontWeight: isMinPrice ? FontWeight.bold : FontWeight.normal))); }), const DataCell(Text(''))])),
                  DataRow(cells: [const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))), const DataCell(Text('')), ...suppliers.map((s) => DataCell(Text(_formatCurrency((s['totalPrice'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.bold)))), DataCell(Row(children: suppliers.map((s) => IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: () => _deleteQuotation(s['supplierId']))).toList()))]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (quotations.isNotEmpty) ElevatedButton.icon(icon: const Icon(Icons.analytics_outlined), label: const Text('Analisar Cotações e Criar Pedido'), onPressed: () => _showMixedOrderDialog(suppliers, requestItems), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
          ],
        );
      },
    );
  }

  void _showMixedOrderDialog(List<Map<String, dynamic>> suppliers, List<dynamic> requestItems) {
    final bestBuys = _calculateBestBuys(suppliers, requestItems);
    if (bestBuys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível determinar a melhor opção. Verifique os preços.')));
      return;
    }
    final totalValue = bestBuys.fold<double>(0, (sum, item) => sum + (item['unitPrice'] * item['quantity']));
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Resumo do Pedido Otimizado'), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: [...bestBuys.map((item) => ListTile(title: Text(item['productDescription']), subtitle: Text('Fornecedor: ${item['supplierName']}'), trailing: Text(_formatCurrency(item['unitPrice'] as double)))), const Divider(), Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('Valor Total do Pedido: ${_formatCurrency(totalValue)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))])), actions: [TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(ctx).pop()), ElevatedButton(child: const Text('Confirmar e Criar Pedido'), onPressed: () { _createMixedPurchaseOrder(bestBuys, totalValue); Navigator.of(ctx).pop(); })]));
  }

  List<Map<String, dynamic>> _calculateBestBuys(List<Map<String, dynamic>> suppliers, List<dynamic> requestItems) {
    List<Map<String, dynamic>> bestBuys = [];
    for (var item in requestItems) {
      double minPrice = double.infinity;
      Map<String, dynamic>? bestSupplierOffer;
      for (var supplier in suppliers) {
        final supplierItem = (supplier['items'] as List).firstWhere((i) => i['productId'] == item['productId'], orElse: () => null);
        if (supplierItem != null) {
          final price = (supplierItem['unitPrice'] as num).toDouble();
          if (price > 0 && price < minPrice) {
            minPrice = price;
            bestSupplierOffer = { ...item, 'unitPrice': price, 'supplierId': supplier['supplierId'], 'supplierName': supplier['supplierName'] };
          }
        }
      }
      if (bestSupplierOffer != null) bestBuys.add(bestSupplierOffer);
    }
    return bestBuys;
  }

  void _createMixedPurchaseOrder(List<Map<String, dynamic>> finalItems, double totalValue) {
    final supplierNames = finalItems.map((item) => item['supplierName'] as String?).toSet();
    supplierNames.removeWhere((name) => name == null);
    String finalSupplierName = 'Compra Mista';
    if (supplierNames.length == 1) {
      finalSupplierName = supplierNames.first!;
    }
    FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).update({'status': 'Pedido Criado', 'selectedSupplierName': finalSupplierName, 'totalPrice': totalValue, 'finalItems': finalItems, 'orderCreationDate': Timestamp.now()});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido de compra criado com sucesso!')));
  }

  String _formatCurrency(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);

  void _addQuotation() async {
    if (_selectedSupplierId == null) return;
    final supplierDoc = await FirebaseFirestore.instance.collection('suppliers').doc(_selectedSupplierId).get();
    final supplierName = supplierDoc.data()?['name'] ?? 'N/A';
    final items = widget.requestData['items'] as List;
    List<Map<String, dynamic>> pricedItems = [];
    num totalQuotePrice = 0;
    for (var item in items) {
      final productId = item['productId'] as String;
      final priceText = _priceControllers[productId]!.text.replaceAll(',', '.');
      final unitPrice = double.tryParse(priceText) ?? 0.0;
      if (unitPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preencha um preço válido para ${item['productDescription']}!')));
        return;
      }
      final quantity = item['quantity'] as num;
      totalQuotePrice += unitPrice * quantity;
      pricedItems.add({ ...item, 'unitPrice': unitPrice });
    }
    await FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).collection('quotations').doc(_selectedSupplierId).set({'supplierId': _selectedSupplierId, 'supplierName': supplierName, 'totalPrice': totalQuotePrice, 'items': pricedItems, 'addedAt': Timestamp.now()});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotação salva!')));
  }

  void _deleteQuotation(String quotationId) {
    FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).collection('quotations').doc(quotationId).delete();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotação excluída!')));
  }

  @override
  void dispose() {
    _priceControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }
}
