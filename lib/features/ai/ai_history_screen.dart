import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import 'ai_conversation_screen.dart';

class AiHistoryScreen extends ConsumerStatefulWidget {
  const AiHistoryScreen({super.key});

  @override
  ConsumerState<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends ConsumerState<AiHistoryScreen> {
  int _page = 0;
  static const _pageSize = 100;

  Future<void> _delete(AiConversationRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar esta conversación'),
        content: Text(
            'Se eliminarán sus ${row.kind == 'weeklyAnalysis' ? 'comentarios' : 'preguntas y respuestas'} y el contexto guardado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(aiConversationRepositoryProvider).delete(row.id);
    ref.invalidate(aiConversationsProvider(((_page + 1) * _pageSize, 0)));
  }

  @override
  Widget build(BuildContext context) {
    final limit = (_page + 1) * _pageSize;
    final conversations = ref.watch(aiConversationsProvider((limit, 0)));
    final count = ref.watch(aiConversationCountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de IA')),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('No se pudo leer el historial local.')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Las respuestas verificadas aparecerán aquí. No se guarda una consulta cancelada o fallida.'),
              ),
            );
          }
          final total = count.valueOrNull;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                    '${rows.length}${total == null ? '' : ' de $total'} conversaciones guardadas en este teléfono'),
              ),
              for (final row in rows)
                ListTile(
                  title: Text(row.title),
                  subtitle: Text([
                    _kindLabel(row.kind),
                    if (row.rangeStart != null && row.rangeEnd != null)
                      '${formatShort(parseDay(row.rangeStart!))} – ${formatShort(parseDay(row.rangeEnd!))}',
                    DateTime.fromMillisecondsSinceEpoch(row.createdAt,
                            isUtc: true)
                        .toLocal()
                        .toString()
                        .substring(0, 16),
                  ].join(' · ')),
                  trailing: IconButton(
                    tooltip: 'Borrar conversación',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(row),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AiConversationScreen.forConversation(
                        repository: ref.read(aiConversationRepositoryProvider),
                        conversationId: row.id,
                      ),
                    ),
                  ),
                ),
              if (total != null && rows.length < total)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: () => setState(() => _page++),
                    child: const Text('Cargar conversaciones anteriores'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'weeklyAnalysis' => 'Análisis semanal',
        'exerciseQuestion' => 'Guía de ejercicio',
        _ => 'Pregunta sobre informe',
      };
}
