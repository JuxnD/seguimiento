"""Independent geometry contracts for the owner's reported illustrations."""
import math
import json
import hashlib
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool'))
import illustration_catalog as catalog


class Geometry035(unittest.TestCase):
    def test_carry_knees_share_forward_flexion(self):
        for name in ('Carga abrazada al pecho', 'Carga de maleta con mochila'):
            for frame in catalog.generate(name)['frames']:
                for side in ('near', 'far'):
                    upper, lower = frame[side + 'Leg']['angles']
                    # With y down and chest toward +x, flexion places knee
                    # in front of the hip-ankle axis: lower >= upper.
                    signed = math.sin(math.radians(lower - upper))
                    self.assertGreaterEqual(signed, -1e-6, (name, side, signed))

    def test_curl_forearm_moves_in_front_of_elbow(self):
        frames = catalog.generate('Curl con banda')['frames']
        start, end = frames[0]['nearArm']['angles'][1], frames[1]['nearArm']['angles'][1]
        delta = (end - start + 180) % 360 - 180
        for i in range(61):
            angle = start + delta * i / 60
            self.assertGreaterEqual(math.cos(math.radians(angle)), -1e-6, (i, angle))

    def test_straddle_reach_keeps_knees_straight(self):
        for frame in catalog.generate('Elevaciones en straddle')['frames']:
            for side in ('near', 'far'):
                reach = frame[side + 'Leg']['reach3']
                self.assertAlmostEqual(math.sqrt(sum(v*v for v in reach)), 28, delta=.02)

    def test_active_and_passive_hang_are_different_postures(self):
        active = dict(catalog.generate('Colgarse de la barra')['frames'][0])
        passive = dict(catalog.generate('Colgado pasivo')['frames'][0])
        active.pop('caption'); passive.pop('caption')
        self.assertNotEqual(active, passive)

    def test_vsit_has_entry_hold_and_exit_without_false_hand_support(self):
        frames = catalog.generate('Barca / V-sit')['frames']
        poses = [{k:v for k,v in f.items() if k != 'caption'} for f in frames]
        self.assertNotEqual(poses[0], poses[1])
        self.assertNotIn('manos permanecen firmes', frames[-1]['caption'])

    def test_requested_sequences_have_authored_phases(self):
        root = Path(__file__).resolve().parents[2]
        figures = json.loads((root/'assets/tecnica/figuras3d.json').read_text(encoding='utf-8'))['figures']
        authored = [f for f in figures if f.get('motion')]
        self.assertTrue(authored)
        for figure in authored:
            # Manual/reduced-motion is a controller state, never a mutation of
            # the rig contract that would select legacy floor normalization.
            self.assertIs(figure.get('continuous'), True, figure['name'])
        for name in ('90/90 de cadera', 'Aceleración 10–20 m', 'Burpees',
                     'Calentamiento tipo FIFA 11+', 'Barca / V-sit'):
            e = catalog.generate(name)
            self.assertEqual(len(e.get('motion', [])), len(e['frames']) - 1, name)
            self.assertTrue(any(p['kind'] == 'interpolate' for p in e['motion']), name)

    def test_burpee_separates_flight_and_landing(self):
        e = catalog.generate('Burpees')
        self.assertTrue(any(p.get('ground') == 'flight' for p in e.get('motion', [])))
        self.assertTrue(any('Aterriz' in f['caption'] for f in e['frames']))

    def test_fifa_cuts_between_parts_not_between_poses(self):
        e = catalog.generate('Calentamiento tipo FIFA 11+')
        parts = {p['part'] for p in e.get('motion', [])}
        self.assertEqual(len(parts), 10)
        self.assertEqual(sum(p['kind'] == 'cut' for p in e['motion']), 10)  # nine changes + explicit restart

    def test_fifa_lateral_hop_authors_actual_travel_and_airborne_pose(self):
        e = catalog.generate('Calentamiento tipo FIFA 11+')
        indices = [i for i, stage in enumerate(e['motion'])
                   if stage['part'] == '9' and stage['kind'] != 'cut']
        frames = [e['frames'][i] for i in indices] + [e['frames'][indices[-1]+1]]
        self.assertGreater(max(f.get('bodyZ', 0) for f in frames)-min(f.get('bodyZ', 0) for f in frames), 8)
        self.assertLess(min(f['hip'][1] for f in frames), frames[0]['hip'][1]-5)

    def test_fifa_lateral_steps_move_pelvis_and_feet_across_the_floor(self):
        e = catalog.generate('Calentamiento tipo FIFA 11+')
        indices = [i for i, stage in enumerate(e['motion'])
                   if stage['part'] == '3' and stage['kind'] != 'cut']
        frames = [e['frames'][i] for i in indices] + [e['frames'][indices[-1]+1]]
        self.assertGreater(max(f.get('bodyZ', 0) for f in frames)-min(f.get('bodyZ', 0) for f in frames), 6)
        for side, sign in [('near', 1), ('far', -1)]:
            feet = [(f.get('bodyZ', 0)+sign*3.3+f[side+'Leg'].get('reach3', [0, 0, 0])[2]) for f in frames]
            self.assertGreater(max(feet)-min(feet), 6, side)

    def test_unselected_asset_entries_are_unchanged(self):
        root = Path(__file__).resolve().parents[2]
        baseline = json.loads((root/'test/fixtures/illustration_035_baseline.json').read_text(encoding='utf-8'))['figures']
        selected = {'90/90 de cadera','Aceleración 10–20 m','Barca / V-sit','Burpees',
                    'Calentamiento tipo FIFA 11+','Carga abrazada al pecho','Carga de maleta con mochila',
                    'Colgarse de la barra','Colgado pasivo','Curl con banda','Dragon flag','Dominadas',
                    'Elevaciones en straddle','Negativo de dragon flag','Negativo de dragon flag a una pierna',
                    'Negativo de dragon flag recogido','Vela'}
        current = json.loads((root/'assets/tecnica/figuras3d.json').read_text(encoding='utf-8'))['figures']
        # Phase2 adds32 independent identities; no historical identity may
        # disappear. Exact111/11 coverage is checked by guided_contract_test.
        self.assertTrue(set(baseline) <= {f['name'] for f in current})
        for f in current:
            if f['name'] in selected or f['name'] not in baseline: continue
            # `muscles` comes from lib/data/exercise_details.dart (edited on the
            # 1.25.0 line); the geometry freeze covers every other field.
            pose = {k: v for k, v in f.items() if k != 'muscles'}
            digest = hashlib.sha256(json.dumps(pose,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
            self.assertEqual(digest,baseline[f['name']],f['name'])


if __name__ == '__main__':
    unittest.main()
