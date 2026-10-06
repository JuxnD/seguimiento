import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exercise_figure.dart';
import 'exercise_figure_3d.dart';

/// Catálogo de figuras 3D, leído una vez del asset.
final figure3dProvider = FutureProvider<Figure3DCatalog>(
  (ref) async => Figure3DCatalog.fromJsonString(await rootBundle.loadString(Figure3DCatalog.asset)),
);

const _bg = Color(0xFF0B0806);
const _muscle = Color(0xFFF08A34);

/// Alto de cada momento en la hoja de técnica: grande en el teléfono.
const figure3dHeight = 260.0;

class Figure3DPainter extends CustomPainter {
  Figure3DPainter(this.figure, this.progress, {this.yaw, this.pitch});

  final Figure3D figure;
  final double progress;
  final double? yaw, pitch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    paintFigure3D(canvas, size, figure, progress, yaw: yaw, pitch: pitch);
  }

  @override
  bool shouldRepaint(Figure3DPainter oldDelegate) =>
      oldDelegate.figure != figure ||
      oldDelegate.progress != progress ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch;
}

/// Nombre corto de un momento: lo que va antes de los dos puntos del pie.
String momentLabel(Figure3D fig, int i) {
  final c = fig.frames[i].caption;
  final k = c.indexOf(':');
  return k > 0 ? c.substring(0, k) : 'Momento ${i + 1}';
}

/// Posición del recorrido en el segundo `t` de la animación en bucle: va
/// del primer momento al último y vuelve, con una pausa en cada uno.
double loopProgress(double t, int keys, {double hold = 0.6, double move = 1.2}) {
  if (keys < 2) return 0;
  final steps = keys - 1;
  final cycle = hold + 2 * steps * (move + hold);
  var x = t % cycle;
  if (x < hold) return 0;
  x -= hold;
  for (var s = 0; s < 2 * steps; s++) {
    final forward = s < steps;
    final from = forward ? s : 2 * steps - s;
    final to = forward ? s + 1 : 2 * steps - s - 1;
    if (x < move) {
      final u = x / move;
      final e = u < 0.5 ? 4 * u * u * u : 1 - math.pow(-2 * u + 2, 3) / 2;
      return (from + (to - from) * e) / steps;
    }
    x -= move;
    if (x < hold) return to / steps;
    x -= hold;
  }
  return 0;
}

/// Figura de técnica: el maniquí 3D si el ejercicio lo tiene y enseña la
/// variante que pide la sesión; si no, las figuras planas de siempre.
class ExerciseFigureView extends ConsumerWidget {
  const ExerciseFigureView({super.key, required this.exercise, this.grip, this.loaded});

  final String exercise;

  /// Agarre y carga externa que pide la sesión; null = sin contexto. La
  /// dominada 3D es prona con mochila: en supina o sin carga mostrarla
  /// enseñaría otra cosa.
  final String? grip;
  final bool? loaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(figure3dProvider);
    // Mientras carga no se muestra la 2D: evita un parpadeo de figura a figura.
    if (catalog.isLoading && !catalog.hasValue) return const SizedBox.shrink();
    final fig = catalog.valueOrNull?.forExercise(exercise);
    if (fig == null || !fig.matches(grip: grip, loaded: loaded)) return ExerciseArtView(exercise: exercise);
    return Figure3DMoments(figure: fig);
  }
}

/// Tres momentos grandes que se pasan de lado, con su pie. "Ver movimiento"
/// los anima en el mismo cuadro; tocar uno lo abre en grande, donde se
/// puede girar.
class Figure3DMoments extends StatefulWidget {
  const Figure3DMoments({super.key, required this.figure});

  final Figure3D figure;

  @override
  State<Figure3DMoments> createState() => _Figure3DMomentsState();
}

class _Figure3DMomentsState extends State<Figure3DMoments> with SingleTickerProviderStateMixin {
  final _pages = PageController(viewportFraction: 0.94);

  /// Reloj de la animación: solo se usa el tiempo transcurrido.
  late final AnimationController _ticker;
  var _page = 0;
  var _playing = false;

  Figure3D get fig => widget.figure;
  int get _n => fig.frames.length;
  double _keyProgress(int i) => _n < 2 ? 0 : i / (_n - 1);

