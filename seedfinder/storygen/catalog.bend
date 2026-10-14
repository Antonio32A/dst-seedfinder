import Base
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/story.bend as StoryData
import ../data/strings.bend as Strings
import ../data/cave_story.bend as CaveStory
import ../data/cave_catalog.bend as CaveCatalog
import ../lua/strhash.bend as StrHash
import ../data/builds.bend as Builds

# The rooms and tasks storygen reads, for both shards. Forest ids are the rows of data/rooms.bend and data/tasks.bend;
# a caves room or task id is its row of data/cave_story.bend plus cave_room_base() or cave_task_base(), so every id
# stored in the story state says which table it belongs to.

def cave_room_base() -> U32:
  128

def cave_task_base() -> U32:
  64

def is_cave_room(+room: U32) -> Bool:
  (room >= cave_room_base() : U32)

def is_cave_task(+task: U32) -> Bool:
  (task >= cave_task_base() : U32)

def cave_room(+room: U32) -> U32:
  (room - cave_room_base() : U32)

def cave_task(+task: U32) -> U32:
  (task - cave_task_base() : U32)

def caves_room_id(+local: U32) -> U32:
  (local + cave_room_base() : U32)

def caves_task_id(+local: U32) -> U32:
  (local + cave_task_base() : U32)

def optional_cave_room(+room: U32) -> U32:
  Bool.pick(U32, Blob.is_none(room), room, caves_room_id(room))

def cave_rooms(rooms: List<&2, U32>) -> List<&2, U32>:
  match rooms:
    case Nil{}:
      Nil{}
    case Con{+room, rest}:
      caves_room_id(room) <> cave_rooms(rest)

def caves_choices(triples: List<&2, U32>) -> List<&2, U32>:
  match triples:
    case Con{+room, Con{+kind, Con{+value, rest}}}:
      caves_room_id(room) <> kind <> value <> caves_choices(rest)
    case _:
      Nil{}

def forest_or_caves(+build: Builds.Build, forest: List<&2, U32>, +lock: U32) -> List<&2, U32>:
  match forest:
    case Nil{}:
      CaveStory.locks_keys(build, lock)
    case Con{+count, +keys}:
      count <> keys

def room_name(+build: Builds.Build, +room: U32) -> String:
  Bool.pick(String, is_cave_room(room), CaveStory.room_name(build, cave_room(room)), Strings.name(build, Rooms.name(build, room)))

def room_value(+build: Builds.Build, +room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_value(build, cave_room(room)), Rooms.value(build, room))

def room_node_type(+build: Builds.Build, +room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_node_type(build, cave_room(room)), Rooms.node_type(build, room))

def room_internal_type(+build: Builds.Build, +room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_internal_type(build, cave_room(room)), Rooms.internal_type(build, room))

def room_exit_weight(+build: Builds.Build, +room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_exit_weight(build, cave_room(room)), Rooms.random_node_exit_weight(build, room))

def room_entrance_weight(+build: Builds.Build, +room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_entrance_weight(build, cave_room(room)), Rooms.random_node_entrance_weight(build, room))

# The RoadPoison, ForceConnected and ForceDisconnected bits of a caves room's tags (see gen/tags.bend).
def cave_room_poison(+build: Builds.Build, +room: U32) -> U32:
  CaveStory.room_poison(build, cave_room(room))

# The same bits of a caves task's room_tags.
def cave_task_poison(+build: Builds.Build, +task: U32) -> U32:
  CaveStory.task_room_poison(build, cave_task(task))

def task_name(+build: Builds.Build, +task: U32) -> String:
  Bool.pick(String, is_cave_task(task), CaveCatalog.task_name(build, cave_task(task)), Strings.name(build, task))

def task_hash(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), StrHash.hash_string(CaveCatalog.task_name(build, cave_task(task))), Strings.hash(build, task))

def task_locks(+build: Builds.Build, +task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), CaveStory.task_locks(build, cave_task(task)), Tasks.task_locks(build, task))

def task_keys_given(+build: Builds.Build, +task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), CaveStory.task_keys_given(build, cave_task(task)), Tasks.task_keys_given(build, task))

# LOCKS_KEYS is one game-wide table: a lock has the same keys on both shards, and each shard's rows cover the locks its
# tasks use, so a lock the forest table leaves empty is looked up in the caves' one.
def locks_keys(+build: Builds.Build, +lock: U32) -> List<&2, U32>:
  forest_or_caves(build, Tasks.locks_keys(build, lock), lock)

def task_room_bg(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_room_bg(build, cave_task(task)), Tasks.room_bg(build, task))

def task_background_room(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), caves_room_id(CaveStory.task_background_room(build, cave_task(task))), Tasks.background_room(build, task))

def task_cove_room(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), caves_room_id(CaveStory.task_cove_room(build, cave_task(task))), Tasks.cove_room(build, task))

def task_entrance_room(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), optional_cave_room(CaveStory.task_entrance_room(build, cave_task(task))), Tasks.entrance_room(build, task))

def task_entrance_is_list(+build: Builds.Build, +task: U32) -> Bool:
  Bool.pick(Bool, is_cave_task(task), U32.is_eq(CaveStory.task_entrance_is_list(build, cave_task(task)), 1), False{})

def task_has_entrance(+build: Builds.Build, +task: U32) -> Bool:
  Bool.not(Blob.is_none(task_entrance_room(build, task))) || task_entrance_is_list(build, task)

# The rooms of a caves task's entrance_room list, in list order.
def task_entrance_choices(+build: Builds.Build, +task: U32) -> List<&2, U32>:
  cave_rooms(CaveStory.task_entrance_choices(build, cave_task(task)))

def task_cove_room_chance(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_room_chance(build, cave_task(task)), Tasks.cove_room_chance(build, task))

def task_cove_room_max_edges(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_room_max_edges(build, cave_task(task)), Tasks.cove_room_max_edges(build, task))

def task_crosslink_factor(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_crosslink_factor(build, cave_task(task)), Tasks.crosslink_factor(build, task))

def task_make_loop(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_make_loop(build, cave_task(task)), Tasks.make_loop(build, task))

def task_region_id(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), Blob.none(), Tasks.region_id(build, task))

def task_cove_threshold(+build: Builds.Build, +task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_threshold(build, cave_task(task)), Tasks.cove_threshold(build, task))

def default_cove_max_edges(+build: Builds.Build) -> U32:
  Tasks.default_cove_max_edges(build)

# The task's room_choices as (room, kind, value) triples in pairs() order, caves rooms as story ids.
def task_room_choices(+build: Builds.Build, +task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), caves_choices(CaveStory.task_room_choices(build, cave_task(task))), Tasks.task_room_choices(build, task))

# The count closure row of a room_choices entry of a room.
def count_closure(+build: Builds.Build, +room: U32, +value: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_room(room), CaveStory.count_closures(build, value), StoryData.count_closures(build, value))
