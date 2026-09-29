import struct
import unittest

from world import Instance
from world_dump import dump_of, pillars_payload, roads_payload


def words(payload):
    return struct.unpack(f"<{len(payload) // 4}i", payload)


class RoadsPayload(unittest.TestCase):
    def test_a_world_without_roads_has_a_zero_count(self):
        self.assertEqual(words(roads_payload([])), (0,))

    def test_null_entries_are_skipped_and_kept_roads_stay_in_order(self):
        roads = [[3, [1.5, -2.0], [3.0, 4.1], [5.0, 6.0]], None, [1, [0.1, 0.2], [0.3, -0.7]], None]
        self.assertEqual(
            words(roads_payload(roads)),
            (2, 3, 3, 150, -200, 300, 410, 500, 600, 1, 2, 10, 20, 30, -70),
        )

    def test_tenths_that_are_not_exact_in_binary_round_to_whole_hundredths(self):
        self.assertEqual(words(roads_payload([[1, [0.29, 1.15], [-0.57, 8.2]]]))[3:], (29, 115, -57, 820))


class Pillars(unittest.TestCase):
    def test_links_name_their_prefab_by_position_in_the_sorted_prefab_list(self):
        entities = {"tentacle_pillar_atrium": [(1.0, 2.0)], "rock1": [(0.0, 0.0)], "tentacle_pillar": [(3.0, 4.0), (5.0, 6.0)]}
        pillar = [Instance("tentacle_pillar", i, 0.0, 0.0) for i in range(2)]
        atrium = [Instance("tentacle_pillar_atrium", 0, 0.0, 0.0)]
        links = [(pillar[0], pillar[1]), (atrium[0], atrium[0])]
        self.assertEqual(words(pillars_payload(links, entities)), (2, 1, 0, 1, 1, 2, 0, 2, 0))


class Header(unittest.TestCase):
    def test_a_world_that_gave_up_is_a_version_3_header_with_its_shard(self):
        self.assertEqual(words(dump_of({"seed": 7, "status": "gave_up", "shard": "caves"}, "linux"))[1:], (3, 7, 0, 2, 1))

    def test_a_world_without_a_shard_is_a_forest_world(self):
        self.assertEqual(words(dump_of({"seed": 7, "status": "gave_up"}, "linux"))[5], 0)


if __name__ == "__main__":
    unittest.main()
