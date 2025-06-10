const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const expect = std.testing.expect;

const SPRITE_SZ = 64;
const SPRITE_ROW = 4;
const board_width = 30;
const board_height = 16;
const screenWidth = board_width * 64;
const screenHeight = board_height * 64;
const mine_density = 206;
var dead: bool = false;
var win: bool = false;
var clicked_count: i32 = 0;
var UNCLICKED: rl.Rectangle = undefined;
var FLAG: rl.Rectangle = undefined;

var TILES: rl.Texture = undefined;
var board: [][]Tile = undefined;

const TileType = enum {
    bomb,
    clickedBomb,
    flag,
    crossBomb,
    unclicked,
    clicked,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    pub fn is_number(self: TileType) bool {
        return if (@intFromEnum(self) >= 6) true else false;
    }
};

const Tile = struct {
    pos: rl.Vector2 = undefined,
    idx_pos: rl.Vector2 = undefined,
    typ: TileType = .clicked,
    frameRec: rl.Rectangle = undefined,
    clicked: bool = false,
    flag: bool = false,
    pub fn update_sprite(self: *Tile) void {
        const spriteX = (@mod(@as(i32, @intFromEnum(self.typ)), SPRITE_ROW)) * SPRITE_SZ;
        const spriteY = @divFloor(@as(i32, @intFromEnum(self.typ)), SPRITE_ROW) * SPRITE_SZ;
        self.frameRec = rl.Rectangle.init(@as(f32, @floatFromInt(spriteX)), @as(f32, @floatFromInt(spriteY)), SPRITE_SZ, SPRITE_SZ);
    }

    pub fn show(self: *Tile) void {
        if (self.flag) {
            TILES.drawRec(FLAG, self.pos, .white);
        } else if (self.clicked) {
            TILES.drawRec(self.frameRec, self.pos, .white);
        } else {
            TILES.drawRec(UNCLICKED, self.pos, .white);
        }
    }

    pub fn update(self: *Tile) void {
        if (dead) {
            self.die();
        }
        const mouse_pos = rl.getMousePosition();
        const in_range = self.mouse_in_range(mouse_pos);
        const left_clicked = in_range and rl.isMouseButtonPressed(rl.MouseButton.left);
        const right_clicked = in_range and rl.isMouseButtonPressed(rl.MouseButton.right);
        if (left_clicked) {
            if (self.typ == .bomb and !self.flag) {
                self.explode();
            } else if (self.typ == .clicked and !self.clicked) {
                self.expand_from_here();
            } else if (self.typ.is_number() and self.clicked) {
                self.expand_neighbors();
            } else self.clicked = true;
        } else if (right_clicked and !self.clicked) {
            self.flag = !self.flag;
        }

        self.update_sprite();
    }

    fn explode(self: *Tile) void {
        self.clicked = true;
        dead = true;
        self.typ = .clickedBomb;
    }

    fn expand_from_here(self: *Tile) void {
        std.debug.print("expanding ({d}, {d})\n", .{ self.idx_pos.x, self.idx_pos.y });
        self.clicked = true;
        if (self.typ.is_number()) return;

        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(self.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(self.idx_pos.y)) + dir[1];
            if (x < 0 or x >= board_height or y < 0 or y >= board_width) continue;

            const tile = &board[@intCast(x)][@intCast(y)];
            if ((tile.typ == .clicked or tile.typ.is_number()) and !tile.clicked) {
                tile.expand_from_here();
            }
        }
    }

    fn expand_neighbors(self: *Tile) void {
        std.debug.print("expanding ({d}, {d}) neighbors\n", .{ self.idx_pos.x, self.idx_pos.y });
        self.clicked = true;
        const flag_count = self.count_neighbor(.flag);
        // when expand_neighbors is called, self is guaranteed to be a number tile
        if (flag_count != @as(i32, @intFromEnum(self.typ)) - 5) return;

        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(self.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(self.idx_pos.y)) + dir[1];
            if (x < 0 or x >= board_height or y < 0 or y >= board_width) continue;

            const tile = &board[@intCast(x)][@intCast(y)];
            if (!tile.clicked) {
                if (tile.typ == .clicked) {
                    tile.expand_from_here();
                } else if (tile.typ == .bomb) {
                    if (!tile.flag) tile.explode();
                } else tile.clicked = true;
            }
        }
    }

    fn die(self: *Tile) void {
        self.clicked = true;
        self.update_sprite();
    }

    fn mouse_in_range(self: *Tile, mousePos: rl.Vector2) bool {
        if (mousePos.x >= self.pos.x and mousePos.x < self.pos.x + SPRITE_SZ and mousePos.y >= self.pos.y and mousePos.y < self.pos.y + SPRITE_SZ) {
            return true;
        } else return false;
    }

    pub fn count_neighbor(self: *Tile, target: TileType) i32 {
        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        var count: i32 = 0;
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(self.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(self.idx_pos.y)) + dir[1];
            if (x < 0 or x >= board_height or y < 0 or y >= board_width) continue;

            const tile = board[@intCast(x)][@intCast(y)];
            if (target == .flag and tile.flag) {
                count += 1;
            } else if (tile.typ == target) {
                // std.debug.print("({d}, {d}) thinks ({d}, {d}) is bomb\n", .{ self.idx_pos.x, self.idx_pos.y, x, y });
                count += 1;
            }
        }
        return count;
    }
};

