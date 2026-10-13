import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exercise_figure_3d.dart';

/// Catálogo de figuras 3D, leído una vez del asset.
final figure3dProvider = FutureProvider<Figure3DCatalog>(
  (ref) async => Figure3DCatalog.fromJsonString(await rootBundle.loadString(Figure3DCatalog.asset)),
);

const _bg = Color(0xFF0B0806);
const _muscle = Color(0xFFF08A34);

/// Alto de cada momento en la hoja de técnica: grande en el teléfono.
const figure3dHeight = 330.0;

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
double loopProgress(double t, int keys, {double hold = 0.6, double move = 2.4}) {
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

/// Forward-only authored stages; legacy figures keep their existing loop.
double figureMotionProgress(Figure3D figure, double seconds) {
  if (!figure.hasMotion) return loopProgress(seconds, figure.frames.length);
  final total = figure.motion.fold<double>(0, (sum, stage) => sum + stage.seconds);
  var remaining = seconds % total;
  for (var i = 0; i < figure.motion.length; i++) {
    final stage = figure.motion[i];
    if (remaining < stage.seconds) {
      final t = remaining / stage.seconds;
      // Progress still advances through holds/cuts so stage selection and
      // the timeline stay consistent; skeletonAt owns their interpolation.
      final eased = stage.kind == 'interpolate' ? t * t * (3 - 2 * t) : t;
      return (i + eased) / figure.motion.length;
    }
    remaining -= stage.seconds;
  }
  return 0;
}

double figureMotionTime(Figure3D figure, double progress) {
  if (figure.frames.length < 2) return 0;
  if (!figure.hasMotion) {
    final x = progress.clamp(0, 1) * (figure.frames.length - 1);
    final index = math.min(x.floor(), figure.frames.length - 2);
    final fraction = x - index;
    final u =
        fraction < .5 ? math.pow(fraction / 4, 1 / 3).toDouble() : 1 - math.pow((1 - fraction) / 4, 1 / 3).toDouble();
    return .6 + index * 3 + u * 2.4;
  }
  final x = progress.clamp(0, 1) * figure.motion.length;
  final index = math.min(x.floor(), figure.motion.length - 1);
  var fraction = x - index;
  if (figure.motion[index].kind == 'interpolate') {
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (mid * mid * (3 - 2 * mid) < fraction) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    fraction = (lo + hi) / 2;
  }
  return figure.motion.take(index).fold<double>(0, (sum, stage) => sum + stage.seconds) +
      fraction * figure.motion[index].seconds;
}

String figureMotionCaption(Figure3D figure, double progress) {
  final stage = figure.stageAt(progress);
  if (stage != null) {
    return '${stage.part.isEmpty ? '' : 'Parte ${stage.part} · '}${stage.label}';
  }
  return figure.frames[(progress * (figure.frames.length - 1)).round()].caption;
}

/// A part is bounded by its own authored stages. The intervening cut belongs
/// to navigation, never to playback of the selected exercise.
class FigureMotionPart {
  const FigureMotionPart(this.label, this.start, this.end, this.startTime, this.endTime);
  final String label;
  final double start, end, startTime, endTime;

  double progressAt(Figure3D figure, double time) => time <= startTime
      ? start
      : figureMotionProgress(figure, time.clamp(startTime, endTime - 1e-7));
}

List<FigureMotionPart> figureMotionParts(Figure3D figure) {
  final parts = <FigureMotionPart>[];
  var time = 0.0;
  for (var i = 0; i < figure.motion.length;) {
    final stage = figure.motion[i];
    if (stage.part.isEmpty || stage.kind == 'cut') {
      time += stage.seconds;
      i++;
      continue;
    }
    final first = i;
    final startTime = time;
    while (i < figure.motion.length && figure.motion[i].part == stage.part && figure.motion[i].kind != 'cut') {
      time += figure.motion[i].seconds;
      i++;
    }
    final label = figure.frames[first].caption.split(' · ').first;
    parts.add(FigureMotionPart(label, first / figure.motion.length, i / figure.motion.length, startTime, time));
  }
  return parts;
}

class _FigurePartControls extends StatelessWidget {
  const _FigurePartControls({required this.parts, required this.selected, required this.onSelected});
  final List<FigureMotionPart> parts;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(liveRegion: true,
            child: Text('Parte ${selected + 1} de ${parts.length}', textAlign: TextAlign.center)),
          Semantics(
            label: 'Seleccionar parte del calentamiento',
            child: DropdownButton<int>(
              isExpanded: true,
              itemHeight: null,
              value: selected,
              items: [
                for (var i = 0; i < parts.length; i++)
                  DropdownMenuItem(value: i, child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8), child: Text(parts[i].label))),
              ],
              onChanged: (index) {
                if (index != null) { onSelected(index); }
              },
            ),
          ),
          TextButton.icon(
            onPressed: selected + 1 < parts.length ? () => onSelected(selected + 1) : null,
            icon: const Icon(Icons.skip_next),
            label: const Text('Siguiente parte'),
          ),
        ]),
      );
}

