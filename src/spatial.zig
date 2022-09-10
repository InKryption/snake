const std = @import("std");

pub const Rotation = enum {
    clockwise,
    anticlockwise,

    pub fn reversed(rotation: Rotation) Rotation {
        return switch (rotation) {
            .clockwise => .anticlockwise,
            .anticlockwise => .clockwise,
        };
    }
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

pub const DirectionRotation = enum {
    north_clockwise,
    north_anticlockwise,

    east_clockwise,
    east_anticlockwise,

    south_clockwise,
    south_anticlockwise,

    west_clockwise,
    west_anticlockwise,

    pub fn init(direction: Direction, rotation: Rotation) DirectionRotation {
        const lut_index1: u8 = switch (direction) {
            .north => 0,
            .east => 1,
            .south => 2,
            .west => 3,
        };
        const lut_index2: u8 = switch (rotation) {
            .clockwise => 0,
            .anticlockwise => 1,
        };
        const lut = @bitCast([8]DirectionRotation, [4][2]DirectionRotation{
            // clockwise, anticlockwise
            .{ .north_clockwise, .north_anticlockwise }, // north
            .{ .east_clockwise, .east_anticlockwise }, // east
            .{ .south_clockwise, .south_anticlockwise }, // south
            .{ .west_clockwise, .west_anticlockwise }, // west
        });
        return lut[lut_index1 * 2 + lut_index2];
    }

    pub fn getDirection(dr: DirectionRotation) Direction {
        return switch (dr) {
            .north_clockwise,
            .north_anticlockwise,
            => .north,

            .east_clockwise,
            .east_anticlockwise,
            => .east,

            .south_clockwise,
            .south_anticlockwise,
            => .south,

            .west_clockwise,
            .west_anticlockwise,
            => .west,
        };
    }

    pub fn getRotation(dr: DirectionRotation) Rotation {
        return switch (dr) {
            .north_clockwise,
            .east_clockwise,
            .south_clockwise,
            .west_clockwise,
            => .clockwise,

            .north_anticlockwise,
            .east_anticlockwise,
            .south_anticlockwise,
            .west_anticlockwise,
            => .anticlockwise,
        };
    }
};
