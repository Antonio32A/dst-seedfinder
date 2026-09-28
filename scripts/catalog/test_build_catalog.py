import unittest

from build_catalog import minimap_icon

ATLAS = {name: {"xml": "minimap/minimap_data2.xml", "tex": "minimap/minimap_atlas2.tex"}
         for name in ["antlion.png", "rock.png", "flotsam_heavy.png", "singingshell_cluster.png", "storage_robot_broken.png"]}
TABLE = {
    "antlion": {"icon": "antlion.png", "priority": 1},
    "rock1": {"icon": "rock.png"},
    "shell_cluster": {"icon": "singingshell_cluster.png"},
    "storage_robot": {"icon": "storage_robot.png", "priority": 5},
    "floatinglantern": {"icon": "lantern.png", "over_fog": True},
    "ghost": {"icon": "missing.png"},
}


class MinimapIcon(unittest.TestCase):
    def test_takes_the_game_run_icon_with_its_priority(self):
        self.assertEqual(minimap_icon("antlion", TABLE, ATLAS), dict(ATLAS["antlion.png"], element="antlion.png", match="game", priority=1))

    def test_carries_the_draw_over_fog_flag(self):
        atlas = dict(ATLAS, **{"lantern.png": {"xml": "x", "tex": "y"}})
        self.assertTrue(minimap_icon("floatinglantern", TABLE, atlas)["over_fog"])

    def test_gives_a_spawner_the_icon_of_what_it_spawns(self):
        icon = minimap_icon("antlion_spawner", TABLE, ATLAS)
        self.assertEqual((icon["element"], icon["match"], icon["priority"]), ("antlion.png", "spawned:antlion", 1))

    def test_prefers_a_captured_icon_but_keeps_the_game_priority(self):
        icon = minimap_icon("storage_robot", TABLE, ATLAS)
        self.assertEqual((icon["element"], icon["match"], icon["priority"]), ("storage_robot_broken.png", "captured", 5))
        self.assertEqual(minimap_icon("shell_cluster", TABLE, ATLAS)["element"], "flotsam_heavy.png")

    def test_has_no_icon_for_prefabs_the_game_run_did_not_give_one(self):
        self.assertIsNone(minimap_icon("beefalo", TABLE, ATLAS))

    def test_has_no_icon_when_the_atlas_lacks_the_element(self):
        self.assertIsNone(minimap_icon("ghost", TABLE, ATLAS))


if __name__ == "__main__":
    unittest.main()
