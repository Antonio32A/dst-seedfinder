import struct
import unittest

from world_dump import roads_payload


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


if __name__ == "__main__":
    unittest.main()
