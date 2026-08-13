#!/usr/bin/env python3
"""
Extract Wolfenstein 3D shareware maps (GAMEMAPS.WL1) and compress each
64x64 dual-plane level into the Wolf64 4 KB single-byte map format.
"""

from __future__ import annotations

import argparse
import random
import struct
import sys
from pathlib import Path

MAP_W = 64
MAP_H = 64
PLANE_BYTES = MAP_W * MAP_H * 2
AREATILE = 107
AMBUSHTILE = 106
PUSHABLETILE = 98
EXITTILE = 99
ICONARROWS = 90
ELEVATORTILE = 21

# Wolf64 geometry: 1..14 solid, 15..17 doors, 18+ walkable
T_EMPTY = 18
T_GREY = 1
T_GREY_BANNER = 2
T_BLUE = 3
T_BLUE_CELL = 4
T_WOOD = 5
T_WOOD_HITLER = 6
T_BRICK = 7
T_BRICK_WREATH = 8
T_PURPLE = 9
T_PURPLE_BLOOD = 10
T_ELEVATOR = 13
T_PUSHWALL = 14
T_DOOR = 15
T_LOCKED_GOLD = 16
T_LOCKED_SILVER = 17

# Items / props / actors (19+; 18 = empty floor)
T_AMMO = 19
T_FIRSTAID = 20
T_FOOD = 21
T_GOLD_KEY = 22
T_SILVER_KEY = 23
T_CROSS = 24
T_CHALICE = 25
T_MACHINEGUN = 26
T_PILLAR = 33
T_TABLE = 34
T_LAMP = 35
T_BLOOD = 36
T_PLANT = 37
T_PLAYER = 49  # +0..3 NESW
T_GUARD_PATROL = 53
T_GUARD_AMBUSH = 57
T_SS_PATROL = 61
T_SS_AMBUSH = 65
T_DOG = 69
T_BOSS = 73
T_TURN = 113  # +0..7 N,NE,E,SE,S,SW,W,NW (Wolf ICONARROWS)
T_EXIT = 145
T_PUSH_TRAJ = 146  # +0..3 NESW

# Wolf dir 0..3 = E,N,W,S  ->  our 0..3 = N,E,S,W
WOLF_DIR_TO_NESW = (1, 0, 3, 2)

# Wolf ICONARROWS 0..7 (E,NE,N,NW,W,SW,S,SE) -> our 8-dir
ARROW_TO_8 = (2, 1, 0, 7, 6, 5, 4, 3)
# Vertical flip: N↔S, NE↔SE, NW↔SW (E/W unchanged)
_TURN_FLIP_8 = (4, 3, 2, 1, 0, 7, 6, 5)

DIR_DELTA = (
    (0, -1),  # N
    (1, 0),   # E
    (0, 1),   # S
    (-1, 0),  # W
)

# Wall plane tile -> Wolf64 wall id (unmapped solids fall back to grey stone)
WALL_TEXTURE_MAP = {
    1: T_GREY,
    2: T_GREY,
    3: T_GREY_BANNER,
    4: T_GREY_BANNER,  # portrait -> banner
    5: T_BLUE_CELL,
    6: T_GREY_BANNER,  # eagle -> banner
    7: T_BLUE_CELL,
    8: T_BLUE,
    9: T_BLUE,
    10: T_WOOD_HITLER,  # wood eagle -> wood portrait
    11: T_WOOD_HITLER,
    12: T_WOOD,
    # 13 = entrance jamb — inherit neighbor texture in convert_level (not exit)
    14: T_GREY,  # steel -> stone
    15: T_GREY,
    16: T_GREY,  # landscape slot
    17: T_BRICK,
    18: T_BRICK_WREATH,
    19: T_PURPLE,
    20: T_BRICK,  # shield brick -> plain brick
    21: T_ELEVATOR,
    22: T_ELEVATOR,
    23: T_WOOD_HITLER,  # iron cross wood -> wood portrait
    24: T_GREY_BANNER,  # slime accent -> banner family
    25: T_PURPLE_BLOOD,
    26: T_GREY,
    27: T_GREY,
    28: T_GREY,
}

