/// Guía de la banda elástica (§18.7). Asume una banda de lazo largo ("power
/// band"); si es de tubo con asas o una mini banda, hay que ajustar.
library;

/// Cómo anclar la banda para cada tipo de anclaje del catálogo.
const bandAnchors = <String, (String, String)>{
  'alto': (
    'Anclaje alto (en la barra)',
    'Pasa la banda por encima de la barra y mete un extremo dentro del otro, tirando hasta que quede '
        'estrangulada (nudo de alondra). Para face pull, jalón y extensión de tríceps hacia abajo.',
  ),
  'medio': (
    'Anclaje medio (a la altura del pecho)',
    'Alrededor de una columna, una baranda o la pata de un mueble pesado; o con un nudo en la banda metido '
        'en la puerta del lado de las bisagras, con la puerta cerrada y abriendo hacia el lado contrario al '
        'tuyo. Para Pallof press y remo de pie.',
  ),
  'bajo': (
    'Anclaje bajo (pisándola)',
    'Uno o ambos pies sobre la banda, a la anchura de la cadera. Para elevaciones laterales, curl, '
        'extensión sobre la cabeza y remo inclinado.',
  ),
  'manos': (
    'Sin anclaje (entre las manos)',
    'La banda se sostiene con las dos manos; la tensión sale de separarlas.',
  ),
};

const bandTension = 'Más tensión: aléjate del anclaje, agarra la banda más corta o dóblala.';

const bandSafety = [
  'Revisa que no tenga grietas antes de usarla.',
  'Nunca la sueltes bajo tensión.',
  'En el anclaje alto, la cara siempre fuera de la línea de la banda.',
  'El anclaje no debe poder deslizarse.',
];
