import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../product/product_model.dart';

class EditableRequestItem {
  String productId;
  String productDescription;
  num quantity;
  String unit;
  TextEditingController priceController;
  TextEditingController discountController;
  double finalValue;
  String? supplierId;
  String? supplierName;

  EditableRequestItem({
    required this.productId,
    required this.productDescription,
    required this.quantity,
    required this.unit,
    required double initialPrice,
    required double initialDiscountValue,
    this.supplierId,
    this.supplierName,
  }) : 
    priceController = TextEditingController(text: initialPrice.toStringAsFixed(2)),
    discountController = TextEditingController(text: initialDiscountValue.toStringAsFixed(2)),
    finalValue = (initialPrice * quantity) - initialDiscountValue;

  void calculateFinalValue() {
    final price = double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0.0;
    final discount = double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0.0;
    finalValue = (price * quantity) - discount;
  }
  
  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productDescription': productDescription,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0.0,
      'discountValue': double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0.0,
      'supplierId': supplierId,
      'supplierName': supplierName,
    };
  }
}

class Step3PaymentWidget extends StatefulWidget {
  final String purchaseRequestId;
  final Map<String, dynamic> requestData;

  const Step3PaymentWidget({super.key, required this.purchaseRequestId, required this.requestData});

  @override
  State<Step3PaymentWidget> createState() => _Step3PaymentWidgetState();
}

class _Step3PaymentWidgetState extends State<Step3PaymentWidget> {
  final _formKey = GlobalKey<FormState>();
  final _nfController = TextEditingController();
  final _freightCostController = TextEditingController();

  String? _paymentStatus;
  String? _deliveryStatus;
  DateTime? _expectedDeliveryDate;

  List<EditableRequestItem> _editableItems = [];
  double _itemsSubtotal = 0;
  double _overallTotal = 0;

  @override
  void initState() {
    super.initState();
    _nfController.text = widget.requestData['invoiceNumber'] ?? '';
    _paymentStatus = widget.requestData['paymentStatus'];
    _deliveryStatus = widget.requestData['deliveryStatus'];
    _expectedDeliveryDate = (widget.requestData['expectedDeliveryDate'] as Timestamp?)?.toDate();
    _freightCostController.text = (widget.requestData['freightCost'] as num?)?.toStringAsFixed(2) ?? '0.00';
    
    final itemsData = (widget.requestData['finalItems'] as List<dynamic>?) ?? [];
    _editableItems = itemsData.map((itemData) {
      final item = EditableRequestItem(
        productId: itemData['productId'],
        productDescription: itemData['productDescription'],
        quantity: itemData['quantity'],
        unit: itemData['unit'] ?? '',
        initialPrice: (itemData['unitPrice'] as num).toDouble(),
        initialDiscountValue: (itemData['discountValue'] as num?)?.toDouble() ?? 0.0,
        supplierId: itemData['supplierId'],
        supplierName: itemData['supplierName'],
      );
      item.priceController.addListener(_recalculateTotals);
      item.discountController.addListener(_recalculateTotals);
      return item;
    }).toList();

    _freightCostController.addListener(_recalculateTotals);
    _recalculateTotals();
  }