# Object-plane statics: Wolf object id 23+i  ->  our floor id (None = drop)
STATIC_MAP = {
    0: None,  # puddle
    1: T_PILLAR,  # barrel
    2: T_TABLE,
    3: T_LAMP,
    4: T_LAMP,  # chandelier
    5: None,  # hanged man
    6: T_FOOD,  # dog food / alpo
    7: T_PILLAR,
    8: T_PLANT,  # tree
    9: T_BLOOD,  # flat skeleton
    10: None,  # sink
    11: T_PLANT,
    12: T_PILLAR,  # urn
    13: T_TABLE,
    14: T_LAMP,  # ceiling light
    15: None,  # kitchen
    16: T_PILLAR,  # armor
    17: None,  # cage
    18: T_BLOOD,  # skeleton in cage
    19: T_BLOOD,  # skeleton relax
    20: T_GOLD_KEY,
    21: T_SILVER_KEY,
    22: None,
    23: None,
    24: T_FOOD,
    25: T_FIRSTAID,
    26: T_AMMO,
    27: T_MACHINEGUN,
    28: T_MACHINEGUN,  # chaingun -> machine gun
    29: T_CROSS,
    30: T_CHALICE,
    31: T_CROSS,  # bible -> cross
    32: T_CHALICE,  # crown -> chalice
    33: T_FIRSTAID,  # 1-up
    34: T_BLOOD,  # gibs
    35: T_PILLAR,  # barrel
    36: None,  # well
    37: None,  # empty well
    38: T_BLOOD,
    39: None,  # flag
    40: None,  # apogee
    41: None,
    42: None,
    43: None,
    44: None,
    45: None,
    46: None,
    47: None,
}

# Runtime item pool budget (must match MAX_ITEMS in src/mem.asm).
MAX_ITEMS_BUDGET = 200

# Wolf object ids kept when randomly culling overflow props.
# Ceiling lamps (chandelier / ceiling light) + all pickups / weapons / 1-up.
KEEP_STATIC_OBJS = frozenset(
    {
        27,  # chandelier
        29,  # dog food
        37,  # ceiling light
        43,  # gold key
        44,  # silver key
        47,  # food
        48,  # first aid
        49,  # ammo
        50,  # machinegun
        51,  # chaingun
        56,  # 1-up → first aid
    }
)


def is_spawn_item_tile(tile: int) -> bool:
    """Tiles that items_init registers into the SoA (cross/chalice skipped)."""
    if T_AMMO <= tile <= T_MACHINEGUN:
        return tile not in (T_CROSS, T_CHALICE)
    return T_PILLAR <= tile <= T_PLANT


def is_cullable_static_obj(obj: int) -> bool:
    if obj in KEEP_STATIC_OBJS:
        return False
    if not (23 <= obj <= 74):
        return False
    mapped = map_static(obj)
    return mapped is not None and is_spawn_item_tile(mapped)


def cull_items_to_budget(out: bytearray, objs: list[int], rng: random.Random) -> int:
    """
    Random rejection cull: pick a cell; if its object is a cullable prop and the
    output tile still occupies an item slot, clear it. Repeat until under budget.
    """
    n = sum(1 for t in out if is_spawn_item_tile(t))
    if n <= MAX_ITEMS_BUDGET:
        return 0

    culled = 0
    cells = MAP_W * MAP_H
    # Bound attempts so a misconfigured keep-set cannot hang.
    attempts = 0
    max_attempts = cells * 64
    while n > MAX_ITEMS_BUDGET and attempts < max_attempts:
        attempts += 1
        i = rng.randrange(cells)
        o = objs[i]
        if not is_cullable_static_obj(o):
            continue
        if not is_spawn_item_tile(out[i]):
            continue
        out[i] = T_EMPTY
        culled += 1
        n -= 1
    if n > MAX_ITEMS_BUDGET:
        raise RuntimeError(
            f"item cull stuck at {n} spawnables (budget {MAX_ITEMS_BUDGET}); "
            f"culled {culled}"
        )
    return culled