/// Figura de técnica: el maniquí 3D si el ejercicio lo tiene y enseña la
/// variante que pide la sesión; si no, las figuras planas de siempre.
class ExerciseFigureView extends ConsumerWidget {
  const ExerciseFigureView({super.key, required this.exercise, this.grip, this.loaded, this.side});

  final String exercise;

  /// Agarre y carga externa que pide la sesión; null = sin contexto. La
  /// dominada 3D es prona con mochila: en supina o sin carga mostrarla
  /// enseñaría otra cosa.
  final String? grip;
  final bool? loaded;
  final String? side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(figure3dProvider);
    // Mientras carga no se muestra la 2D: evita un parpadeo de figura a figura.
    if (catalog.isLoading && !catalog.hasValue) return const SizedBox.shrink();
    if (catalog.hasError) {
      return Column(children: [
        const Text('No se pudo cargar la ilustración.'),
        TextButton(onPressed: () => ref.invalidate(figure3dProvider), child: const Text('Reintentar')),
      ]);
    }
    final fig = catalog.valueOrNull?.forExercise(exercise, grip: grip, loaded: loaded, side: side);
    if (fig == null) {
      return const Text('Este ejercicio todavía no tiene una ilustración. Puedes añadir una foto de referencia.');
    }
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

class _Figure3DMomentsState extends State<Figure3DMoments> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _pages = PageController(viewportFraction: 0.94);

  /// Reloj de la animación: solo se usa el tiempo transcurrido.
  late final AnimationController _ticker;
  var _page = 0;
  var _playing = false;
  var _showingMotion = false;
  double _time = 0;
  int _partIndex = 0;
  ScrollPosition? _scrollPosition;

