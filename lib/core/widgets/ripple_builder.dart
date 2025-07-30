import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ripple/ripple.dart';

/// Um widget que constrói a si mesmo com base no resultado de uma consulta Ripple
/// e se atualiza automaticamente quando os dados subjacentes mudam.
class RippleBuilder<T> extends StatefulWidget {
  /// A instância principal do Ripple para acessar o stream de reatividade.
  final Ripple ripple;

  /// A função que cria a consulta a ser executada.
  /// Ela será re-executada sempre que os dados relevantes mudarem.
  final QueryBuilder Function() query;

  /// A função que constrói a UI com base no snapshot da consulta.
  final AsyncWidgetBuilder<T> builder;

  /// Dados iniciais a serem usados enquanto a primeira consulta está em andamento.
  final T? initialData;

  /// Define se o widget deve reagir a mudanças no banco de dados.
  /// Padrão: true.
  final bool reactive;

  const RippleBuilder({
    super.key,
    required this.ripple,
    required this.query,
    required this.builder,
    this.initialData,
    this.reactive = true,
  });

  @override
  // ignore: library_private_types_in_public_api
  _RippleBuilderState<T> createState() => _RippleBuilderState<T>();
}

class _RippleBuilderState<T> extends State<RippleBuilder<T>> {
  late AsyncSnapshot<T> _snapshot;
  StreamSubscription? _subscription;

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _snapshot);
  }

  @override
  void didUpdateWidget(RippleBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a consulta mudar, precisamos re-executar e talvez re-inscrever.
    // Uma comparação de SQL é uma forma de verificar se a consulta realmente mudou.
    if (widget.query().toSql() != oldWidget.query().toSql()) {
      _fetchData();
      if (widget.reactive) {
        // Re-inscreve para o caso de a tabela ter mudado.
        _unsubscribe();
        _subscribe();
      }
    }

    // Se a flag 'reactive' mudou
    if (widget.reactive != oldWidget.reactive) {
      if (widget.reactive) {
        _subscribe();
      } else {
        _unsubscribe();
      }
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialData != null
        ? AsyncSnapshot<T>.withData(
            ConnectionState.none,
            widget.initialData as T,
          )
        : AsyncSnapshot<T>.nothing();

    _fetchData();
    if (widget.reactive) {
      _subscribe();
    }
  }

  Future<void> _fetchData() async {
    // Notifica que estamos carregando
    setState(() {
      _snapshot = _snapshot.inState(ConnectionState.waiting);
    });

    try {
      // Executa a consulta
      final result = widget.query() as T;
      // Atualiza o snapshot com os dados
      setState(() {
        _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, result);
      });
    } catch (error, stackTrace) {
      // Atualiza o snapshot com o erro
      setState(() {
        _snapshot = AsyncSnapshot<T>.withError(
          ConnectionState.done,
          error,
          stackTrace,
        );
      });
    }
  }

  void _subscribe() {
    // 1. Garante que não haja inscrições antigas.
    _unsubscribe();

    // 2. Obtém o QueryBuilder e a lista completa de tabelas envolvidas.
    final queryBuilder = widget.query();
    final tablesToListen = queryBuilder.involvedTables;

    // 3. Se houver tabelas para ouvir, cria UMA ÚNICA inscrição.
    if (tablesToListen.isNotEmpty) {
      final driver = widget.ripple.driver;
      _subscription = driver.changeFeed.listen((Set<String> changedTables) {
        // 4. Verifica se QUALQUER uma das tabelas alteradas está na nossa lista de interesse.
        if (mounted && changedTables.any(tablesToListen.contains)) {
          // 5. Se sim, busca os dados novamente.
          _fetchData();
        }
      });
    }
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }
}
