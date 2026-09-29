import Base
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/story.bend as StoryData
import ../data/strings.bend as Strings
import ../data/cave_story.bend as CaveStory
import ../data/cave_catalog.bend as CaveCatalog
import ../lua/strhash.bend as StrHash

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

def forest_or_caves(forest: List<&2, U32>, +lock: U32) -> List<&2, U32>:
  match forest:
    case Nil{}:
      CaveStory.locks_keys(lock)
    case Con{+count, +keys}:
      count <> keys

def room_name(+room: U32) -> String:
  Bool.pick(String, is_cave_room(room), CaveStory.room_name(cave_room(room)), Strings.name(Rooms.name(room)))

def room_value(+room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_value(cave_room(room)), Rooms.value(room))

def room_node_type(+room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_node_type(cave_room(room)), Rooms.node_type(room))

def room_internal_type(+room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_internal_type(cave_room(room)), Rooms.internal_type(room))

def room_exit_weight(+room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_exit_weight(cave_room(room)), Rooms.random_node_exit_weight(room))

def room_entrance_weight(+room: U32) -> U32:
  Bool.pick(U32, is_cave_room(room), CaveStory.room_entrance_weight(cave_room(room)), Rooms.random_node_entrance_weight(room))

# The RoadPoison, ForceConnected and ForceDisconnected bits of a caves room's tags (see gen/tags.bend).
def cave_room_poison(+room: U32) -> U32:
  CaveStory.room_poison(cave_room(room))

# The same bits of a caves task's room_tags.
def cave_task_poison(+task: U32) -> U32:
  CaveStory.task_room_poison(cave_task(task))

def task_name(+task: U32) -> String:
  Bool.pick(String, is_cave_task(task), CaveCatalog.task_name(cave_task(task)), Strings.name(task))

def task_hash(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), StrHash.hash_string(CaveCatalog.task_name(cave_task(task))), Strings.hash(task))

def task_locks(+task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), CaveStory.task_locks(cave_task(task)), Tasks.task_locks(task))

def task_keys_given(+task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), CaveStory.task_keys_given(cave_task(task)), Tasks.task_keys_given(task))

# LOCKS_KEYS is one game-wide table: a lock has the same keys on both shards, and each shard's rows cover the locks its
# tasks use, so a lock the forest table leaves empty is looked up in the caves' one.
def locks_keys(+lock: U32) -> List<&2, U32>:
  forest_or_caves(Tasks.locks_keys(lock), lock)

def task_room_bg(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_room_bg(cave_task(task)), Tasks.room_bg(task))

def task_background_room(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), caves_room_id(CaveStory.task_background_room(cave_task(task))), Tasks.background_room(task))

def task_cove_room(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), caves_room_id(CaveStory.task_cove_room(cave_task(task))), Tasks.cove_room(task))

def task_entrance_room(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), optional_cave_room(CaveStory.task_entrance_room(cave_task(task))), Tasks.entrance_room(task))

def task_entrance_is_list(+task: U32) -> Bool:
  Bool.pick(Bool, is_cave_task(task), U32.is_eq(CaveStory.task_entrance_is_list(cave_task(task)), 1), False{})

def task_has_entrance(+task: U32) -> Bool:
  Bool.not(Blob.is_none(task_entrance_room(task))) || task_entrance_is_list(task)

# The rooms of a caves task's entrance_room list, in list order.
def task_entrance_choices(+task: U32) -> List<&2, U32>:
  cave_rooms(CaveStory.task_entrance_choices(cave_task(task)))

def task_cove_room_chance(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_room_chance(cave_task(task)), Tasks.cove_room_chance(task))

def task_cove_room_max_edges(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_room_max_edges(cave_task(task)), Tasks.cove_room_max_edges(task))

def task_crosslink_factor(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_crosslink_factor(cave_task(task)), Tasks.crosslink_factor(task))

def task_make_loop(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_make_loop(cave_task(task)), Tasks.make_loop(task))

def task_region_id(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), Blob.none(), Tasks.region_id(task))

def task_cove_threshold(+task: U32) -> U32:
  Bool.pick(U32, is_cave_task(task), CaveStory.task_cove_threshold(cave_task(task)), Tasks.cove_threshold(task))

def default_cove_max_edges() -> U32:
  Tasks.default_cove_max_edges()

# The task's room_choices as (room, kind, value) triples in pairs() order, caves rooms as story ids.
def task_room_choices(+task: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_task(task), caves_choices(CaveStory.task_room_choices(cave_task(task))), Tasks.task_room_choices(task))

# The count closure row of a room_choices entry of a room.
def count_closure(+room: U32, +value: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_cave_room(room), CaveStory.count_closures(value), StoryData.count_closures(value))
