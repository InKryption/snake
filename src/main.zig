const std = @import("std");
const sdl = @import("MasterQ32/SDL");

const spatial = @import("spatial.zig");
const SnakeGame = @import("SnakeGame.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng_state = std.rand.RomuTrio.init(seed: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :seed seed;
    });
    const random = prng_state.random();

    const grid_size = SnakeGame.Indexer.Bounds{ .w = 20, .h = 20 };
    const cell_size = SnakeGame.Indexer.Bounds{ .w = 20, .h = 20 };

    var sg = try SnakeGame.initAllocRandom(allocator, grid_size, random);
    defer sg.deinitAllocated(allocator);

    var current_food = sg.spawnFoodRandom(random).?;

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
    const tick_loop: u64 = 10;

    const keyboard = sdl.getKeyboardState();
    const KeyState = struct {
        was_pressed: bool = false,
        is_pressed: bool = false,

        fn justPressed(ks: @This()) bool {
            return !ks.was_pressed and ks.is_pressed;
        }
    };
    var user_key_states = std.EnumArray(spatial.Direction, KeyState).initFill(.{});

    var user_inputs = try std.ArrayList(?spatial.Rotation).initCapacity(allocator, 1024);
    defer user_inputs.deinit();

    mainloop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :mainloop,
                else => {},
            }
        }
        update_user_key_states: {
            var iterator = user_key_states.iterator();
            while (iterator.next()) |entry| {
                entry.value.was_pressed = entry.value.is_pressed;
                entry.value.is_pressed = keyboard.isPressed(switch (entry.key) {
                    .north => .up,
                    .east => .right,
                    .south => .down,
                    .west => .left,
                });
            }
            break :update_user_key_states;
        }
        update_user_inputs: {
            const actual_rot = sg.getSnakeHeadCell().snake.rotation;
            const k = struct {
                fn k(b0: u1, b1: u1, b2: u1) u3 {
                    const Bits = packed struct { b0: u1, b1: u1, b2: u1 };
                    return @bitCast(u3, Bits{ .b0 = b0, .b1 = b1, .b2 = b2 });
                }
            }.k;

            const d_forward = sg.getSnakeHeadCell().snake.direction;
            const d_clockwise = d_forward.rotated(.clockwise);
            const d_anticlockwise = d_forward.rotated(.anticlockwise);

            const b0 = @boolToInt(user_key_states.get(d_forward).justPressed());
            const b1 = @boolToInt(user_key_states.get(d_clockwise).justPressed());
            const b2 = @boolToInt(user_key_states.get(d_anticlockwise).justPressed());

            try user_inputs.insert(0, switch (k(b0, b1, b2)) {
                k(0, 0, 0) => break :update_user_inputs,
                k(1, 1, 1) => break :update_user_inputs,

                k(1, 0, 0) => null,
                k(0, 1, 0) => .clockwise,
                k(0, 0, 1) => .anticlockwise,

                k(0, 1, 1) => if (actual_rot) |rot| rot.reversed() else null,
                k(1, 0, 1) => @as(?spatial.Rotation, switch (actual_rot orelse .clockwise) {
                    .clockwise => .anticlockwise,
                    .anticlockwise => null,
                }),
                k(1, 1, 0) => @as(?spatial.Rotation, switch (actual_rot orelse .anticlockwise) {
                    .anticlockwise => .clockwise,
                    .clockwise => null,
                }),
            });
            break :update_user_inputs;
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

        var y: SnakeGame.Indexer.HalfUInt = 0;
        while (y < sg.size.h) : (y += 1) {
            for (sg.getGridRow(y)) |cell, x| {
                const coord: SnakeGame.Indexer.Coord = .{
                    .x = @intCast(SnakeGame.Indexer.HalfUInt, x),
                    .y = sg.size.h - (y + 1),
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
