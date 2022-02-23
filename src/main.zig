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

    const grid_size = SnakeGame.Indexer.Bounds{ .w = 10, .h = 10 };
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
    const tick_loop: u64 = 100;

    mainloop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :mainloop,
                else => {},
            }
        }

        if (timer.read() >= 16 * std.time.ns_per_ms) {
            timer.reset();
        } else continue :mainloop;
        tick = (tick + 1) % tick_loop;

        try renderer.setColor(sdl.Color.black);
        try renderer.clear();

        var y: SnakeGame.Indexer.HalfUInt = 0;
        while (y < sg.size.h) : (y += 1) {
            for (sg.getGridRow(y)) |cell, x| {
                const coord: SnakeGame.Indexer.Coord = .{
                    .x = @intCast(SnakeGame.Indexer.HalfUInt, x),
                    .y = y,
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
                    .snake => {
                        try renderer.setColor(sdl.Color.green);
                        try renderer.fillRect(dst_rect);
                    },
                }
            }
        }

        renderer.present();
    }
}
