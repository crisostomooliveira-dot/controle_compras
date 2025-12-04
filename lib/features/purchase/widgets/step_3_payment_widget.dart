import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EditableRequestItem {
  String productId;
  String productDescription;
  num quantity;
  TextEditingController priceController;
  TextEditingController discountController;
  double finalValue;

  EditableRequestItem({
    required this.productId,
    required this.productDescription,
    required this.quantity,
    required double initialPrice,
    required double initialDiscountValue,
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
      'unitPrice': double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0.0,
      'discountValue': double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0.0,
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
  String? _paymentStatus;
  String? _deliveryStatus;
  DateTime? _expectedDeliveryDate;

  List<EditableRequestItem> _editableItems = [];
  double _overallTotal = 0;

  @override
  void initState() {
    super.initState();
    _nfController.text = widget.requestData['invoiceNumber'] ?? '';
    _paymentStatus = widget.requestData['paymentStatus'];
    _deliveryStatus = widget.requestData['deliveryStatus'];
    _expectedDeliveryDate = (widget.requestData['expectedDeliveryDate'] as Timestamp?)?.toDate();
    
    final itemsData = (widget.requestData['finalItems'] as List<dynamic>?) ?? [];
    _editableItems = itemsData.map((itemData) {
      final item = EditableRequestItem(
        productId: itemData['productId'],
        productDescription: itemData['productDescription'],
        quantity: itemData['quantity'],
        initialPrice: (itemData['unitPrice'] as num).toDouble(),
        initialDiscountValue: (itemData['discountValue'] as num?)?.toDouble() ?? 0.0,
      );
      item.priceController.addListener(_recalculateOverallTotal);
      item.discountController.addListener(_recalculateOverallTotal);
      return item;
    }).toList();

    _recalculateOverallTotal();
  }

  void _recalculateOverallTotal() {
    double total = 0;
    for (var item in _editableItems) {
      item.calculateFinalValue();
      total += item.finalValue;
    }
    if (mounted) {
      setState(() {
        _overallTotal = total;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sequentialId = widget.requestData['sequentialId']?.toString() ?? 'N/A';
    final supplierName = _getSupplierDisplayName();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Pedido Nº: $sequentialId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Fornecedor(es): $supplierName', style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
          const SizedBox(height: 24),
          _buildItemsDataTable(),
          const Divider(height: 24),
          TextFormField(controller: _nfController, decoration: const InputDecoration(labelText: 'Número da Nota Fiscal (NF)')),
          const SizedBox(height: 16),
          _buildExpectedDeliveryDateField(context),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _paymentStatus, decoration: const InputDecoration(labelText: 'Status do Pagamento'), items: ['Aguardando Aprovação', 'Pendente', 'Pago', 'Atrasado'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _paymentStatus = v)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _deliveryStatus, decoration: const InputDecoration(labelText: 'Status da Entrega'), items: ['Aguardando Entrega', 'Entregue', 'Em Trânsito', 'Retirar Material'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _deliveryStatus = v)),
          const SizedBox(height: 32),
          ElevatedButton(onPressed: _updateStatus, child: const Text('Salvar e Atualizar Status')),
        ],
      ),
    );
  }

  String _getSupplierDisplayName() {
    final legacySupplierName = widget.requestData['selectedSupplierName'];
    if (legacySupplierName != null) return legacySupplierName;

    final items = widget.requestData['finalItems'] as List<dynamic>?;
    if (items == null || items.isEmpty) return 'N/A';
    
    final supplierNames = items.map((item) => item['supplierName'] as String?).toSet();
    supplierNames.removeWhere((name) => name == null);

    if (supplierNames.isEmpty) return 'N/A';
    if (supplierNames.length == 1) return supplierNames.first!;
    return 'Compra Mista (${supplierNames.length})';
  }

  Widget _buildItemsDataTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Itens do Pedido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [DataColumn(label: Text('Descrição')), DataColumn(label: Text('Qtd')), DataColumn(label: Text('Valor Unitário')), DataColumn(label: Text('Desconto (R\$)')), DataColumn(label: Text('Valor Final'))],
            rows: [
              ..._editableItems.map((item) => DataRow(cells: [DataCell(Text(item.productDescription)), DataCell(Text(item.quantity.toString())), DataCell(TextFormField(controller: item.priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true))), DataCell(TextFormField(controller: item.discountController, keyboardType: const TextInputType.numberWithOptions(decimal: true))), DataCell(Text(_formatCurrency(item.finalValue)))])),
              DataRow(cells: [const DataCell(Text('')), const DataCell(Text('')), const DataCell(Text('')), const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))), DataCell(Text(_formatCurrency(_overallTotal), style: const TextStyle(fontWeight: FontWeight.bold)))])
            ]
          ),
        ),
      ],
    );
  }

  Widget _buildExpectedDeliveryDateField(BuildContext context) {
    return TextFormField(
      readOnly: true,
      decoration: InputDecoration(labelText: 'Data de Entrega Prevista', suffixIcon: const Icon(Icons.calendar_today)),
      controller: TextEditingController(text: _expectedDeliveryDate == null ? '' : DateFormat('dd/MM/yyyy').format(_expectedDeliveryDate!)),
      onTap: () async {
        final pickedDate = await showDatePicker(context: context, initialDate: _expectedDeliveryDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (pickedDate != null) setState(() => _expectedDeliveryDate = pickedDate);
      },
    );
  }
  
  String _formatCurrency(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);

  void _updateStatus() {
    if (_formKey.currentState!.validate()) {
      bool isDelivered = _deliveryStatus == 'Entregue';
      bool hasInvoice = _nfController.text.isNotEmpty;
      String newStatus = (isDelivered && hasInvoice) ? 'Finalizado' : 'Pedido Criado';
      FirebaseFirestore.instance.collection('purchase_requests').doc(widget.purchaseRequestId).update({
        'invoiceNumber': _nfController.text,
        'paymentStatus': _paymentStatus,
        'deliveryStatus': _deliveryStatus,
        'expectedDeliveryDate': _expectedDeliveryDate != null ? Timestamp.fromDate(_expectedDeliveryDate!) : null,
        'finalItems': _editableItems.map((item) => item.toMap()).toList(),
        'finalValue': _overallTotal,
        'status': newStatus,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informações da compra atualizadas!')));
    }
  }

  @override
  void dispose() {
    _nfController.dispose();
    for (var item in _editableItems) {
      item.priceController.dispose();
      item.discountController.dispose();
    }
    super.dispose();
  }
}