  void _checkVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_playing || !mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      if (!bounds.overlaps(Offset.zero & MediaQuery.sizeOf(context))) _toggle();
    });
  }

  Figure3D get fig => widget.figure;
  int get _n => fig.frames.length;
  double _keyProgress(int i) => _n < 2 ? 0 : i / (_n - 1);

  /// Punto del recorrido que se ve ahora en la animación.
  double get _clock => _time + (_playing ? (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6 : 0);
  double get _loopProgress {
    final parts = figureMotionParts(fig);
    return parts.isEmpty ? figureMotionProgress(fig, _clock) : parts[_partIndex].progressAt(fig, _clock);
  }

  void _stopAtPartEnd() {
    final parts = figureMotionParts(fig);
    if (_playing && parts.isNotEmpty && _clock >= parts[_partIndex].endTime) {
      _ticker.stop();
      setState(() { _time = parts[_partIndex].endTime; _playing = false; });
    }
  }

  void _selectPart(int index) {
    _ticker.stop();
    setState(() {
      _playing = false;
      _showingMotion = true;
      _partIndex = index;
      _time = figureMotionParts(fig)[index].startTime;
    });
  }

  String _pageCaption(int i) => '${i + 1}/$_n · ${fig.frames[i].caption}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = AnimationController(vsync: this, duration: const Duration(hours: 1));
    _ticker.addListener(_stopAtPartEnd);
  }

  @override
  void didUpdateWidget(covariant Figure3DMoments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figure != fig) {
      _ticker.stop();
      _playing = false;
      _showingMotion = false;
      _page = 0;
      _time = 0;
      _partIndex = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_checkVisibility);
      _scrollPosition = position;
      position?.addListener(_checkVisibility);
    }
    if ((MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) && _playing) {
      _time += (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
      _ticker.stop();
      _playing = false;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_checkVisibility);
    _pages.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!fig.continuous || MediaQuery.disableAnimationsOf(context)) return;
    if (_playing) {
      _time += (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    } else {
      final parts = figureMotionParts(fig);
      if (parts.isNotEmpty && _time >= parts[_partIndex].endTime) {
        _time = parts[_partIndex].startTime;
      }
    }
    setState(() {
      _playing = !_playing;
      _showingMotion = true;
    });
    if (_playing) {
      _ticker.forward(from: 0);
    } else {
      _ticker.stop();
    }
  }

  void _showMoments() {
    final progress = _loopProgress;
    if (_playing) {
      _time += (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    }
    _ticker.stop();
    setState(() {
      _playing = false;
      _showingMotion = false;
      _page = (progress * (_n - 1)).round();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(_page);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _toggle();
  }

  void _open(double progress) {
    if (_playing) _toggle();
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Figure3DFullScreen(figure: fig, initialProgress: progress),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final parts = figureMotionParts(fig);
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
    if (_showingMotion || parts.isNotEmpty) {
      stage = AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final p = _loopProgress;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _open(p),
                  child: frame(p, figureMotionCaption(fig, p), const ValueKey('figura3d-animada')),
                ),
                const SizedBox(height: 8),
                Text(figureMotionCaption(fig, p), textAlign: TextAlign.center, style: captionStyle),
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
        onPageChanged: (i) => setState(() {
          _page = i;
          _time = figureMotionTime(fig, _keyProgress(i));
        }),
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
        if (parts.isNotEmpty) _FigurePartControls(parts: parts, selected: _partIndex, onSelected: _selectPart),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!_showingMotion && parts.isEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (_n > 7) Text('${_page + 1}/$_n'),
                for (var i = 0; i < (_n > 7 ? 0 : _n); i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? scheme.primary : scheme.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
              ]),
            // Reflow preserves the full action label with large text.
            if (fig.continuous && parts.isEmpty)
              TextButton.icon(
                onPressed: _showingMotion
                    ? _showMoments
                    : MediaQuery.disableAnimationsOf(context)
                        ? null
                        : _toggle,
                icon: Icon(_showingMotion ? Icons.view_carousel_outlined : Icons.play_circle_outline),
                label:
                    Text(_showingMotion ? 'Ver momentos' : 'Ver movimiento', maxLines: 2, textAlign: TextAlign.center),
              ),
            if (_showingMotion || parts.isNotEmpty)
              TextButton.icon(
                  onPressed: MediaQuery.disableAnimationsOf(context) ? null : _toggle,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  label: Text(_playing ? 'Pausa' : parts.isNotEmpty ? 'Movimiento' : 'Continuar')),
            IconButton(
              tooltip: 'Ampliar y girar',
              icon: const Icon(Icons.open_in_full),
              // Animando, se amplía la pose que se ve, no el inicio.
              onPressed: () => _open(_showingMotion || parts.isNotEmpty ? _loopProgress : _keyProgress(_page)),
            ),
          ],
        ),
        if (fig.muscles.isNotEmpty)
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
        if (fig.annotations.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(fig.annotations.map((a) => a['text'] as String).join(' · '))),
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

class _Figure3DFullScreenState extends State<Figure3DFullScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ticker;
  late double _yaw = widget.figure.initialYaw;
  late double _pitch = widget.figure.initialPitch;
  late double _progress = widget.initialProgress;
  var _playing = false;
  late double _time = figureMotionTime(widget.figure, widget.initialProgress);
  int _partIndex = 0;

  Figure3D get fig => widget.figure;
  int get _n => fig.frames.length;
  bool get _rotated => _yaw != fig.initialYaw || _pitch != fig.initialPitch;
  double get _clock => _time + (_playing ? (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6 : 0);

  void _stopAtPartEnd() {
    final parts = figureMotionParts(fig);
    if (_playing && parts.isNotEmpty && _clock >= parts[_partIndex].endTime) {
      _ticker.stop();
      setState(() {
        _time = parts[_partIndex].endTime;
        _progress = parts[_partIndex].progressAt(fig, _time);
        _playing = false;
      });
    }
  }

  void _selectPart(int index) {
    _ticker.stop();
    setState(() {
      _playing = false;
      _partIndex = index;
      final part = figureMotionParts(fig)[index];
      _progress = part.start;
      _time = part.startTime;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = AnimationController(vsync: this, duration: const Duration(hours: 1));
    _ticker.addListener(_stopAtPartEnd);
    final parts = figureMotionParts(fig);
    if (parts.isNotEmpty) {
      _partIndex = math.max(0, parts.indexWhere((part) => _progress >= part.start && _progress < part.end));
    }
  }

  @override
  void didUpdateWidget(covariant Figure3DFullScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figure != fig) {
      _ticker.stop();
      _playing = false;
      _yaw = fig.initialYaw;
      _pitch = fig.initialPitch;
      _progress = widget.initialProgress;
      _time = figureMotionTime(fig, _progress);
      final parts = figureMotionParts(fig);
      _partIndex = parts.isEmpty ? 0 : math.max(0, parts.indexWhere((part) => _progress >= part.start && _progress < part.end));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) && _playing) {
      _time += (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
      _ticker.stop();
      _playing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _yaw = fig.initialYaw;
        _pitch = fig.initialPitch;
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _toggle();
  }

  void _toggle() {
    if (!fig.continuous || MediaQuery.disableAnimationsOf(context)) return;
    if (_playing) {
      _time += (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    } else {
      final parts = figureMotionParts(fig);
      if (parts.isNotEmpty && _time >= parts[_partIndex].endTime) {
        _time = parts[_partIndex].startTime;
        _progress = parts[_partIndex].start;
      }
    }
    setState(() => _playing = !_playing);
    if (_playing) {
      _ticker.forward(from: 0);
    } else {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final parts = figureMotionParts(fig);
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
              label: const Text('Restablecer vista'),
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
                  _pitch = (_pitch + d.delta.dy * 0.2).clamp(0, 85);
                }),
                onDoubleTap: _reset,
                child: AnimatedBuilder(
                  animation: _ticker,
                  builder: (context, _) {
                    if (_playing) {
                      _progress = parts.isEmpty
                          ? figureMotionProgress(fig, _clock)
                          : parts[_partIndex].progressAt(fig, _clock);
                    }
                    return Semantics(
                      image: true,
                      label: '${fig.name}: ${figureMotionCaption(fig, _progress)}',
                      child: CustomPaint(
                        painter: Figure3DPainter(fig, _progress, yaw: _yaw, pitch: _pitch),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.min(350, MediaQuery.sizeOf(context).height * .4)),
              child: SingleChildScrollView(
                  child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: AnimatedBuilder(
                      animation: _ticker,
                      builder: (context, _) => Text(
                            _playing || fig.hasMotion ? figureMotionCaption(fig, _progress) : fig.frames[key].caption,
                            textAlign: TextAlign.center,
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          )),
                ),
                if (parts.isNotEmpty)
                  _FigurePartControls(parts: parts, selected: _partIndex, onSelected: _selectPart),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < (parts.isEmpty ? _n : 0); i++)
                        ChoiceChip(
                          label: Text(momentLabel(fig, i)),
                          selected: !_playing && key == i,
                          onSelected: (_) => setState(() {
                            if (_playing) _toggle();
                            _progress = _n < 2 ? 0 : i / (_n - 1);
                            _time = figureMotionTime(fig, _progress);
                          }),
                        ),
                      if (fig.continuous)
                        ActionChip(
                          avatar: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 18),
                          label: Text(_playing ? 'Pausa' : 'Movimiento'),
                          onPressed: MediaQuery.disableAnimationsOf(context) ? null : _toggle,
                        ),
                    ],
                  ),
                ),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
                  TextButton(onPressed: _reset, child: const Text('Vista inicial')),
                  TextButton(
                      onPressed: () => setState(() {
                            _yaw = 0;
                            _pitch = 8;
                          }),
                      child: const Text('De perfil')),
                  TextButton(
                      onPressed: () => setState(() {
                            final body = liftSkeleton(fig.skeletonAt(_progress), fig);
                            final front = body.front;
                            if (front.y > .2) {
                              _yaw = 0;
                              _pitch = 75;
                            } else {
                              _yaw = math.atan2(front.x, front.z) * 180 / math.pi;
                              _pitch = (-math.asin(front.y.clamp(-1, 1)) * 180 / math.pi).clamp(0, 85);
                            }
                          }),
                      child: const Text('Ver apoyos')),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'Arrastra para girar · doble toque para volver a la vista inicial',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (fig.annotations.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(fig.annotations.map((a) => a['text'] as String).join(' · '))),
              ])),
            ),
          ],
        ),
      ),
    );
  }
}
