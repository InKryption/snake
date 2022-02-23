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
