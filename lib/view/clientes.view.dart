import 'package:flutter/material.dart';

class ClientesView extends StatefulWidget {
  const ClientesView({super.key});

  @override
  State<ClientesView> createState() => _ClientesViewState();
}

class _ClientesViewState extends State<ClientesView> {
  final List<Map<String, String>> clientes = [
    {'nome': 'João da Silva', 'telefone': '(11) 99999-1234'},
    {'nome': 'Maria Oliveira', 'telefone': '(21) 98888-4321'},
    {'nome': 'Carlos Souza', 'telefone': '(31) 97777-5555'},
  ];

  void _adicionarCliente() {
    showDialog(
      context: context,
      builder: (context) {
        final nomeController = TextEditingController();
        final telefoneController = TextEditingController();
        return AlertDialog(
          title: const Text('Adicionar Cliente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: telefoneController,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nomeController.text.isNotEmpty && telefoneController.text.isNotEmpty) {
                  setState(() {
                    clientes.add({
                      'nome': nomeController.text,
                      'telefone': telefoneController.text,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 196, 50, 99),
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: clientes.length,
        itemBuilder: (context, index) {
          final cliente = clientes[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.person, color: Color.fromARGB(255, 194, 131, 178)),
              title: Text(cliente['nome'] ?? ''),
              subtitle: Text(cliente['telefone'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  setState(() {
                    clientes.removeAt(index);
                  });
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarCliente,
        icon: const Icon(Icons.person_add),
        label: const Text('Adicionar'),
        backgroundColor: const Color.fromARGB(255, 196, 50, 99),
        foregroundColor: Colors.white,
      ),
    );
  }
}