def carmack_expand(data: bytes, expanded_len: int) -> bytearray:
    """CAL_CarmackExpand — length is expanded size in bytes."""
    out = bytearray(expanded_len)
    length = expanded_len // 2
    in_i = 0
    out_i = 0
    src = memoryview(data)

    while length > 0:
        if in_i + 2 > len(src):
            raise ValueError("Carmack stream truncated")
        ch = src[in_i] | (src[in_i + 1] << 8)
        in_i += 2
        tag = ch >> 8
        if tag == 0xA7:  # near
            count = ch & 0xFF
            if count == 0:
                if in_i >= len(src):
                    raise ValueError("Carmack near literal truncated")
                ch = (ch & 0xFF00) | src[in_i]
                in_i += 1
                out[out_i] = ch & 0xFF
                out[out_i + 1] = ch >> 8
                out_i += 2
                length -= 1
            else:
                if in_i >= len(src):
                    raise ValueError("Carmack near offset truncated")
                offset = src[in_i]
                in_i += 1
                copy_i = out_i - offset * 2
                length -= count
                while count:
                    out[out_i] = out[copy_i]
                    out[out_i + 1] = out[copy_i + 1]
                    out_i += 2
                    copy_i += 2
                    count -= 1
        elif tag == 0xA8:  # far
            count = ch & 0xFF
            if count == 0:
                if in_i >= len(src):
                    raise ValueError("Carmack far literal truncated")
                ch = (ch & 0xFF00) | src[in_i]
                in_i += 1
                out[out_i] = ch & 0xFF
                out[out_i + 1] = ch >> 8
                out_i += 2
                length -= 1
            else:
                if in_i + 2 > len(src):
                    raise ValueError("Carmack far offset truncated")
                offset = src[in_i] | (src[in_i + 1] << 8)
                in_i += 2
                copy_i = offset * 2
                length -= count
                while count:
                    out[out_i] = out[copy_i]
                    out[out_i + 1] = out[copy_i + 1]
                    out_i += 2
                    copy_i += 2
                    count -= 1
        else:
            out[out_i] = ch & 0xFF
            out[out_i + 1] = ch >> 8
            out_i += 2
            length -= 1
    return out


def rlew_expand(data: bytes, rlew_tag: int, dest_len: int) -> list[int]:
    """CA_RLEWexpand — returns dest_len/2 little-endian words."""
    words_out = dest_len // 2
    out: list[int] = []
    i = 0
    n = len(data)
    while len(out) < words_out:
        if i + 2 > n:
            raise ValueError("RLEW stream truncated")
        w = data[i] | (data[i + 1] << 8)
        i += 2
        if w == rlew_tag:
            if i + 4 > n:
                raise ValueError("RLEW run truncated")
            count = data[i] | (data[i + 1] << 8)
            value = data[i + 2] | (data[i + 3] << 8)
            i += 4
            out.extend([value] * count)
        else:
            out.append(w)
    if len(out) != words_out:
        raise ValueError(f"RLEW size mismatch: got {len(out)}, want {words_out}")
    return out


def decompress_plane(chunk: bytes, rlew_tag: int) -> list[int]:
    """Auto-detect Carmack+RLEW vs RLEW-only, return 4096 tile words."""
    if len(chunk) < 2:
        raise ValueError("Empty plane chunk")
    first = chunk[0] | (chunk[1] << 8)
    if first == PLANE_BYTES:
        return rlew_expand(chunk[2:], rlew_tag, PLANE_BYTES)
    if len(chunk) < 4:
        raise ValueError("Plane chunk too small for Carmack")
    # Carmack: word0 = expanded RLEW size, then Carmack payload
    expanded = first
    carmacked = carmack_expand(chunk[2:], expanded)
    # RLEW payload still leads with a size word
    return rlew_expand(bytes(carmacked[2:]), rlew_tag, PLANE_BYTES)


def read_maphead(path: Path) -> tuple[int, list[int]]:
    data = path.read_bytes()
    if len(data) < 402:
        raise ValueError(f"MAPHEAD too small: {path}")
    rlew_tag = struct.unpack_from("<H", data, 0)[0]
    offsets = list(struct.unpack_from("<100i", data, 2))
    return rlew_tag, offsets


