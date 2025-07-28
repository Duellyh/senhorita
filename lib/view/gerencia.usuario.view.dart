// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class GerenciarUsuariosView extends StatefulWidget {
  const GerenciarUsuariosView({super.key});

  @override
  State<GerenciarUsuariosView> createState() => _GerenciarUsuariosViewState();
}

class _GerenciarUsuariosViewState extends State<GerenciarUsuariosView> {
  final _formKey = GlobalKey<FormState>();
  final nomeController = TextEditingController();
  final usuarioController = TextEditingController();
  final cpfController = TextEditingController();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  String tipoUsuarioSelecionado = 'funcionario';
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  String? editandoId;

  void _preencherCampos(Map<String, dynamic> usuario, String id) {
    setState(() {
      editandoId = id;
      nomeController.text = usuario['nome'] ?? '';
      usuarioController.text = usuario['nomeUsuario'] ?? '';
      cpfController.text = usuario['cpf'] ?? '';
      emailController.text = usuario['email'] ?? '';
      senhaController.text = '';
      tipoUsuarioSelecionado = usuario['tipo'] ?? 'funcionario';
    });
  }

  @override
  void initState() {
    super.initState();
    _carregarDadosUsuario();
  }

  Future<void> _carregarDadosUsuario() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          nomeUsuario = data['nomeUsuario'] ?? '';
          tipoUsuario = data['tipo'] ?? 'funcionario';
        });
      }
    }
  }

  Future<void> _salvarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    final nomeUsuario = usuarioController.text.trim().toLowerCase();
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    final dados = {
      'nome': nomeController.text.trim(),
      'nomeUsuario': nomeUsuario,
      'cpf': cpfController.text.trim(),
      'email': email,
      'tipo': tipoUsuarioSelecionado, // NOVO
      'dataCadastro': DateTime.now().toIso8601String(),
    };

    final usuariosRef = FirebaseFirestore.instance.collection('usuarios');

    try {
      if (editandoId != null) {
        // Atualizar dados
        await usuariosRef.doc(editandoId).update(dados);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário atualizado com sucesso!')),
        );
      } else {
        // Verifica se nomeUsuario já existe
        final jaExiste = await usuariosRef
            .where('nomeUsuario', isEqualTo: nomeUsuario)
            .limit(1)
            .get();

        if (jaExiste.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nome de usuário já está em uso.')),
          );
          return;
        }

        // Cria o usuário no Firebase Auth
        final credenciais = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: senha);

        await usuariosRef.doc(credenciais.user!.uid).set(dados);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário cadastrado com sucesso!')),
        );
      }

      setState(() {
        editandoId = null;
        nomeController.clear();
        usuarioController.clear();
        cpfController.clear();
        emailController.clear();
        senhaController.clear();
      });
    } on FirebaseAuthException catch (e) {
      String mensagemErro;
      if (e.code == 'email-already-in-use') {
        mensagemErro = 'Este e-mail já está em uso.';
      } else if (e.code == 'invalid-email') {
        mensagemErro = 'E-mail inválido.';
      } else {
        mensagemErro = e.message ?? 'Erro ao cadastrar usuário.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagemErro)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado: ${e.toString()}')),
      );
    }
  }

  Future<void> _excluirUsuario(String id) async {
    await FirebaseFirestore.instance.collection('usuarios').doc(id).delete();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Usuário excluído.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Usuários'),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
      ),
      drawer: Drawer(
        child: Container(
          color: primaryColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: accentColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.store, color: Colors.white, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Olá, ${nomeUsuario.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.dashboard, 'Home', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeView()),
                  );
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const VendasView()),
                );
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ProdutosView()),
                );
              }),
              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdicionarProdutosView(),
                  ),
                );
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ClientesView()),
                );
              }),
              if (tipoUsuario == 'funcionario')
                _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VendasRealizadasView(),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.show_chart, 'Relatórios', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const RelatoriosView()),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracoesView(),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'Informe o nome' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: usuarioController,
                    decoration: const InputDecoration(
                      labelText: 'Nome de Usuário',
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'Informe o nome de usuário' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: cpfController,
                    decoration: const InputDecoration(labelText: 'CPF'),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Informe o CPF' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        value!.isEmpty ? 'Informe o e-mail' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    validator: (value) =>
                        editandoId != null || value!.length >= 6
                        ? null
                        : 'Senha mínima de 6 caracteres',
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: tipoUsuarioSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Usuário',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrador'),
                      ),
                      DropdownMenuItem(
                        value: 'funcionario',
                        child: Text('Funcionário'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        tipoUsuarioSelecionado = value!;
                      });
                    },
                  ),

                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(
                      editandoId != null ? 'Salvar Alterações' : 'Cadastrar',
                    ),
                    onPressed: _salvarUsuario,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const Text(
              'Usuários cadastrados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const CircularProgressIndicator();

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty)
                    return const Text('Nenhum usuário cadastrado.');

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text(data['nome'] ?? 'Sem nome'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email: ${data['email'] ?? ''}'),
                            Text('Login: ${data['nomeUsuario'] ?? ''}'),
                            Text('Tipo: ${data['tipo'] ?? '---'}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _preencherCampos(data, doc.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _excluirUsuario(doc.id),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}
