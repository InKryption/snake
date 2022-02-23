const std = @import("std");
const sdl = @import("MasterQ32/SDL");

const spatial = @import("spatial/spatial.zig");
const SnakeGame = @import("SnakeGame.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var default_prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const random = default_prng.random();

    const grid_size = SnakeGame.Indexer.Bounds{ .w = 5, .h = 5 };
    const cell_size = SnakeGame.Indexer.Bounds{ .w = 50, .h = 50 };
    _ = cell_size;

    var sg = try SnakeGame.initAllocRandom(allocator, grid_size, random);
    defer sg.deinitAllocated(allocator);

    var current_food = sg.spawnFoodRandom(random).?;
    _ = current_food;

    try sdl.init(sdl.InitFlags{ .video = true });
    defer sdl.quit();

    const window = try sdl.createWindow("snake", .default, .default, grid_size.w * cell_size.w, grid_size.h * cell_size.h, sdl.WindowFlags{});
    defer window.destroy();

    const renderer = try sdl.createRenderer(window, null, sdl.RendererFlags{
        .accelerated = true,
    });
    defer renderer.destroy();

    var timer = try std.time.Timer.start();
    var tick: u64 = 0;
    const tick_loop: u64 = 25;

    mainloop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :mainloop,
                .key_down => |info| blk: {
                    if (info.is_repeat) break :blk;
                    if (switch (info.scancode) {
                        .up, .down, .left, .right => false,
                        else => true,
                    }) break :blk;

                    const current_rotation = sg.getSnakeHeadCell().snake.rotation;
                    sg.getSnakeHeadCellPtr().snake.rotation = switch (sg.getSnakeHeadCell().snake.direction) {
                        .north => switch (info.scancode) {
                            .down => null,
                            .up => current_rotation,
                            .left => spatial.Rotation.anticlockwise,
                            .right => spatial.Rotation.clockwise,
                            else => unreachable,
                        },
                        .east => switch (info.scancode) {
                            .down => spatial.Rotation.anticlockwise,
                            .up => spatial.Rotation.clockwise,
                            .left => current_rotation,
                            .right => null,
                            else => unreachable,
                        },
                        .south => switch (info.scancode) {
                            .down => current_rotation,
                            .up => null,
                            .left => spatial.Rotation.clockwise,
                            .right => spatial.Rotation.anticlockwise,
                            else => unreachable,
                        },
                        .west => switch (info.scancode) {
                            .down => spatial.Rotation.clockwise,
                            .up => spatial.Rotation.anticlockwise,
                            .left => null,
                            .right => current_rotation,
                            else => unreachable,
                        },
                    };
                },
                else => {},
            }
        }

        if (timer.read() >= 16 * std.time.ns_per_ms) {
            timer.reset();
        } else continue :mainloop;

        tick = (tick + 1) % tick_loop;
        if (tick == 0) switch (sg.advance()) {
            .move => {},
            .grow => {
                if (current_food.* != .food) {
                    current_food = sg.spawnFoodRandom(random) orelse
                        return std.debug.print("You Win.\n", .{});
                } else unreachable;
            },
            .collision => {
                return std.debug.print("You Lose.\n", .{});
            },
        };

        try renderer.setColor(sdl.Color.black);
        try renderer.clear();

        var y: SnakeGame.Indexer.HalfUInt = sg.size.h;
        while (y > 0) : (y -= 1) {
            for (sg.getGridRow(y - 1)) |cell, x| {
                const coord: SnakeGame.Indexer.Coord = .{
                    .x = @intCast(SnakeGame.Indexer.HalfUInt, x),
                    .y = (y - 1),
                };

                const dst_rect: sdl.Rectangle = .{
                    .x = @intCast(c_int, coord.x * cell_size.w + 1),
                    .y = @intCast(c_int, coord.y * cell_size.h + 1),
                    .width = @intCast(c_int, cell_size.w - 2),
                    .height = @intCast(c_int, cell_size.h - 2),
                };

                switch (cell) {
                    .air => {
                        try renderer.setColor(sdl.Color.white);
                        try renderer.drawRect(dst_rect);
                    },
                    .food => {
                        try renderer.setColor(sdl.Color.red);
                        try renderer.fillRect(dst_rect);
                    },
                    .snake => |data| {
                        try renderer.setColor(sdl.Color.rgb(0, 128, 16));
                        try renderer.fillRect(dst_rect);
                        const k = struct {
                            fn k(d: spatial.Direction, r_or_null: ?spatial.Rotation) u3 {
                                return (@enumToInt(d) + 1) * if (r_or_null) |r|
                                     (@enumToInt(r) + 1)
                                else
                                    (@enumToInt(std.enums.values(spatial.Rotation)[std.enums.values(spatial.Rotation).len - 1]) + 1);
                            }
                        }.k;
                        switch (k(data.direction, data.rotation)) {
                            k(.north, .clockwise) => _,
                        }
                    },
                }
            }
        }

        renderer.present();
    }
}