  void _recalculateTotals() {
    double subtotal = 0;
    for (var item in _editableItems) {
      item.calculateFinalValue();
      subtotal += item.finalValue;
    }
    final freight = double.tryParse(_freightCostController.text.replaceAll(',', '.')) ?? 0.0;
    if (mounted) {
      setState(() {
        _itemsSubtotal = subtotal;
        _overallTotal = subtotal + freight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sequentialId = widget.requestData['sequentialId']?.toString() ?? 'N/A';
    final supplierName = _getSupplierDisplayName();
    final isFinalizado = widget.requestData['status'] == 'Finalizado';

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Pedido Nº: $sequentialId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)), IconButton(icon: const Icon(Icons.copy), onPressed: _copyPurchaseRequest, tooltip: 'Copiar para um Novo Pedido')]),
          const SizedBox(height: 8),
          Text('Fornecedor(es): $supplierName', style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
          const SizedBox(height: 24),
          _buildItemsDataTable(isFinalizado),
          const Divider(height: 24),
          TextFormField(controller: _nfController, readOnly: isFinalizado, decoration: const InputDecoration(labelText: 'Número da Nota Fiscal (NF)')),
          const SizedBox(height: 16),
          _buildExpectedDeliveryDateField(context, isFinalizado),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _paymentStatus, decoration: const InputDecoration(labelText: 'Status do Pagamento'), items: ['Aguardando Aprovação', 'Pendente', 'Pago', 'Atrasado'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: isFinalizado ? null : (v) => setState(() => _paymentStatus = v)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _deliveryStatus, decoration: const InputDecoration(labelText: 'Status da Entrega'), items: ['Aguardando Entrega', 'Entregue', 'Em Trânsito', 'Retirar Material'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: isFinalizado ? null : (v) => setState(() => _deliveryStatus = v)),
          const SizedBox(height: 32),
          if (!isFinalizado) 
            ElevatedButton(onPressed: _updateStatus, child: const Text('Salvar e Atualizar Status')),
          if (isFinalizado)
            Center(child: Chip(label: const Text('PEDIDO FINALIZADO'), backgroundColor: Colors.green.shade100, labelStyle: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }

  String _getSupplierDisplayName() {
    final selectedSupplierName = widget.requestData['selectedSupplierName'];
    if (selectedSupplierName != null && selectedSupplierName.isNotEmpty) {
      return selectedSupplierName;
    }

    if (_editableItems.isEmpty) return 'N/A';
    final supplierNames = _editableItems.map((item) => item.supplierName).toSet();
    supplierNames.removeWhere((name) => name == null || name.isEmpty);
    if (supplierNames.isEmpty) return 'Fornecedor Indefinido';
    if (supplierNames.length == 1) return supplierNames.first!;
    return 'Compra Mista (${supplierNames.length})';
  }

  Widget _buildItemsDataTable(bool isFinalizado) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Itens do Pedido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), if (!isFinalizado) IconButton(icon: const Icon(Icons.add_box), onPressed: _addItem, tooltip: 'Adicionar Item')]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [const DataColumn(label: Text('Descrição')), const DataColumn(label: Text('Qtd')), const DataColumn(label: Text('Valor Unitário')), const DataColumn(label: Text('Desconto (R\$)')), const DataColumn(label: Text('Valor Final')), if (!isFinalizado) const DataColumn(label: Text('Ações'))],
            rows: [
              ..._editableItems.map((item) => DataRow(cells: [
                  DataCell(Text(item.productDescription)), 
                  DataCell(Text('${item.quantity} ${item.unit}')), 
                  DataCell(TextFormField(controller: item.priceController, readOnly: isFinalizado, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  DataCell(TextFormField(controller: item.discountController, readOnly: isFinalizado, keyboardType: const TextInputType.numberWithOptions(decimal: true))), 
                  DataCell(Text(_formatCurrency(item.finalValue))),
                  if (!isFinalizado) DataCell(IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeItem(item))),
              ])),
            ]
          ),
        ),
        const SizedBox(height: 16),
        _buildTotalsSection(isFinalizado),
      ],
    );
  }

  Widget _buildTotalsSection(bool isFinalizado) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Subtotal dos Itens: ${_formatCurrency(_itemsSubtotal)}', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        SizedBox(
          width: 250,
          child: TextFormField(
            controller: _freightCostController,
            readOnly: isFinalizado,
            decoration: const InputDecoration(labelText: 'Frete (R\$)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(height: 8),
        Text('TOTAL DO PEDIDO: ${_formatCurrency(_overallTotal)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildExpectedDeliveryDateField(BuildContext context, bool isFinalizado) {
    return TextFormField(
      readOnly: true,
      decoration: InputDecoration(labelText: 'Data de Entrega Prevista', suffixIcon: const Icon(Icons.calendar_today)),
      controller: TextEditingController(text: _expectedDeliveryDate == null ? '' : DateFormat('dd/MM/yyyy').format(_expectedDeliveryDate!)),
      onTap: isFinalizado ? null : () async {
        final pickedDate = await showDatePicker(context: context, initialDate: _expectedDeliveryDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (pickedDate != null) setState(() => _expectedDeliveryDate = pickedDate);
      },
    );
  }
  
  String _formatCurrency(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ').format(value);

  void _addItem() async {
    final selectedProduct = await _showProductSelectionDialog();
    if (selectedProduct != null) {
      final quantity = await _showQuantityDialog();
      if (quantity != null && quantity > 0) {
        setState(() {
          final newItem = EditableRequestItem(
            productId: selectedProduct.id,
            productDescription: selectedProduct.description,
            quantity: quantity,
            unit: selectedProduct.unit,
            initialPrice: 0.0, // Default price, user can edit
            initialDiscountValue: 0.0,
            supplierId: null, // User might need to define this if it's a mixed order
            supplierName: null,
          );
          newItem.priceController.addListener(_recalculateTotals);
          newItem.discountController.addListener(_recalculateTotals);
          _editableItems.add(newItem);
          _recalculateTotals();
        });
      }
    }
  }

  Future<Product?> _showProductSelectionDialog() async {
    return showDialog<Product>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecione um Produto'),
          content: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('products').orderBy('description').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final products = snapshot.data!.docs.map((doc) => Product.fromFirestore(doc)).toList();
              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      title: Text(product.description),
                      subtitle: Text('Unidade: ${product.unit}'),
                      onTap: () => Navigator.of(context).pop(product),
                    );
                  },
                ),
              );
            },
          ),
          actions: [TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(context).pop())],
        );
      },
    );
  }

  Future<num?> _showQuantityDialog() async {
    final controller = TextEditingController();
    return showDialog<num>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Quantidade'),
          content: TextFormField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Informe a quantidade')),
          actions: [TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(context).pop()), TextButton(child: const Text('Confirmar'), onPressed: () {
              final quantity = num.tryParse(controller.text.replaceAll(',', '.'));
              if (quantity != null && quantity > 0) {
                Navigator.of(context).pop(quantity);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, insira uma quantidade válida.')));
              }
          })],
        );
      },
    );
  }

  void _removeItem(EditableRequestItem item) {
    setState(() {
      _editableItems.remove(item);
      _recalculateTotals();
    });
  }

  void _copyPurchaseRequest() async {
    final newRequestId = FirebaseFirestore.instance.collection('purchase_requests').doc().id;
    final batch = FirebaseFirestore.instance.batch();

    // 1. Get the current highest sequential ID
    final counterRef = FirebaseFirestore.instance.collection('counters').doc('purchase_requests');
    final counterSnapshot = await counterRef.get();
    final newSequentialId = (counterSnapshot.data()?['currentId'] ?? 0) + 1;
    batch.update(counterRef, {'currentId': newSequentialId});

    // 2. Create the new purchase request document
    final newRequestData = {
      ...widget.requestData, // Copy all fields from the original request
      'sequentialId': newSequentialId,
      'status': 'Solicitado', // Reset status
      'createdAt': FieldValue.serverTimestamp(), // New creation date
      // Fields to clear
      'invoiceNumber': null,
      'paymentStatus': null,
      'deliveryStatus': null,
      'expectedDeliveryDate': null,
      'orderCreationDate': null,
      'finalItems': null, // Clear final items, will be re-set from original items
      'totalPrice': 0,
      'subtotal': 0,
      'freightCost': 0,
    };
    final newRequestRef = FirebaseFirestore.instance.collection('purchase_requests').doc(newRequestId);
    batch.set(newRequestRef, newRequestData);

    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido copiado com sucesso! Novo Pedido Nº $newSequentialId')));
    Navigator.of(context).pop(); // Go back to the previous screen
  }

  void _updateStatus() {
    if (_formKey.currentState!.validate()) {
      final isDelivered = _deliveryStatus == 'Entregue';
      final hasInvoice = _nfController.text.isNotEmpty;
      final isPaid = _paymentStatus == 'Pago';

      String currentStatus = widget.requestData['status'];
      String newStatus = currentStatus;

      if (currentStatus != 'Finalizado') {
        if (isDelivered && hasInvoice && isPaid) {
          newStatus = 'Finalizado';
        } else {
          newStatus = 'Pedido Criado';
        }
      }

      FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).update({
        'invoiceNumber': _nfController.text,
        'paymentStatus': _paymentStatus,
        'deliveryStatus': _deliveryStatus,
        'expectedDeliveryDate': _expectedDeliveryDate != null ? Timestamp.fromDate(_expectedDeliveryDate!) : null,
        'finalItems': _editableItems.map((item) => item.toMap()).toList(),
        'subtotal': _itemsSubtotal,
        'freightCost': double.tryParse(_freightCostController.text.replaceAll(',', '.')) ?? 0.0,
        'totalPrice': _overallTotal,
        'status': newStatus,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informações da compra atualizadas!')));
    }
  }

  @override
  void dispose() {
    _nfController.dispose();
    _freightCostController.dispose();
    for (var item in _editableItems) {
      item.priceController.dispose();
      item.discountController.dispose();
    }
    super.dispose();
  }
}
