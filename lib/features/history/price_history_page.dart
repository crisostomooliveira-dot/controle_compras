import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PriceHistoryPage extends StatefulWidget {
  const PriceHistoryPage({super.key});

  @override
  State<PriceHistoryPage> createState() => _PriceHistoryPageState();
}

class _PriceHistoryPageState extends State<PriceHistoryPage> {
  Map<String, String> _constructionNames = {};
  List<String> _allProducts = [];
  String _currentSearchTerm = '';

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final constructionsFuture = FirebaseFirestore.instance.collection('constructions').get();
    final productsFuture = FirebaseFirestore.instance.collection('products').get();
    final results = await Future.wait([constructionsFuture, productsFuture]);

    final constructionNames = { for (var doc in (results[0] as QuerySnapshot).docs) doc.id : (doc.data() as Map<String, dynamic>)['name'] as String? ?? '' };
    final productNames = (results[1] as QuerySnapshot).docs.map((doc) => (doc.data() as Map<String, dynamic>)['description'] as String).toList();

    if (mounted) {
      setState(() {
        _constructionNames = constructionNames;
        _allProducts = productNames;
      });
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _currentSearchTerm = searchTerm.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.length < 3) return const Iterable<String>.empty();
                return _allProducts.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) => _onSearchChanged(selection),
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _onSearchChanged(value),
                  decoration: const InputDecoration(labelText: 'Buscar por descrição do produto', suffixIcon: Icon(Icons.search)),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('purchase_requests').where('status', isEqualTo: 'Finalizado').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Text('Ocorreu um erro na busca.');
                  if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();
                  
                  final allItems = _extractAndFilterItems(snapshot.data?.docs ?? []);

                  if (allItems.isEmpty) return const Center(child: Text('Nenhum histórico encontrado para este produto.'));
                  
                  return ListView.builder(
                    itemCount: allItems.length,
                    itemBuilder: (context, index) => _buildHistoryCard(allItems[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _extractAndFilterItems(List<QueryDocumentSnapshot> docs) {
    if (_currentSearchTerm.length < 3) return [];

    List<Map<String, dynamic>> filteredItems = [];
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final items = (data['finalItems'] as List<dynamic>?) ?? [];
      
      for (var item in items) {
        if ((item['productDescription'] as String).toLowerCase().contains(_currentSearchTerm)) {
          filteredItems.add({
            ...item,
            'orderDate': (data['orderCreationDate'] as Timestamp?)?.toDate(),
            'constructionId': data['constructionId'],
          });
        }
      }
    }
    return filteredItems;
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final date = item['orderDate'] as DateTime?;
    final formattedDate = date != null ? DateFormat('dd/MM/yyyy').format(date) : '-';
    final constructionName = _constructionNames[item['constructionId']] ?? '-';
    final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(item['productDescription']),
        subtitle: Text('Obra: $constructionName | Data: $formattedDate'),
        trailing: Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(unitPrice)),
      ),
    );
  }
}
