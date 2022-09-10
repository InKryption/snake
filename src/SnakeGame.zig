const std = @import("std");
const spatial = @import("spatial.zig");

const SnakeGame = @This();
occupants: [*]Occupant,
size: Indexer.Bounds,
snake_head_coord: Indexer.Coord,
snake_tail_coord: Indexer.Coord,

pub const Indexer = struct {
    const int_bits = @bitSizeOf(usize);
    pub const FullUInt = std.meta.Int(.unsigned, int_bits);
    pub const HalfUInt = std.meta.Int(.unsigned, @divExact(int_bits, 2));

    pub const FullSint = std.meta.Int(.signed, int_bits);
    pub const HalfSInt = std.meta.Int(.signed, @divExact(int_bits, 2));

    pub const Bounds = struct {
        w: HalfUInt,
        h: HalfUInt,

        pub fn toLen(bounds: Bounds) FullUInt {
            return boundsToLen(bounds);
        }
    };

    pub const Coord = struct {
        x: HalfUInt,
        y: HalfUInt,

        pub fn toIndexInBounds(coord: Coord, bounds: Bounds) OutOfBounds!FullUInt {
            return coordToIndexInBounds(bounds, coord);
        }

        pub fn toIndexInOrOnBounds(coord: Coord, bounds: Bounds) OutOfBounds!FullUInt {
            return coordToIndexInOrOnBounds(bounds, coord);
        }

        pub fn plusOffsetClamped(coord: Coord, bounds: Bounds, offset: Offset) Coord {
            return coordPlusOffsetClamped(bounds, coord, offset);
        }

        pub fn plusOffsetWrapped(coord: Coord, bounds: Bounds, offset: Offset) Coord {
            return coordPlusOffsetWrapped(bounds, coord, offset);
        }
    };

    pub const Offset = struct {
        x: HalfSInt,
        y: HalfSInt,

        pub fn add(a: Offset, b: Offset) Offset {
            return addOffsets(a, b);
        }
    };

    pub const OutOfBounds = error{OutOfBounds};

    pub fn boundsToLen(bounds: Bounds) FullUInt {
        return std.math.mulWide(HalfUInt, bounds.w, bounds.h);
    }

    fn coordToIndexUnsafe(bounds: Bounds, coord: Coord) FullUInt {
        return @as(FullUInt, coord.x) + std.math.mulWide(HalfUInt, coord.y, bounds.w);
    }

    pub fn coordIsInBounds(bounds: Bounds, coord: Coord) bool {
        return (coord.x < bounds.w and coord.y < bounds.h);
    }

    pub fn coordToIndexInBounds(bounds: Bounds, coord: Coord) OutOfBounds!FullUInt {
        return if (coordIsInBounds(bounds, coord))
            coordToIndexUnsafe(bounds, coord)
        else
            OutOfBounds.OutOfBounds;
    }

    pub fn coordIsInOrOnBounds(bounds: Bounds, coord: Coord) bool {
        return (coord.x <= bounds.w and coord.y <= bounds.h);
    }

    pub fn coordToIndexInOrOnBounds(bounds: Bounds, coord: Coord) OutOfBounds!FullUInt {
        return if (coordIsInOrOnBounds(bounds, coord))
            coordToIndexUnsafe(bounds, coord)
        else
            OutOfBounds.OutOfBounds;
    }

    fn indexToCoordUnsafe(bounds: Bounds, index: FullUInt) Coord {
        return Coord{
            .x = @intCast(HalfUInt, index % bounds.w),
            .y = @intCast(HalfUInt, @divTrunc(index, bounds.w)),
        };
    }

    pub fn indexIsInBounds(bounds: Bounds, index: FullUInt) bool {
        return index < boundsToLen(bounds);
    }

    pub fn indexToCoordInBounds(bounds: Bounds, index: FullUInt) OutOfBounds!Coord {
        return if (indexIsInBounds(bounds, index))
            indexToCoordUnsafe(bounds, index)
        else
            error.OutOfBounds;
    }

    pub fn indexIsInOrOnBounds(bounds: Bounds, index: FullUInt) bool {
        return index <= boundsToLen(bounds);
    }

    pub fn indexToCoordInOrOnBounds(bounds: Bounds, index: FullUInt) OutOfBounds!Coord {
        return if (indexIsInOrOnBounds(bounds, index))
            indexToCoordUnsafe(bounds, index)
        else
            error.OutOfBounds;
    }

    pub fn directionOffset(direction: spatial.Direction) Offset {
        return switch (direction) {
            .north => Offset{ .x = 0, .y = 1 },
            .east => Offset{ .x = 1, .y = 0 },
            .south => Offset{ .x = 0, .y = -1 },
            .west => Offset{ .x = -1, .y = 0 },
        };
    }

    pub fn addOffsets(a: Offset, b: Offset) Offset {
        return Offset{
            .x = a.x + b.x,
            .y = a.y + b.y,
        };
    }

    pub fn coordPlusOffsetClamped(bounds: Bounds, coord: Coord, offset: Offset) Coord {
        return Coord{
            .x = @intCast(HalfUInt, std.math.clamp(@as(FullSint, coord.x) + offset.x, 0, bounds.w)),
            .y = @intCast(HalfUInt, std.math.clamp(@as(FullSint, coord.y) + offset.y, 0, bounds.h)),
        };
    }

    pub fn coordPlusOffsetWrapped(bounds: Bounds, coord: Coord, offset: Offset) Coord {
        return Coord{
            .x = if (offset.x < 0)
                @intCast(HalfUInt, (coord.x + (bounds.w - (@intCast(HalfUInt, -offset.x) % bounds.w))) % bounds.w)
            else
                @intCast(HalfUInt, (coord.x + @intCast(HalfUInt, offset.x)) % bounds.w),
            .y = if (offset.y < 0)
                @intCast(HalfUInt, (coord.y + (bounds.h - (@intCast(HalfUInt, -offset.y) % bounds.h))) % bounds.h)
            else
                @intCast(HalfUInt, (coord.y + @intCast(HalfUInt, offset.y)) % bounds.h),
        };
    }
};

