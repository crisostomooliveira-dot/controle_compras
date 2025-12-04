import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_compras/features/product/product_model.dart';
import 'package:controle_compras/features/purchase/purchase_detail_page.dart';
import 'package:controle_compras/features/purchase/request_item_model.dart';
import 'package:flutter/material.dart';

class PurchaseRequestPage extends StatefulWidget {
  const PurchaseRequestPage({super.key});

  @override
  State<PurchaseRequestPage> createState() => _PurchaseRequestPageState();
}

class _PurchaseRequestPageState extends State<PurchaseRequestPage> {
  final _headerFormKey = GlobalKey<FormState>();
  String? _selectedConstructionId;
  String? _selectedCostCenterId;

  final _itemFormKey = GlobalKey<FormState>();
  Product? _selectedProduct;
  final _quantityController = TextEditingController();
  
  final List<RequestItem> _requestItems = [];
  List<Product> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _fetchAllProducts();
  }

  Future<void> _fetchAllProducts() async {
    final snapshot = await FirebaseFirestore.instance.collection('products').orderBy('description').get();
    if (mounted) {
      setState(() {
        _allProducts = snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Solicitação de Compra'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildRequestHeader(),
            const Divider(height: 30),
            _buildAddItemForm(),
            const Divider(height: 30),
            const Text('Itens da Solicitação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildItemsTable(),
            const Spacer(),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestHeader() {
    return Form(
      key: _headerFormKey,
      child: Row(
        children: [
          Expanded(child: _buildDropdown('constructions', 'Obra', (val) => setState(() => _selectedConstructionId = val))),
          const SizedBox(width: 16),
          Expanded(child: _buildDropdown('cost_centers', 'Centro de Custo', (val) => setState(() => _selectedCostCenterId = val))),
        ],
      ),
    );
  }

  Widget _buildAddItemForm() {
    return Form(
      key: _itemFormKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Autocomplete<Product>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.length < 3) return const Iterable<Product>.empty();
                return _allProducts.where((Product option) {
                  return option.description.toLowerCase().contains(textEditingValue.text.toLowerCase());
                });
              },
              displayStringForOption: (Product option) => option.description,
              onSelected: (Product selection) {
                setState(() => _selectedProduct = selection);
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Produto (mín. 3 letras)'),
                  validator: (value) => (_selectedProduct == null && value!.isNotEmpty) ? 'Selecione um item da lista' : null,
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1, 
            child: TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Req.';
                final value = num.tryParse(v.replaceAll('.', '').replaceAll(',', '.'));
                if (value == null || value <= 0) return 'Inválido';
                return null;
              },
            )
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Adicionar')),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTable() {
    return Expanded(
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [DataColumn(label: Text('Produto')), DataColumn(label: Text('Qtd')), DataColumn(label: Text('Unidade')), DataColumn(label: Text('Ação'))],
          rows: _requestItems.map((item) => DataRow(cells: [DataCell(Text(item.productDescription)), DataCell(Text(item.quantity.toString())), DataCell(Text(item.unit)), DataCell(IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() => _requestItems.remove(item))))])).toList(),
        ),
      ),
    );
  }

  Widget _buildDropdown(String collection, String label, ValueChanged<String?> onChanged) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var items = snapshot.data!.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text((doc.data() as Map<String, dynamic>)['name'] ?? 'N/A'))).toList();
        return DropdownButtonFormField<String>(decoration: InputDecoration(labelText: label), items: items, onChanged: onChanged, validator: (v) => v == null ? 'Selecione' : null);
      },
    );
  }

  void _addItem() {
    if (_itemFormKey.currentState!.validate() && _selectedProduct != null) {
      final String quantityText = _quantityController.text;
      final num? quantity = num.tryParse(quantityText.replaceAll('.', '').replaceAll(',', '.'));

      if (quantity == null || quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, insira uma quantidade válida.')));
        return;
      }

      final newItem = RequestItem(productId: _selectedProduct!.id, productDescription: _selectedProduct!.description, quantity: quantity, unit: _selectedProduct!.unit);
      setState(() => _requestItems.add(newItem));

      _itemFormKey.currentState!.reset();
      _quantityController.clear();
      setState(() => _selectedProduct = null);
    }
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(onPressed: _requestItems.isEmpty ? null : _saveRequest, child: const Text('Salvar e Ir para Cotação'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16))),
    );
  }

  void _saveRequest() async {
    if (!_headerFormKey.currentState!.validate() || _requestItems.isEmpty) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final counterRef = firestore.collection('counters').doc('purchase_requests');

      final newRequestDoc = await firestore.runTransaction((transaction) async {
        final counterSnapshot = await transaction.get(counterRef);
        int newRequestNumber = 1;
        if (counterSnapshot.exists) {
          newRequestNumber = (counterSnapshot.data()!['lastNumber'] as num).toInt() + 1;
        } else {
          transaction.set(counterRef, {'lastNumber': 1});
        }

        final itemsAsMaps = _requestItems.map((item) => item.toMap()).toList();
        final newRequestRef = firestore.collection('purchase_requests').doc();

        transaction.set(newRequestRef, {
          'sequentialId': newRequestNumber,
          'constructionId': _selectedConstructionId,
          'costCenterId': _selectedCostCenterId,
          'items': itemsAsMaps,
          'requestDate': Timestamp.now(),
          'status': 'Solicitado',
        });

        transaction.update(counterRef, {'lastNumber': newRequestNumber});
        return newRequestRef;
      });

      final newRequestData = await newRequestDoc.get();
      final newSequentialId = newRequestData.data()?['sequentialId'];

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Solicitação Nº $newSequentialId criada! Redirecionando...')));

      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => PurchaseDetailPage(purchaseRequestId: newRequestDoc.id)));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar solicitação: $e')));
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }
}
