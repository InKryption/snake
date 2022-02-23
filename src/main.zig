const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var default_prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const random = default_prng.random();

    var sg = try SnakeGame.initAllocRandom(allocator, .{ .w = 10, .h = 10 }, random);
    defer sg.deinitAllocated(allocator);
}

const SnakeGame = struct {
    occupants: [*]Occupant,
    size: Indexer.Bounds,
    snake_head_coord: Indexer.Coord,
    snake_tail_coord: Indexer.Coord,

    pub const Indexer = Indexer2d(@bitSizeOf(usize));

    /// A combination of `initAlloc` and `initRandom`.
    /// Must be deinitialized with `deinitAllocated`.
    pub fn initAllocRandom(allocator: std.mem.Allocator, size: Indexer.Bounds, random: std.rand.Random) std.mem.Allocator.Error!SnakeGame {
        return try initAlloc(
            allocator,
            size,
            Indexer.Coord{
                .x = random.uintAtMost(Indexer.HalfUInt, size.w),
                .y = random.uintAtMost(Indexer.HalfUInt, size.h),
            },
            SnakeCellData{
                .direction = random.enumValue(Direction),
                .rotation = if (random.boolean()) random.enumValue(Rotation) else null,
            },
        );
    }

    /// Allocates a buffer of the appropriate size.
    /// Must be deinitialized with `deinitAllocated`.
    pub fn initAlloc(allocator: std.mem.Allocator, size: Indexer.Bounds, head_coord: Indexer.Coord, head_data: SnakeCellData) std.mem.Allocator.Error!SnakeGame {
        const buffer = try allocator.alloc(Occupant, Indexer.boundsToLen(size));
        errdefer allocator.free(buffer);

        return initBuffer(buffer, size, head_coord, head_data) catch unreachable;
    }

    pub fn deinitAllocated(self: SnakeGame, allocator: std.mem.Allocator) void {
        allocator.free(self.getOccupantsSliceMut());
    }

    /// Same as `initBuffer`, but snake spawns at a randomly determined location.
    pub fn initBufferRandom(buffer: []Occupant, size: Indexer.Bounds, random: std.rand.Random) Indexer.Error!SnakeGame {
        return try initBuffer(
            buffer,
            size,
            Indexer.Coord{
                .x = random.uintAtMost(Indexer.HalfUInt, size.w),
                .y = random.uintAtMost(Indexer.HalfUInt, size.h),
            },
            SnakeCellData{
                .direction = random.enumValue(Direction),
                .rotation = if (random.boolean()) random.enumValue(Rotation) else null,
            },
        );
    }

    /// Asserts that the legnth of the buffer given is equivalent to the length represented by the size given.
    /// Buffer must remain alive for the duration of the life of this snake.
    /// Deinitialization not required.
    pub fn initBuffer(buffer: []Occupant, size: Indexer.Bounds, head_coord: Indexer.Coord, head_data: SnakeCellData) Indexer.Error!SnakeGame {
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

    pub fn advance(self: *SnakeGame) Event {
        const old_head_coord: Indexer.Coord = self.snake_head_coord;
        const old_tail_coord: Indexer.Coord = self.snake_tail_coord;

        const old_head_data: SnakeCellData = self.getSnakeHeadCell().snake;
        const old_tail_data: SnakeCellData = self.getSnakeTailCell().snake;

        const old_head_direction: Direction = if (old_head_data.rotation) |r| old_head_data.direction.rotated(r) else old_head_data.direction;
        const old_tail_direction: Direction = if (old_tail_data.rotation) |r| old_tail_data.direction.rotated(r) else old_tail_data.direction;

        const dst_head_coord: Indexer.Coord = Indexer.coordPlusOffsetWrapped(self.size, old_head_coord, Indexer.directionOffset(old_head_direction));
        const dst_tail_coord: Indexer.Coord = Indexer.coordPlusOffsetWrapped(self.size, old_tail_coord, Indexer.directionOffset(old_tail_direction));

        std.debug.assert(self.getOccupant(dst_tail_coord) == .snake);
        switch (self.getOccupant(dst_head_coord)) {
            .food => {},
            .air, .snake => {
                self.getSnakeTailCellPtr().* = .air;
                self.snake_tail_coord = dst_tail_coord;
            },
        }

        switch (self.getOccupant(dst_head_coord)) {
            .snake => {},
            .air, .food => {
                self.snake_head_coord = dst_head_coord;
                self.getSnakeHeadCellPtr().* = @unionInit(Occupant, "snake", .{
                    .direction = old_head_direction,
                    .rotation = null,
                });
            },
        }

        return switch (self.getOccupant(dst_head_coord)) {
            .air => .move,
            .food => .grow,
            .snake => .{ .collision = undefined },
        };
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
        const index = Indexer.coordToIndexInBounds(self.size, coord) catch unreachable;
        return &self.getOccupantsSliceMut()[index];
    }

    pub fn getOccupantsSlice(self: SnakeGame) []const Occupant {
        var copy = self;
        return copy.getOccupantsSliceMut();
    }
    pub fn getOccupantsSliceMut(self: SnakeGame) []Occupant {
        return self.occupants[0..Indexer.boundsToLen(self.size)];
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
        direction: Direction,
        rotation: ?Rotation,
    };
};

pub const Rotation = enum {
    clockwise,
    anticlockwise,
};

pub const Direction = enum {
    north,
    east,
    south,
    west,

    pub fn rotated(direction: Direction, rotation: Rotation) Direction {
        return switch (direction) {
            .north => switch (rotation) {
                .clockwise => .east,
                .anticlockwise => .west,
            },
            .east => switch (rotation) {
                .clockwise => .south,
                .anticlockwise => .north,
            },
            .south => switch (rotation) {
                .clockwise => .west,
                .anticlockwise => .east,
            },
            .west => switch (rotation) {
                .clockwise => .north,
                .anticlockwise => .south,
            },
        };
    }

    pub fn reversed(direction: Direction) Direction {
        return switch (direction) {
            .north => .south,
            .south => .north,
            .east => .west,
            .west => .east,
        };
    }
};

pub fn Indexer2d(comptime int_bits: u16) type {
    return struct {
        pub const FullUInt = std.meta.Int(.unsigned, int_bits);
        pub const HalfUInt = if (int_bits % 2 == 0) std.meta.Int(.unsigned, @divExact(int_bits, 2)) else Indexer2d(int_bits - 1).HalfUInt;

        pub const FullSint = std.meta.Int(.signed, int_bits);
        pub const HalfSInt = if (int_bits % 2 == 0) std.meta.Int(.signed, @divExact(int_bits, 2)) else Indexer2d(int_bits - 1).HalfSInt;

        pub const Bounds = struct { w: HalfUInt, h: HalfUInt };
        pub const Coord = struct { x: HalfUInt, y: HalfUInt };
        pub const Offset = struct { x: HalfSInt, y: HalfSInt };

        pub const Error = error{OutOfBounds};

        pub fn boundsToLen(bounds: Bounds) FullUInt {
            return std.math.mulWide(HalfUInt, bounds.w, bounds.h);
        }

        pub fn coordToIndexInBounds(bounds: Bounds, coord: Coord) Error!FullUInt {
            return if (coord.x < bounds.w or coord.y < bounds.h)
                @as(FullUInt, coord.x) + std.math.mulWide(HalfUInt, coord.y, bounds.w)
            else
                error.OutOfBounds;
        }

        pub fn coordToIndexInOrOnBounds(bounds: Bounds, coord: Coord) Error!FullUInt {
            return if (coord.x <= bounds.w or coord.y <= bounds.h)
                @as(FullUInt, coord.x) + std.math.mulWide(HalfUInt, coord.y, bounds.w)
            else
                error.OutOfBounds;
        }

        pub fn indexToCoordInBounds(bounds: Bounds, index: FullUInt) Error!Coord {
            return if (index < boundsToLen(bounds)) Coord{
                .x = @intCast(HalfUInt, index % bounds.w),
                .y = @intCast(HalfUInt, @divTrunc(index, bounds.w)),
            } else error.OutOfBounds;
        }

        pub fn indexToCoordInOrOnBounds(bounds: Bounds, index: FullUInt) Error!Coord {
            return if (index <= boundsToLen(bounds)) Coord{
                .x = index % bounds.w,
                .y = @divTrunc(index, bounds.w),
            } else error.OutOfBounds;
        }

        pub fn directionOffset(direction: Direction) Offset {
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
}
