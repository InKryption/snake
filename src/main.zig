const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var default_prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const random = default_prng.random();

    var sg = try SnakeGame.init(allocator, random, .{ .w = 10, .h = 10 });
    defer sg.deinit();
}

const SnakeGame = struct {
    allocator: std.mem.Allocator,
    grid: OccupantGrid,
    snake_head_cell: *OccupantGrid.Cell,
    snake_tail_cell: *OccupantGrid.Cell,

    pub const OccupantGrid = Grid(Occupant);

    pub fn init(allocator: std.mem.Allocator, random: std.rand.Random, size: OccupantGrid.Indexer.Bounds) !SnakeGame {
        const grid = try OccupantGrid.init(allocator, size, .air);
        errdefer grid.deinit(allocator);

        const snake_head_cell_coord = OccupantGrid.Indexer.Coord{
            .x = random.uintLessThan(OccupantGrid.Indexer.HalfUInt, grid.size.w),
            .y = random.uintLessThan(OccupantGrid.Indexer.HalfUInt, grid.size.h),
        };

        const snake_head_cell: *OccupantGrid.Cell = grid.getPtr(snake_head_cell_coord);
        snake_head_cell.item = @unionInit(Occupant, "snake", .{
            .direction = random.enumValue(Direction),
            .rotation = if (random.boolean()) random.enumValue(Rotation) else null,
        });

        const snake_tail_cell: *OccupantGrid.Cell = grid.getPtr(OccupantGrid.Indexer.coordPlusOffsetWrapped(
            size,
            snake_head_cell_coord,
            OccupantGrid.Indexer.directionOffset(snake_head_cell.item.snake.direction.reversed()),
        ));

        return SnakeGame{
            .allocator = allocator,
            .grid = grid,
            .snake_head_cell = snake_head_cell,
            .snake_tail_cell = snake_tail_cell,
        };
    }

    pub fn deinit(self: SnakeGame) void {
        self.grid.deinit(self.allocator);
    }

    const Occupant = union(enum) {
        air,
        food,
        snake: SnakeCellData,
    };
    const SnakeCellData = struct {
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

pub fn Grid(comptime T: type) type {
    return struct {
        const Self = @This();
        cells: [*]Cell,
        size: Indexer.Bounds,

        pub const Indexer = Indexer2d(@bitSizeOf(usize));

        pub fn init(allocator: std.mem.Allocator, size: Indexer.Bounds, default_value: ?T) std.mem.Allocator.Error!Self {
            var self = Self{
                .cells = (try allocator.alloc(Cell, Indexer.boundsToLen(size))).ptr,
                .size = size,
            };
            errdefer self.deinit(allocator);

            for (self.slice()) |*cell, i| {
                cell.* = .{
                    .neighbors = neighbors: {
                        const coord = Indexer.indexToCoordInBounds(size, i) catch unreachable;
                        // const neighbor_coords: std.EnumArray(Direction, Indexer.Coord) = std.EnumArray(Direction, Indexer.Coord).init(.{
                        //     .north = .{ .x = coord.x, .y = (coord.y + 1) % size.h },
                        //     .south = .{ .x = coord.x, .y = (if (coord.y == 0) size.h else coord.y) - 1 },
                        //     .east = .{ .x = (coord.x + 1) % size.w, .y = coord.y },
                        //     .west = .{ .x = (if (coord.x == 0) size.w else coord.x) - 1, .y = coord.y },
                        // });

                        var neighbors = Cell.Neighbors.initUndefined();
                        var iterator = neighbors.iterator();
                        while (iterator.next()) |entry| {
                            // const index = Indexer.coordToIndexInBounds(size, neighbor_coords.get(entry.key)) catch unreachable;
                            const index = Indexer.coordToIndexInBounds(size, Indexer.coordPlusOffsetWrapped(
                                size,
                                coord,
                                Indexer.directionOffset(entry.key),
                            )) catch unreachable;
                            entry.value.* = &self.slice()[index];
                        }

                        break :neighbors neighbors;
                    },
                    .item = if (default_value) |value| value else undefined,
                };
            }

            return self;
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.cells[0..Indexer.boundsToLen(self.size)]);
        }

        pub fn slice(self: Self) []Cell {
            return self.cells[0..Indexer.boundsToLen(self.size)];
        }

        pub fn getPtr(self: Self, coord: Indexer.Coord) *Cell {
            return &self.slice()[Indexer.coordToIndexInBounds(self.size, coord) catch unreachable];
        }

        pub fn getRow(self: Self, y: Indexer.HalfUInt) []Cell {
            const start = Indexer.coordToIndexInOrOnBounds(self.size, .{ .x = 0, .y = y }) catch unreachable;
            const end = Indexer.coordToIndexInOrOnBounds(self.size, .{ .x = self.size.w, .y = y }) catch unreachable;
            return self.slice()[start..end];
        }

        pub const Cell = struct {
            neighbors: Neighbors,
            item: T,

            pub const Neighbors = std.EnumArray(Direction, *Cell);
        };
    };
}

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
