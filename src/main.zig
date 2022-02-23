const std = @import("std");

const spatial = @import("spatial/spatial.zig");
const SnakeGame = @import("SnakeGame.zig");

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


