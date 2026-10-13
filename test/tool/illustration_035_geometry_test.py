"""Independent geometry contracts for the owner's reported illustrations."""
import math
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


if __name__ == '__main__':
    unittest.main()
