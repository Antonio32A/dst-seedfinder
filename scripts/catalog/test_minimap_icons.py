import os
import unittest

from minimap_icons import LUA, ROOT, parse_icons, run_extractor

GAME_SCRIPTS = os.path.join(ROOT, "build/deps/game-scripts")


class ParseIcons(unittest.TestCase):
    def test_refuses_icon_names_that_are_not_file_names(self):
        with self.assertRaises(ValueError):
            parse_icons('{"a": {"icon": "../a.png"}}')


@unittest.skipUnless(os.path.isdir(GAME_SCRIPTS) and os.path.exists(LUA), "needs scripts/setup.sh")
class ExtractorOnTheGameScripts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = run_extractor()

    def test_records_the_last_icon_priority_and_draw_over_fog_flag_the_constructor_set(self):
        self.assertEqual(self.table["antlion"], {"icon": "antlion.png", "priority": 1})
        self.assertEqual(self.table["evergreen"], {"icon": "evergreen.png", "priority": -1})
        self.assertTrue(self.table["floatinglantern"]["over_fog"])

    def test_uses_the_master_simulations_later_icon(self):
        self.assertEqual(self.table["hermithouse_construction1"]["icon"], "hermitcrab_home.png")

    def test_finishes_constructors_that_crashed_on_stubs(self):
        for prefab in ["backpack", "shell_cluster", "sunkenchest"]:
            self.assertNotIn("incomplete", self.table[prefab])

    def test_has_no_row_for_prefabs_without_a_minimap_icon(self):
        for prefab in ["beefalo", "grassgekko", "antlion_spawner"]:
            self.assertNotIn(prefab, self.table)


if __name__ == "__main__":
    unittest.main()