def read_level(gamemaps: bytes, offset: int, rlew_tag: int) -> tuple[str, list[int], list[int]]:
    header = gamemaps[offset : offset + 38]
    if len(header) < 38:
        raise ValueError(f"Truncated level header at {offset}")
    p0, p1, _p2 = struct.unpack_from("<iii", header, 0)
    l0, l1, _l2 = struct.unpack_from("<HHH", header, 12)
    width, height = struct.unpack_from("<HH", header, 18)
    name = header[22:38].split(b"\0", 1)[0].decode("ascii", errors="replace")
    if width != MAP_W or height != MAP_H:
        raise ValueError(f"{name}: expected 64x64, got {width}x{height}")
    walls = decompress_plane(gamemaps[p0 : p0 + l0], rlew_tag)
    objs = decompress_plane(gamemaps[p1 : p1 + l1], rlew_tag)
    return name, walls, objs


def idx(x: int, y: int) -> int:
    return y * MAP_W + x


def in_bounds(x: int, y: int) -> bool:
    return 0 <= x < MAP_W and 0 <= y < MAP_H


def map_wall_texture(tile: int) -> int:
    if tile in WALL_TEXTURE_MAP:
        return WALL_TEXTURE_MAP[tile]
    if 1 <= tile <= 63:
        return T_GREY
    return T_EMPTY


def map_door(tile: int) -> int:
    # 90/91 unlocked, 92-99 locked variants, 100/101 elevator door
    lock = (tile - 90) // 2
    if lock == 0 or tile >= 100:
        return T_DOOR
    # Wolf lock 1/3 → gold key bit0; 2/4 → silver key bit1
    if lock in (1, 3):
        return T_LOCKED_GOLD
    return T_LOCKED_SILVER


def facing(base: int, wolf_dir: int) -> int:
    return base + WOLF_DIR_TO_NESW[wolf_dir & 3]


def map_static(obj: int) -> int | None:
    return STATIC_MAP.get(obj - 23)


def _match_stand_patrol(
    obj: int,
    stand_easy: int,
    patrol_easy: int,
    tiers: tuple[int, ...],
) -> tuple[str, int] | None:
    """Return ('stand'|'patrol', wolf_dir) if obj is in a selected difficulty tier."""
    for add in tiers:
        stand = stand_easy + add
        patrol = patrol_easy + add
        if stand <= obj <= stand + 3:
            return "stand", obj - stand
        if patrol <= obj <= patrol + 3:
            return "patrol", obj - patrol
    return None


# Wolf skill gates (WL_GAME.C fallthrough): +0 always, +36 ≥ gd_medium
# ("Bring 'em On!"), +72 ≥ gd_hard only. Mutants use +18 / +36.
DIFF_BRING_EM_ON = (0, 36)			# exclude Death-incarnate-only (+72)
DIFF_BRING_EM_ON_MUTANT = (0, 18)		# exclude hard-only (+36)


def enemy_from_object(obj: int, ambush: bool) -> int | None:
    """Map Wolf object-plane enemy codes onto our actor IDs (Bring 'em On)."""
    # Guards / officers / SS / dogs. Officers -> guards.
    # Stand (108–111…) = static until alert. Patrol (112–115…) = walk paths.
    # Ambush wall-plane marks deaf stand; both stand IDs use T_*_AMBUSH for now
    # (no chase/sound yet — both must not patrol).
    del ambush  # reserved for EF_DEAF when alert AI lands
    for stand_easy, patrol_easy, patrol_id, ambush_id in (
        (108, 112, T_GUARD_PATROL, T_GUARD_AMBUSH),
        (116, 120, T_GUARD_PATROL, T_GUARD_AMBUSH),
        (126, 130, T_SS_PATROL, T_SS_AMBUSH),
        (134, 138, T_DOG, T_DOG),
    ):
        hit = _match_stand_patrol(obj, stand_easy, patrol_easy, DIFF_BRING_EM_ON)
        if hit is None:
            continue
        kind, wolf_dir = hit
        if kind == "patrol" or patrol_id == ambush_id:
            base = patrol_id
        else:
            base = ambush_id
        return facing(base, wolf_dir)

    # Mutants (+18 medium, +36 hard) -> SS
    hit = _match_stand_patrol(obj, 216, 220, DIFF_BRING_EM_ON_MUTANT)
    if hit is not None:
        kind, wolf_dir = hit
        base = T_SS_AMBUSH if kind == "stand" else T_SS_PATROL
        return facing(base, wolf_dir)

    bosses = {
        214: 0,  # Hans
        197: 1,  # Gretel
        215: 2,  # Giftmacher
        179: 3,  # Fat
        196: 0,  # Schabbs
        160: 1,  # Fake Hitler
        178: 2,  # Hitler
    }
    if obj in bosses:
        return T_BOSS + bosses[obj]

    if obj == 124:
        return T_BLOOD  # dead guard prop

    return None


