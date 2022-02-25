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

pub fn directionPlusOptionalRotation(
    direction: Direction,
    maybe_rotation: ?Rotation,
) DirectionPlusOptionalRotation {
    return DirectionPlusOptionalRotation.from(direction, maybe_rotation);
}

pub const DirectionPlusOptionalRotation = enum {
    north,
    north_clockwise,
    north_anticlockwise,

    east,
    east_clockwise,
    east_anticlockwise,

    south,
    south_clockwise,
    south_anticlockwise,

    west,
    west_clockwise,
    west_anticlockwise,

    pub fn from(d: Direction, maybe_rotation: ?Rotation) DirectionPlusOptionalRotation {
        return if (maybe_rotation) |rotation| switch (d) {
            .north => @as(@This(), switch (rotation) {
                .clockwise => .north_clockwise,
                .anticlockwise => .north_anticlockwise,
            }),
            .east => @as(@This(), switch (rotation) {
                .clockwise => .east_clockwise,
                .anticlockwise => .east_anticlockwise,
            }),
            .south => @as(@This(), switch (rotation) {
                .clockwise => .south_clockwise,
                .anticlockwise => .south_anticlockwise,
            }),
            .west => @as(@This(), switch (rotation) {
                .clockwise => .west_clockwise,
                .anticlockwise => .west_anticlockwise,
            }),
        } else @as(@This(), switch (d) {
            .north => .north,
            .east => .east,
            .south => .south,
            .west => .west,
        });
    }

    pub fn direction(self: DirectionPlusOptionalRotation) Direction {
        return switch (self) {
            .north, .north_clockwise, .north_anticlockwise => .north,

            .east, .east_clockwise, .east_anticlockwise => .east,

            .south, .south_clockwise, .south_anticlockwise => .south,

            .west, .west_clockwise, .west_anticlockwise => .west,
        };
    }
};