/// Asserts that the legnth of the buffer given is equivalent to the length represented by the size given.
/// Buffer must remain alive for the duration of the life of this snake.
/// Deinitialization not required.
pub fn initBuffer(buffer: []Occupant, size: Indexer.Bounds, head_coord: Indexer.Coord, head_data: SnakeCellData) Indexer.OutOfBounds!SnakeGame {
    std.debug.assert(Indexer.boundsToLen(size) == buffer.len);
    const head_index = try Indexer.coordToIndexInBounds(size, head_coord);

    std.mem.set(Occupant, buffer, .air);
    buffer[head_index] = @unionInit(Occupant, "snake", head_data);

    const tail_coord = Indexer.coordPlusOffsetWrapped(
        size,
        head_coord,
        Indexer.directionOffset(buffer[head_index].snake.direction.reversed()),
    );
    buffer[Indexer.coordToIndexInBounds(size, tail_coord) catch unreachable] = @unionInit(Occupant, "snake", .{
        .direction = buffer[head_index].snake.direction,
        .rotation = null,
    });

    return SnakeGame{
        .occupants = buffer.ptr,
        .size = size,
        .snake_head_coord = head_coord,
        .snake_tail_coord = tail_coord,
    };
}

/// Same as `initBuffer`, but snake spawns at a randomly determined location.
pub fn initBufferRandom(buffer: []Occupant, size: Indexer.Bounds, random: std.rand.Random) Indexer.Error!SnakeGame {
    return try initBuffer(
        buffer,
        size,
        Indexer.Coord{
            .x = random.uintLessThan(Indexer.HalfUInt, size.w),
            .y = random.uintLessThan(Indexer.HalfUInt, size.h),
        },
        SnakeCellData{
            .direction = random.enumValue(spatial.Direction),
            .rotation = if (random.boolean()) random.enumValue(spatial.Rotation) else null,
        },
    );
}

/// Allocates a buffer of the appropriate size.
/// Must be deinitialized with `deinitAllocated`.
pub fn initAlloc(allocator: std.mem.Allocator, size: Indexer.Bounds, head_coord: Indexer.Coord, head_data: SnakeCellData) (std.mem.Allocator.Error || Indexer.OutOfBounds)!SnakeGame {
    const buffer = try allocator.alloc(Occupant, Indexer.boundsToLen(size));
    errdefer allocator.free(buffer);

    return try initBuffer(buffer, size, head_coord, head_data);
}

/// A combination of `initAlloc` and `initRandom`.
/// Must be deinitialized with `deinitAllocated`.
pub fn initAllocRandom(allocator: std.mem.Allocator, size: Indexer.Bounds, random: std.rand.Random) std.mem.Allocator.Error!SnakeGame {
    return initAlloc(
        allocator,
        size,
        Indexer.Coord{
            .x = random.uintLessThan(Indexer.HalfUInt, size.w),
            .y = random.uintLessThan(Indexer.HalfUInt, size.h),
        },
        SnakeCellData{
            .direction = random.enumValue(spatial.Direction),
            .rotation = if (random.boolean()) random.enumValue(spatial.Rotation) else null,
        },
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.OutOfBounds => unreachable,
    };
}

pub fn deinitAllocated(self: SnakeGame, allocator: std.mem.Allocator) void {
    allocator.free(self.getOccupantsSliceMut());
}

