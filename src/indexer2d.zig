const std = @import("std");
const cardinal = @import("cardinal.zig");

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
            const result = @as(FullUInt, coord.x) + std.math.mulWide(HalfUInt, coord.y, bounds.w);
            return if ((coord.x < bounds.w or coord.y < bounds.h) and result < boundsToLen(bounds))
                result
            else
                error.OutOfBounds;
        }

        pub fn coordToIndexInOrOnBounds(bounds: Bounds, coord: Coord) Error!FullUInt {
            const result = @as(FullUInt, coord.x) + std.math.mulWide(HalfUInt, coord.y, bounds.w);
            return if ((coord.x <= bounds.w or coord.y <= bounds.h) and result <= boundsToLen(bounds))
                result
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

        pub fn directionOffset(direction: cardinal.Direction) Offset {
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
