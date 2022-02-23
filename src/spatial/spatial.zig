pub const Indexer2d = @import("indexer2d.zig").Indexer2d;

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
                .clockwise => Direction.east,
                .anticlockwise => Direction.west,
            },
            .east => switch (rotation) {
                .clockwise => Direction.south,
                .anticlockwise => Direction.north,
            },
            .south => switch (rotation) {
                .clockwise => Direction.west,
                .anticlockwise => Direction.east,
            },
            .west => switch (rotation) {
                .clockwise => Direction.north,
                .anticlockwise => Direction.south,
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