  /// Punto del recorrido que se ve ahora en la animación.
  double get _loopProgress => loopProgress((_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6, _n);

  String _pageCaption(int i) => '${i + 1}/$_n · ${fig.frames[i].caption}';

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(hours: 1));
  }

  /// Alto del pie más alto con el ancho y la escala de texto reales: con
  /// texto grande el pie ocupa más líneas y el cuadro crece en vez de
  /// desbordar. Se mide en el ancho de una página (el más angosto).
  double _captionHeight(BuildContext context, double width, TextStyle? style) {
    final scaler = MediaQuery.textScalerOf(context);
    final effective = DefaultTextStyle.of(context).style.merge(style);
    var h = 0.0;
    for (var i = 0; i < _n; i++) {
      final painter = TextPainter(
        text: TextSpan(text: _pageCaption(i), style: effective),
        textAlign: TextAlign.center,
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, width * _pages.viewportFraction - 8));
      h = math.max(h, painter.height);
      painter.dispose();
    }
    return h.ceilToDouble() + 2;
  }

  @override
  void dispose() {
    _pages.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _ticker.repeat();
    } else {
      _ticker.stop();
    }
  }

  void _open(double progress) => Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Figure3DFullScreen(figure: fig, initialProgress: progress),
      ));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final captionStyle = text.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    Widget frame(double progress, String caption, Key key) => Semantics(
          image: true,
          label: '${fig.name}: $caption',
          child: Container(
            key: key,
            height: figure3dHeight,
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(painter: Figure3DPainter(fig, progress), size: Size.infinite),
          ),
        );

    final Widget stage;
    if (_playing) {
      stage = AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final p = _loopProgress;
          final key = (p * (_n - 1)).round();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _open(p),
                  child: frame(p, fig.frames[key].caption, const ValueKey('figura3d-animada')),
                ),
                const SizedBox(height: 8),
                Text(fig.frames[key].caption, textAlign: TextAlign.center, style: captionStyle),
              ],
            ),
          );
        },
      );
    } else {
      stage = PageView.builder(
        key: const ValueKey('figura3d-momentos'),
        controller: _pages,
        itemCount: _n,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => _open(_keyProgress(i)),
                child: frame(_keyProgress(i), fig.frames[i].caption, ValueKey('figura3d-$i')),
              ),
              const SizedBox(height: 8),
              Text(_pageCaption(i), textAlign: TextAlign.center, style: captionStyle),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: figure3dHeight + 8 + _captionHeight(context, c.maxWidth, captionStyle),
            child: stage,
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 4),
            if (!_playing)
              for (var i = 0; i < _n; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? scheme.primary : scheme.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            // El botón toma su ancho natural; solo se recorta si no cabe.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _toggle,
                  icon: Icon(_playing ? Icons.pause_circle_outline : Icons.play_circle_outline),
                  label: Text(_playing ? 'Ver momentos' : 'Ver movimiento', overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ampliar y girar',
              icon: const Icon(Icons.open_in_full),
              // Animando, se amplía la pose que se ve, no el inicio.
              onPressed: () => _open(_playing ? _loopProgress : _keyProgress(_page)),
            ),
          ],
        ),
        Row(
          children: [
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: _muscle, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Trabaja: '),
                  TextSpan(text: fig.muscles, style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// La figura en grande: arrastrar la gira (±60°), doble toque o el botón la
/// devuelven a la vista inicial de perfil.
class Figure3DFullScreen extends StatefulWidget {
  const Figure3DFullScreen({super.key, required this.figure, this.initialProgress = 0});

  final Figure3D figure;
  final double initialProgress;

  @override
  State<Figure3DFullScreen> createState() => _Figure3DFullScreenState();
}

class _Figure3DFullScreenState extends State<Figure3DFullScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late double _yaw = widget.figure.initialYaw;
  late double _pitch = widget.figure.initialPitch;
  late double _progress = widget.initialProgress;
  var _playing = false;

  Figure3D get fig => widget.figure;
  int get _n => fig.frames.length;
  bool get _rotated => _yaw != fig.initialYaw || _pitch != fig.initialPitch;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(hours: 1));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _yaw = fig.initialYaw;
        _pitch = fig.initialPitch;
      });

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _ticker.repeat();
    } else {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final key = (_progress * (_n - 1)).round();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(fig.name),
        actions: [
          if (_rotated)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('De perfil'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                key: const ValueKey('figura3d-giro'),
                onPanUpdate: (d) => setState(() {
                  _yaw = (_yaw + d.delta.dx * 0.4).clamp(-maxYaw, maxYaw);
                  _pitch = (_pitch + d.delta.dy * 0.2).clamp(0, 35);
                }),
                onDoubleTap: _reset,
                child: AnimatedBuilder(
                  animation: _ticker,
                  builder: (context, _) {
                    if (_playing) {
                      _progress = loopProgress((_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6, _n);
                    }
                    return Semantics(
                      image: true,
                      label: '${fig.name}: ${fig.frames[(_progress * (_n - 1)).round()].caption}',
                      child: CustomPaint(
                        painter: Figure3DPainter(fig, _progress, yaw: _yaw, pitch: _pitch),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                _playing ? 'En movimiento' : fig.frames[key].caption,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _n; i++)
                    ChoiceChip(
                      label: Text(momentLabel(fig, i)),
                      selected: !_playing && key == i,
                      onSelected: (_) => setState(() {
                        if (_playing) _toggle();
                        _progress = _n < 2 ? 0 : i / (_n - 1);
                      }),
                    ),
                  ActionChip(
                    avatar: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 18),
                    label: Text(_playing ? 'Pausa' : 'Movimiento'),
                    onPressed: _toggle,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Arrastra para girar · doble toque para volver de perfil',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
