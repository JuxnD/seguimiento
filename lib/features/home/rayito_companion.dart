import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../ui/mascot.dart';
import 'rayito_state.dart';
import 'readiness_card.dart';

/// Rayito flotante (plan 052): vive abajo a la derecha en las cinco pestañas,
/// animado, y habla en un globo al abrir la app, cuando guardas algo que suma
/// a la racha y cuando lo tocas. Mantenerlo presionado lo esconde; vuelve
/// desde Ajustes. Mientras haces scroll se asoma a medias para no tapar.
/// Lee lo mismo que la tarjeta de Hoy; no guarda nada en la base.
class RayitoCompanion extends ConsumerStatefulWidget {
  const RayitoCompanion({super.key, this.peek = false});

  /// true mientras la pestaña se desplaza: se corre a un lado.
  final bool peek;

  @override
  ConsumerState<RayitoCompanion> createState() => _RayitoCompanionState();
}

class _RayitoCompanionState extends ConsumerState<RayitoCompanion> {
  /// Un saludo por día aunque la pantalla se reconstruya.
  static String? _greetedDay;

  String? _bubble;
  int _hop = 0;
  int _tap = 0;
  Timer? _hide;
  ({String day, int streak, bool active})? _last;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _say(String line) {
    _hide?.cancel();
    setState(() => _bubble = line);
    // En pruebas no queda un temporizador pendiente: el globo se cierra al
    // tocarlo.
    if (rayitoAnimationsEnabled) {
      _hide = Timer(const Duration(seconds: 7), () {
        if (mounted) setState(() => _bubble = null);
      });
    }
  }

  /// Saluda una vez al día y festeja cuando lo guardado suma a la racha.
  void _react(RayitoView rayito) {
    final day = dayKey(rayito.date);
    final now = (day: day, streak: rayito.streak, active: rayito.activeToday);
    final before = _last;
    _last = now;
    if (before == null) {
      if (_greetedDay != day && rayitoAnimationsEnabled) {
        _greetedDay = day;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _say(rayito.message);
        });
      }
      return;
    }
    final summed = before.day == day &&
        (now.active && !before.active || now.streak > before.streak);
    if (!summed) return;
    final levelUp = rayito.streak == rayito.phase.fromDays && rayito.streak > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _hop++);
      _say(levelUp
          ? '¡Subí al nivel ${rayito.phase.level}! ${rayito.days} seguidos.'
          : '¡Sumaste! ${rayito.days} seguidos construyendo tu mejor versión.');
    });
  }

  void _onTap(RayitoView rayito) {
    if (_bubble != null) {
      _hide?.cancel();
      setState(() => _bubble = null);
      return;
    }
    final lines = [
      rayito.message,
      if (rayito.progressLine case final line?) line,
      'Hoy: ${rayito.todayLabel}.',
      rayitoTipFor(rayito.date),
    ];
    setState(() => _hop++);
    _say(lines[_tap++ % lines.length]);
  }

  Future<void> _hideCompanion() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await setRayitoHidden(ref, true);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Rayito se escondió. Vuelve desde Ajustes.'),
        action: SnackBarAction(
            label: 'Deshacer', onPressed: () => setRayitoHidden(ref, false)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider).valueOrNull;
    if (dashboard == null) return const SizedBox.shrink();
    final view = ref
        .watch(
            readinessViewProvider((day: dayKey(dashboard.date), test: false)))
        .valueOrNull;
    final rayito = rayitoView(dashboard, view);
    _react(rayito);
    final text = Theme.of(context).textTheme;
    final bubble = _bubble;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: animation,
                alignment: Alignment.bottomRight,
                child: child),
          ),
          child: bubble == null || widget.peek
              ? const SizedBox.shrink()
              : GestureDetector(
                  key: ValueKey(bubble),
                  onTap: () => _onTap(rayito),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    margin: const EdgeInsets.only(bottom: 6, right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mascotIvory,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                      boxShadow: const [
                        BoxShadow(blurRadius: 10, color: Color(0x66000000))
                      ],
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(bubble,
                          style: text.bodyMedium
                              ?.copyWith(color: mascotCarbon, height: 1.25)),
                    ),
                  ),
                ),
        ),
        AnimatedSlide(
          offset: widget.peek ? const Offset(0.55, 0) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: widget.peek ? 0.6 : 1,
            duration: const Duration(milliseconds: 260),
            child: Semantics(
              button: true,
              label: '${rayito.semanticLabel}. Toca para que te hable; '
                  'mantén presionado para esconderlo.',
              child: GestureDetector(
                onTap: () => _onTap(rayito),
                onLongPress: _hideCompanion,
                child: ExcludeSemantics(
                  child: RayitoAlive(
                    phase: rayito.phase,
                    mood: rayito.mood,
                    size: 64,
                    hop: _hop,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
