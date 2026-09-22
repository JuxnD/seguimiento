/// Formato numérico es-CO: miles con punto, decimales con coma.
library;

String fmtInt(num value) {
  final n = value.round();
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Un decimal, sin ",0" sobrante: 82,5 · 80.
String fmtDec(num value, {int decimals = 1}) {
  var fixed = value.abs().toStringAsFixed(decimals);
  if (fixed.contains('.')) fixed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = fixed.split('.');
  final body = parts.length == 1 ? fmtInt(int.parse(parts[0])) : '${fmtInt(int.parse(parts[0]))},${parts[1]}';
  return (value < 0 && body != '0') ? '-$body' : body;
}

/// Δ con signo explícito: +1,5 · -0,8 · 0.
String fmtDelta(num value, {int decimals = 1}) {
  final r = double.parse(value.toStringAsFixed(decimals));
  if (r == 0) return '0';
  return r > 0 ? '+${fmtDec(r, decimals: decimals)}' : fmtDec(r, decimals: decimals);
}

/// Escapa texto libre para una celda de tabla Markdown.
String mdCell(String? s) =>
    (s == null || s.trim().isEmpty) ? '—' : s.trim().replaceAll('|', r'\|').replaceAll(RegExp(r'\s*\n\s*'), ' / ');
