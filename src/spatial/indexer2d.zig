const std = @import("std");
const spatial = @import("spatial.zig");

pub fn Indexer2d(comptime int_bits: u16) type {
    return struct {
        pub const FullUInt = std.meta.Int(.unsigned, int_bits);
        pub const HalfUInt = if (int_bits % 2 == 0) std.meta.Int(.unsigned, @divExact(int_bits, 2)) else Indexer2d(int_bits - 1).HalfUInt;

        pub const FullSint = std.meta.Int(.signed, int_bits);
        pub const HalfSInt = if (int_bits % 2 == 0) std.meta.Int(.signed, @divExact(int_bits, 2)) else Indexer2d(int_bits - 1).HalfSInt;

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
}