def is_walkable_wall_plane(tile: int) -> bool:
    return tile >= AREATILE or tile == AMBUSHTILE


def is_solid_wall_plane(tile: int) -> bool:
    return 1 <= tile <= 89


def entrance_jamb_texture(walls: list[int], x: int, y: int) -> int:
    """
    Wolf wall 13 is the level-entrance shaft (not the exit switch).
    Match the most common adjacent solid wall texture so bumping it
    does not trigger T_ELEVATOR / next-level.
    """
    counts: dict[int, int] = {}
    for dx, dy in DIR_DELTA:
        nx, ny = x + dx, y + dy
        if not in_bounds(nx, ny):
            continue
        nw = walls[idx(nx, ny)]
        if nw in (13, ELEVATORTILE, 22):
            continue
        if not is_solid_wall_plane(nw):
            continue
        tex = map_wall_texture(nw)
        if tex == T_ELEVATOR:
            continue
        counts[tex] = counts.get(tex, 0) + 1
    if not counts:
        return T_GREY
    # Majority; ties prefer lower texture id for stable output
    return max(counts.items(), key=lambda kv: (kv[1], -kv[0]))[0]


def pushwall_direction(walls: list[int], x: int, y: int) -> int:
    """
    Infer push direction: longest run of walkable tiles on a cardinal side.
    Ties break N,E,S,W order.
    """
    best_dir = 0
    best_run = -1
    for d, (dx, dy) in enumerate(DIR_DELTA):
        run = 0
        cx, cy = x + dx, y + dy
        while in_bounds(cx, cy) and is_walkable_wall_plane(walls[idx(cx, cy)]):
            run += 1
            cx += dx
            cy += dy
        if run > best_run:
            best_run = run
            best_dir = d
    return best_dir


def convert_level(
    walls: list[int],
    objs: list[int],
    rng: random.Random | None = None,
) -> bytes:
    out = bytearray(MAP_W * MAP_H)
    pushwalls: list[tuple[int, int]] = []

    for y in range(MAP_H):
        for x in range(MAP_W):
            i = idx(x, y)
            w = walls[i]
            o = objs[i]
            ambush = w == AMBUSHTILE

            # --- solid geometry / doors ---
            if 90 <= w <= 101:
                out[i] = map_door(w)
                continue

            if w == ELEVATORTILE or w == 22:
                out[i] = T_ELEVATOR
                # Pushwall marker on an elevator is degenerate; ignore object.
                continue

            # Entrance jamb: blend into neighboring walls (not an exit switch)
            if w == 13:
                out[i] = entrance_jamb_texture(walls, x, y)
                continue

            if is_solid_wall_plane(w):
                if o == PUSHABLETILE:
                    out[i] = T_PUSHWALL
                    pushwalls.append((x, y))
                else:
                    out[i] = map_wall_texture(w)
                continue

            # --- walkable floor ---
            tile = T_EMPTY

            if o == EXITTILE:
                tile = T_EXIT
            elif ICONARROWS <= o <= ICONARROWS + 7:
                tile = T_TURN + ARROW_TO_8[o - ICONARROWS]
            elif 19 <= o <= 22:
                tile = T_PLAYER + (o - 19)  # already NESW
            elif 23 <= o <= 74:
                static = map_static(o)
                if static is not None:
                    tile = static
            else:
                enemy = enemy_from_object(o, ambush)
                if enemy is not None:
                    tile = enemy

            out[i] = tile

    # Trajectory markers behind pushwalls (only overwrite empty floor).
    for x, y in pushwalls:
        d = pushwall_direction(walls, x, y)
        dx, dy = DIR_DELTA[d]
        tx, ty = x + dx, y + dy
        if not in_bounds(tx, ty):
            continue
        ti = idx(tx, ty)
        if out[ti] == T_EMPTY:
            out[ti] = T_PUSH_TRAJ + d

    if rng is None:
        rng = random.Random(0x57464F4C)  # "WOLF"
    culled = cull_items_to_budget(out, objs, rng)
    if culled:
        print(f"  culled {culled} props to <={MAX_ITEMS_BUDGET} item slots")

    return flip_vertical(bytes(out))


