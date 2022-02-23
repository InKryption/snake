const std = @import("std");

const cardinal = @import("cardinal.zig");
const Indexer2d = @import("indexer2d.zig").Indexer2d;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var default_prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const random = default_prng.random();

    var sg = try SnakeGame.initAllocRandom(allocator, .{ .w = 10, .h = 10 }, random);
    defer sg.deinitAllocated(allocator);

    var current_food = sg.spawnFoodRandom(random).?;
    _ = current_food;

    var y: SnakeGame.Indexer.HalfUInt = 0;
    while (y < sg.size.h) : (y += 1) {
        for (sg.getGridRow(y)) |cell| switch (cell) {
            .snake => std.debug.print(" # ", .{}),
            .food => std.debug.print(" O ", .{}),
            .air => std.debug.print(" . ", .{}),
        };
        std.debug.print("\n", .{});
    }
}

const SnakeGame = struct {
    occupants: [*]Occupant,
    size: Indexer.Bounds,
    snake_head_coord: Indexer.Coord,
    snake_tail_coord: Indexer.Coord,

    pub const Indexer = Indexer2d(@bitSizeOf(usize));

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
                .direction = random.enumValue(cardinal.Direction),
                .rotation = if (random.boolean()) random.enumValue(cardinal.Rotation) else null,
            },
        );
    }

    /// Allocates a buffer of the appropriate size.
    /// Must be deinitialized with `deinitAllocated`.
    pub fn initAlloc(allocator: std.mem.Allocator, size: Indexer.Bounds, head_coord: Indexer.Coord, head_data: SnakeCellData) (std.mem.Allocator.Error || Indexer.Error)!SnakeGame {
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
                .direction = random.enumValue(cardinal.Direction),
                .rotation = if (random.boolean()) random.enumValue(cardinal.Rotation) else null,
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

        const old_head_direction: cardinal.Direction = if (old_head_data.rotation) |r| old_head_data.direction.rotated(r) else old_head_data.direction;
        const old_tail_direction: cardinal.Direction = if (old_tail_data.rotation) |r| old_tail_data.direction.rotated(r) else old_tail_data.direction;

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
        direction: cardinal.Direction,
        rotation: ?cardinal.Rotation,
    };
};