pub fn advance(self: *SnakeGame) Event {
    const old_head_coord: Indexer.Coord = self.snake_head_coord;
    const old_tail_coord: Indexer.Coord = self.snake_tail_coord;

    const old_head_data: SnakeCellData = self.getSnakeHeadCell().snake;
    const old_tail_data: SnakeCellData = self.getSnakeTailCell().snake;

    const old_head_direction: spatial.Direction = if (old_head_data.rotation) |r| old_head_data.direction.rotated(r) else old_head_data.direction;
    const old_tail_direction: spatial.Direction = if (old_tail_data.rotation) |r| old_tail_data.direction.rotated(r) else old_tail_data.direction;

    // const dst_head_coord: Indexer.Coord = Indexer.coordPlusOffsetWrapped(self.size, old_head_coord, Indexer.directionOffset(old_head_direction));
    const dst_head_coord: Indexer.Coord = old_head_coord.plusOffsetWrapped(self.size, Indexer.directionOffset(old_head_direction));
    // const dst_tail_coord: Indexer.Coord = Indexer.coordPlusOffsetWrapped(self.size, old_tail_coord, Indexer.directionOffset(old_tail_direction));
    const dst_tail_coord: Indexer.Coord = old_tail_coord.plusOffsetWrapped(self.size, Indexer.directionOffset(old_tail_direction));

    std.debug.assert(self.getOccupant(dst_tail_coord) == .snake);
    switch (self.getOccupant(dst_head_coord)) {
        .food => {},
        .air, .snake => {
            self.getSnakeTailCellPtr().* = .air;
            self.snake_tail_coord = dst_tail_coord;
        },
    }

    const dst_head_old_occupant = self.getOccupant(dst_head_coord);
    switch (dst_head_old_occupant) {
        .snake => {},
        .air, .food => {
            self.snake_head_coord = dst_head_coord;
            self.getSnakeHeadCellPtr().* = @unionInit(Occupant, "snake", .{
                .direction = old_head_direction,
                .rotation = null,
            });
        },
    }

    return switch (dst_head_old_occupant) {
        .air => .move,
        .food => .grow,
        .snake => .{ .collision = .{
            .original_coord = old_head_coord,
            .snake_data = old_head_data,
        } },
    };
}

/// Attempts to spawn food at the given location; if successful, returns a pointer
/// to the cell where the food has been spawned. Otherwise, returns null.
pub fn spawnFoodMaybe(self: *SnakeGame, coord: Indexer.Coord) ?*Occupant {
    const ptr = self.getOccupantPtr(coord);
    switch (ptr.*) {
        .food, .snake => return null,
        .air => {
            ptr.* = .food;
            return ptr;
        },
    }
}
/// Randomly spawns food at some location in the grid, and returns a pointer
/// to the cell where the food has been spawned.
/// Returns null if there are no spaces where food can spawn.
pub fn spawnFoodRandom(self: *SnakeGame, random: std.rand.Random) ?*Occupant {
    blk: for (self.getOccupantsSlice()) |cell| {
        switch (cell) {
            .air => break :blk,
            .food => continue,
            .snake => continue,
        }
    } else return null;

    var ptr: ?*Occupant = null;
    return while (ptr == null) {
        ptr = self.spawnFoodMaybe(.{
            .x = random.uintLessThan(Indexer.HalfUInt, self.size.w),
            .y = random.uintLessThan(Indexer.HalfUInt, self.size.h),
        });
    } else ptr;
}

pub fn getGridRow(self: SnakeGame, y: Indexer.HalfUInt) []const Occupant {
    var copy = self;
    return copy.getGridRowMut(y);
}
pub fn getGridRowMut(self: *SnakeGame, y: Indexer.HalfUInt) []Occupant {
    const start = Indexer.coordToIndexInBounds(self.size, .{ .x = 0, .y = y }) catch unreachable;
    const end = Indexer.coordToIndexInOrOnBounds(self.size, .{ .x = self.size.w, .y = y }) catch unreachable;
    return self.getOccupantsSliceMut()[start..end];
}

pub fn getSnakeHeadCell(self: SnakeGame) Occupant {
    return self.getOccupant(self.snake_head_coord);
}
pub fn getSnakeHeadCellPtr(self: *SnakeGame) *Occupant {
    return self.getOccupantPtr(self.snake_head_coord);
}

pub fn getSnakeTailCell(self: SnakeGame) Occupant {
    return self.getOccupant(self.snake_tail_coord);
}
pub fn getSnakeTailCellPtr(self: *SnakeGame) *Occupant {
    return self.getOccupantPtr(self.snake_tail_coord);
}

pub fn getOccupant(self: SnakeGame, coord: Indexer.Coord) Occupant {
    var copy = self;
    return copy.getOccupantPtr(coord).*;
}
pub fn getOccupantPtr(self: *SnakeGame, coord: Indexer.Coord) *Occupant {
    // const index = Indexer.coordToIndexInBounds(self.size, coord) catch unreachable;
    const index = coord.toIndexInBounds(self.size) catch unreachable;
    return &self.getOccupantsSliceMut()[index];
}

pub fn getOccupantsSlice(self: SnakeGame) []const Occupant {
    var copy = self;
    return copy.getOccupantsSliceMut();
}
pub fn getOccupantsSliceMut(self: SnakeGame) []Occupant {
    return self.occupants[0..self.size.toLen()];
}

pub const Event = union(enum) {
    move,
    grow,
    collision: Collision,
    pub const Collision = struct {
        original_coord: Indexer.Coord,
        snake_data: SnakeCellData,
    };
};

pub const Occupant = union(enum) {
    air,
    food,
    snake: SnakeCellData,
};
pub const SnakeCellData = struct {
    direction: spatial.Direction,
    rotation: ?spatial.Rotation,
};
