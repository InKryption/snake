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

    var user_inputs = try std.ArrayList(?spatial.Rotation).initCapacity(allocator, 1024);
    defer user_inputs.deinit();

    mainloop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :mainloop,
                .key_down => |info| switch (info.scancode) {
                    .up, .down, .left, .right => if (!info.is_repeat) {
                        try user_inputs.insert(0, switch (sg.getSnakeHeadCell().snake.direction) {
                            .south => @as(?spatial.Rotation, switch (info.scancode) {
                                .up => continue,
                                .right => .anticlockwise,
                                .down => null,
                                .left => .clockwise,
                                else => unreachable,
                            }),
                            .east => @as(?spatial.Rotation, switch (info.scancode) {
                                .up => .clockwise,
                                .left => continue,
                                .down => .anticlockwise,
                                .right => null,
                                else => unreachable,
                            }),
                            .north => @as(?spatial.Rotation, switch (info.scancode) {
                                .up => null,
                                .left => .anticlockwise,
                                .down => continue,
                                .right => .clockwise,
                                else => unreachable,
                            }),
                            .west => @as(?spatial.Rotation, switch (info.scancode) {
                                .up => .anticlockwise,
                                .left => null,
                                .down => .clockwise,
                                .right => continue,
                                else => unreachable,
                            }),
                        });
                    },
                    else => continue,
                },
                else => {},
            }
        }

        if (timer.read() >= 16 * std.time.ns_per_ms) {
            timer.reset();
        } else continue :mainloop;

        tick = (tick + 1) % tick_loop;
        if (tick == 0) {
            if (user_inputs.items.len != 0) {
                sg.getSnakeHeadCellPtr().snake.rotation = user_inputs.pop();
            }
            switch (sg.advance()) {
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
            }
        }

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
                        _ = data;
                        try renderer.setColor(sdl.Color.rgb(0, 156, 0));
                        try renderer.fillRect(dst_rect);
                    },
                }
            }
        }

        renderer.present();
    }
}