# Tile bases that pack NESW in low 2 bits (0=N,1=E,2=S,3=W)
_FACING_BASES = (
    T_PLAYER,
    T_GUARD_PATROL,
    T_GUARD_AMBUSH,
    T_SS_PATROL,
    T_SS_AMBUSH,
    T_DOG,
    T_PUSH_TRAJ,
)


def _flip_facing_tile(t: int) -> int:
    """N↔S on directed tiles; E/W and undirected tiles unchanged."""
    if T_TURN <= t <= T_TURN + 7:
        return T_TURN + _TURN_FLIP_8[t - T_TURN]
    for base in _FACING_BASES:
        if base <= t <= base + 3:
            d = t - base
            if d == 0:
                return base + 2			# N → S
            if d == 2:
                return base + 0			# S → N
            return t
    return t


def flip_vertical(blob: bytes) -> bytes:
    """Mirror map on Y (out[x,63-y]=in[x,y]) and N↔S facings."""
    if len(blob) != MAP_W * MAP_H:
        raise ValueError(f"map size {len(blob)}, want {MAP_W * MAP_H}")
    out = bytearray(MAP_W * MAP_H)
    for y in range(MAP_H):
        fy = MAP_H - 1 - y
        for x in range(MAP_W):
            out[idx(x, fy)] = _flip_facing_tile(blob[idx(x, y)])
    return bytes(out)


def sanitize_filename(name: str, index: int) -> str:
    cleaned = "".join(c if c.isalnum() or c in "-_" else "_" for c in name.strip())
    cleaned = cleaned.strip("_") or f"map{index:02d}"
    return f"{index:02d}_{cleaned}.bin"


def extract_all(shareware_dir: Path, out_dir: Path) -> list[tuple[str, Path]]:
    maphead = shareware_dir / "MAPHEAD.WL1"
    gamemaps_path = shareware_dir / "GAMEMAPS.WL1"
    if not maphead.is_file() or not gamemaps_path.is_file():
        raise FileNotFoundError(f"Need MAPHEAD.WL1 and GAMEMAPS.WL1 in {shareware_dir}")

    rlew_tag, offsets = read_maphead(maphead)
    gamemaps = gamemaps_path.read_bytes()
    out_dir.mkdir(parents=True, exist_ok=True)

    written: list[tuple[str, Path]] = []
    for i, off in enumerate(offsets):
        if off <= 0:
            continue
        name, walls, objs = read_level(gamemaps, off, rlew_tag)
        print(f"{i:02d} {name}")
        rng = random.Random(0x57464F4C ^ (i * 0x9E3779B9))
        blob = convert_level(walls, objs, rng)
        assert len(blob) == 4096
        path = out_dir / sanitize_filename(name, i)
        path.write_bytes(blob)
        written.append((name, path))
    return written


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--shareware",
        type=Path,
        default=root / "shareware",
        help="Directory containing MAPHEAD.WL1 / GAMEMAPS.WL1",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=root / "maps",
        help="Output directory for 4 KB .bin maps",
    )
    args = ap.parse_args(argv)

    written = extract_all(args.shareware, args.out)
    for name, path in written:
        print(f"{path.name:28}  {name}")
    print(f"Wrote {len(written)} maps ({len(written) * 4096} bytes) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