fn new_game() anyerror!void {
    dead = false;
    win = false;
    clicked_count = 0;
    for (board, 0..) |_, i| {
        for (board[i], 0..) |_, j| {
            const pos = rl.Vector2.init(@as(f32, @floatFromInt(SPRITE_SZ * j)), @as(f32, @floatFromInt(SPRITE_SZ * i)));
            // const pos = rl.Vector2.init(@as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)));
            // std.debug.print("tile pos = ({d}, {d})\n", .{ pos.x, pos.y });
            var prng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });
            const rand = prng.random();
            const num = rand.intRangeAtMost(i32, 0, 999);
            const typ: TileType = if (num < mine_density) .bomb else .clicked;
            const idx_pos = rl.Vector2.init(@as(f32, @floatFromInt(i)), @as(f32, @floatFromInt(j)));
            // std.debug.print("tile pos = ({d}, {d})\n", .{ i, j });
            board[i][j] = Tile{
                .pos = pos,
                .typ = typ,
                .idx_pos = idx_pos,
                .clicked = false,
            };
        }
    }

    for (board) |row| {
        for (row) |*tile| {
            if (tile.typ == .bomb) continue;
            const neighbor = tile.count_neighbor(.bomb);
            const typ: TileType = @enumFromInt(neighbor + 5);
            tile.typ = typ;
            tile.update_sprite();
        }
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    UNCLICKED = rl.Rectangle.init(0, 64, SPRITE_SZ, SPRITE_SZ);
    FLAG = rl.Rectangle.init(2 * SPRITE_SZ, 0, SPRITE_SZ, SPRITE_SZ);
    board = try allocator.alloc([]Tile, board_height);
    for (0..board_height) |i| {
        board[i] = try allocator.alloc(Tile, board_width);
    }
    defer allocator.free(board);
    defer for (board) |b| allocator.free(b);

    try new_game();

    rl.initWindow(screenWidth, screenHeight, "raylib-test window");
    defer rl.closeWindow(); // Close window and OpenGL context

    TILES = try rl.loadTexture("assets/tiles.png");
    defer rl.unloadTexture(TILES);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var idx: i32 = 0;
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            try new_game();
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);
        for (board, 0..) |_, i| {
            for (board[i], 0..) |_, j| {
                // std.debug.print("tile pos = ({d}, {d})\n", .{ board[i][j].pos.x, board[i][j].pos.y });
                board[i][j].update();
                board[i][j].show();
            }
        }
        // _ = rg.button(rl.Rectangle.init(100, 100, 64, 64), "0");
        // _ = rg.panel(rl.Rectangle.init(100, 100, 64, 64), "shit");

        idx = @mod((idx + 1), 14);
    }
}
