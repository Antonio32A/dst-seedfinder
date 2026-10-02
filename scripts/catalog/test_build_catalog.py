import unittest
from unittest import mock

import names as handnames
from build_catalog import hidden_by_default, minimap_icon, missing_names_and_images, ruins_respawned

ATLAS = {name: {"xml": "minimap/minimap_data2.xml", "tex": "minimap/minimap_atlas2.tex"}
         for name in ["antlion.png", "rock.png", "flotsam_heavy.png", "storage_robot_broken.png", "lantern.png", "iceboulder.png"]}
TABLE = {
    "antlion": {"icon": "antlion.png", "priority": 1},
    "rock1": {"icon": "rock.png"},
    "shell_cluster": {"icon": "singingshell_cluster.png"},
    "storage_robot": {"icon": "storage_robot.png", "priority": 5},
    "floatinglantern": {"icon": "lantern.png", "over_fog": True},
    "rock_ice": {"icon": "iceboulder.png"},
    "ghost": {"icon": "missing.png"},
}


class IconRules(unittest.TestCase):
    def setUp(self):
        self.enterContext(mock.patch.dict(handnames.SPAWNED_ICONS, {"antlion_spawner": "antlion"}, clear=True))
        self.enterContext(mock.patch.dict(handnames.CAPTURED_ICONS, {"storage_robot": "storage_robot_broken.png"}, clear=True))
        self.enterContext(mock.patch.dict(handnames.CONDITIONAL_ICONS, {"rock_ice": "grows"}, clear=True))


class MinimapIcon(IconRules):
    def test_takes_the_game_run_icon_with_its_priority_and_draw_over_fog_flag(self):
        self.assertEqual(minimap_icon("antlion", TABLE, ATLAS), dict(ATLAS["antlion.png"], element="antlion.png", match="game", priority=1))
        self.assertTrue(minimap_icon("floatinglantern", TABLE, ATLAS)["over_fog"])

    def test_gives_a_spawner_the_icon_of_what_it_spawns(self):
        icon = minimap_icon("antlion_spawner", TABLE, ATLAS)
        self.assertEqual((icon["element"], icon["match"], icon["priority"]), ("antlion.png", "spawned:antlion", 1))

    def test_gives_a_ruins_respawner_the_icon_of_the_prefab_it_respawns_as(self):
        with mock.patch("build_catalog.ruins_respawned", return_value={"rock2_spawner": "rock1"}):
            icon = minimap_icon("rock2_spawner", TABLE, ATLAS)
        self.assertEqual((icon["element"], icon["match"]), ("rock.png", "respawned:rock1"))
        self.assertIsNone(hidden_by_default("rock2_spawner", icon))

    def test_finds_the_ruins_respawners_in_the_game_scripts(self):
        respawned = ruins_respawned()
        self.assertEqual(respawned["ancient_altar_spawner"], "ancient_altar")
        self.assertEqual(respawned["ruins_statue_mage_nogem_spawner"], "ruins_statue_mage_nogem")
        self.assertEqual(respawned["chessjunk_spawner"], "chessjunk1")

    def test_prefers_a_captured_icon_but_keeps_the_game_priority(self):
        icon = minimap_icon("storage_robot", TABLE, ATLAS)
        self.assertEqual((icon["element"], icon["match"], icon["priority"]), ("storage_robot_broken.png", "captured", 5))

    def test_has_no_icon_without_a_game_run_icon_or_an_atlas_element_for_it(self):
        self.assertIsNone(minimap_icon("beefalo", TABLE, ATLAS))
        self.assertIsNone(minimap_icon("ghost", TABLE, ATLAS))


class HiddenByDefault(IconRules):
    def test_draws_game_run_icons(self):
        self.assertIsNone(hidden_by_default("rock1", minimap_icon("rock1", TABLE, ATLAS)))

    def test_hides_a_spawner_marker_because_the_game_draws_nothing_at_it(self):
        self.assertIn("spawner marker", hidden_by_default("antlion_spawner", minimap_icon("antlion_spawner", TABLE, ATLAS)))

    def test_hides_a_prefab_whose_icon_depends_on_its_state(self):
        self.assertEqual(hidden_by_default("rock_ice", minimap_icon("rock_ice", TABLE, ATLAS)), "grows")

    def test_hides_a_prefab_without_an_icon(self):
        self.assertEqual(hidden_by_default("beefalo", None), "no minimap icon")


def sampled(prefab, name_source="strings", icons=None):
    return {"id": prefab, "name_source": name_source, "icons": icons or {}, "empirical": {"worlds": 3}}


class MissingNamesAndImages(unittest.TestCase):
    def setUp(self):
        self.enterContext(mock.patch.object(handnames, "NO_IMAGE", {"tentacle"}))

    def test_accepts_a_named_prefab_with_an_image(self):
        self.assertEqual(missing_names_and_images([sampled("rock1", icons={"minimap": {}})]), [])

    def test_accepts_a_prefab_declared_imageless(self):
        self.assertEqual(missing_names_and_images([sampled("tentacle")]), [])

    def test_reports_a_prefab_without_a_name_or_an_image(self):
        problems = missing_names_and_images([sampled("pillar_cave", name_source="fallback")])
        self.assertEqual(problems, ["pillar_cave: no display name", "pillar_cave: no image"])

    def test_ignores_prefabs_no_sampled_world_has(self):
        unsampled = dict(sampled("amulet", name_source="fallback"), empirical={"worlds": 0})
        self.assertEqual(missing_names_and_images([unsampled]), [])

    def test_reports_a_stale_imageless_declaration(self):
        self.assertEqual(missing_names_and_images([sampled("tentacle", icons={"inventory": {}})]),
                         ["tentacle: has an image but is listed in names.NO_IMAGE"])


if __name__ == "__main__":
    unittest.main()
