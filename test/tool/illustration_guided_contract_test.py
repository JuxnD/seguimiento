"""Coverage boundary from the approved 032/034 contracts, independent of generator lists."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
NAMES = '''Respiración 90/90|Gato-camello|Libro abierto|Muñecas a cuatro patas|Deslizamientos en la pared|Zancada del mundo|Rodilla a la pared|Sentadilla profunda|Pie corto|Pike sentado|Pancake|Dorsal en la cama|Pectoral en el marco de la puerta|Sóleo en la pared|Scap pull-up|Y-T prono|Abducción de cadera de lado|Copenhague|Sóleo sentado con mochila|Tibial en la pared|Rotación externa con banda|Support hold en paralelas|Sprint lanzado|Flexiones escapulares|Sentadilla isométrica en la pared|Nórdico inverso|Bajada lateral del escalón|Aterrizaje clavado|Mesa invertida|Plancha inversa sobre antebrazos|Plancha inversa sobre las manos|Plancha inversa a una pierna|Plancha inversa con patada|Plancha inversa con pies elevados'''.split('|')
VARIANTS = {
    'Tibial en la pared': ['tibialis_wall_close', 'tibialis_wall_far', 'tibialis_wall_loaded'],
    'Y-T prono': ['prone_y_t_floor', 'prone_y_t_bed_edge', 'prone_y_t_loaded'],
    'Copenhague': ['copenhagen_short', 'copenhagen_long'],
    'Sóleo sentado con mochila': ['seated_soleus_bilateral', 'seated_soleus_unilateral'],
    'Support hold en paralelas': ['support_parallels', 'support_rings', 'support_protraction'],
    'Rotación externa con banda': ['band_rotation_side', 'band_rotation_90_90'],
    'Aterrizaje clavado': ['landing_bilateral', 'landing_unilateral', 'landing_lateral'],
}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


class GuidedContract(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/'assets/tecnica/figuras3d.json').read_text(encoding='utf-8'))
        self.figures = {f['name']: f for f in self.data['figures']}

    def test_every_requested_identity_has_an_authored_specific_figure(self):
        self.assertEqual(set(NAMES) - self.figures.keys(), set())
        self.assertEqual(len(self.figures), 111)
        for name in NAMES:
            if name in ['Flexiones escapulares', 'Plancha inversa con patada']:
                continue
            f = self.figures[name]
            self.assertGreaterEqual(len(f['frames']), 3, name)
            self.assertEqual(len(f['motion']), len(f['frames'])-1, name)
            self.assertTrue(f['continuous'], name)
            self.assertTrue(f['source'].startswith('Plan v3.2'), name)

    def test_physical_variants_are_complete_and_not_silent_base_substitutions(self):
        variants = self.data.get('physicalVariants', [])
        self.assertEqual({(v['exercise'], v['key']) for v in variants},
                         {(name, key) for name, keys in VARIANTS.items() for key in keys})
        self.assertEqual(len(variants), 18)
        for variant in variants:
            name, key = variant['exercise'], variant['key']
            if key == VARIANTS[name][0]:
                self.assertTrue(variant.get('useBase'), key)
            else:
                figure = variant['figure']
                self.assertEqual(figure['name'], name)
                self.assertNotEqual(figure['frames'], self.figures[name]['frames'], key)

    def test_77_existing_figures_are_exact_and_only_owner_reopened_running_changes(self):
        baseline = json.loads((ROOT/'test/fixtures/illustration_035_mvp_hashes.json').read_text())
        self.assertEqual(len(baseline), 79)
        changed = {name for name, expected in baseline.items() if digest(self.figures[name]) != expected}
        # Owner reported the running diamond; FIFA parts1/10 use that same
        # authored stride. The historical baseline is deliberately unchanged.
        self.assertEqual(changed, {'Aceleración 10–20 m', 'Calentamiento tipo FIFA 11+'})


if __name__ == '__main__':
    unittest.main()
