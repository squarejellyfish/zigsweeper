const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const expect = std.testing.expect;

const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});
const z = @import("zgui");

const SPRITE_SZ = 64;
const SPRITE_ROW = 4;
var screenWidth: i32 = 800;
var screenHeight: i32 = 600;
var widgetPortion: f32 = 0.2;
const widgetPadding: i32 = 320;
var scale: f32 = 1.0;
var UNCLICKED: rl.Rectangle = undefined;
var FLAG: rl.Rectangle = undefined;
var CLICKED: rl.Rectangle = undefined;

var TILES: rl.Texture = undefined;
// var board: [][]Tile = undefined;

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

const Mode = enum { beginner, intermediate, expert, custom };

const ClickingType = enum { mouse, neighbor, nope };

const Game = struct {
    mode: Mode = .beginner,
    board: [][]Tile,
    board_width: usize = 8,
    board_height: usize = 8,
    mines: usize = 10,
    dead: bool = false,
    win: bool = false,
    clicked_count: usize = 0,
    allocator: std.mem.Allocator,
    start_time: i64,
    finish_time: i64 = -1,
    started: bool = false,

    // set the fields, allocates the board
    pub fn init(mode: Mode, allocator: std.mem.Allocator) anyerror!*Game {
        const game = try allocator.create(Game);
        game.setup(mode, allocator);
        UNCLICKED = rl.Rectangle.init(0, 64, SPRITE_SZ, SPRITE_SZ);
        FLAG = rl.Rectangle.init(2 * SPRITE_SZ, 0, SPRITE_SZ, SPRITE_SZ);
        CLICKED = rl.Rectangle.init(1 * SPRITE_SZ, 1 * SPRITE_SZ, SPRITE_SZ, SPRITE_SZ);
        try game.alloc_board();
        return game;
    }

    pub fn setup(self: *Game, mode: Mode, allocator: std.mem.Allocator) void {
        self.mode = mode;
        self.allocator = allocator;
        self.dead = false;
        self.win = false;
        self.started = false;
        self.finish_time = -1;
        if (mode == .beginner) {
            self.board_width = 8;
            self.board_height = 8;
            self.mines = 10;
        } else if (mode == .intermediate) {
            self.board_width = 16;
            self.board_height = 16;
            self.mines = 40;
        } else if (mode == .expert) {
            self.board_width = 30;
            self.board_height = 16;
            self.mines = 99;
        } else {
            @panic("Custom mode is not implemented yet.");
        }
    }

    pub fn alloc_board(self: *Game) anyerror!void {
        // realloc a new game board
        var new_board = try self.allocator.alloc([]Tile, self.board_height);
        for (0..self.board_height) |i| {
            new_board[i] = try self.allocator.alloc(Tile, self.board_width);
        }
        self.board = new_board;
    }

    pub fn deinit(self: *Game) void {
        for (self.board) |b| self.allocator.free(b);
        self.allocator.free(self.board);
    }

    pub fn new_game(self: *Game, mode: Mode) anyerror!void {
        self.deinit();
        self.setup(mode, self.allocator);
        try self.alloc_board();
        self.clicked_count = 0;
        for (self.board, 0..) |_, i| {
            for (self.board[i], 0..) |_, j| {
                const pos = rl.Vector2.init(@as(f32, @floatFromInt(SPRITE_SZ * j)), @as(f32, @floatFromInt(SPRITE_SZ * i)));
                // const pos = rl.Vector2.init(@as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)));
                // std.debug.print("tile pos = ({d}, {d})\n", .{ pos.x, pos.y });
                const typ: TileType = .clicked;
                const idx_pos = rl.Vector2.init(@as(f32, @floatFromInt(i)), @as(f32, @floatFromInt(j)));
                // std.debug.print("tile pos = ({d}, {d})\n", .{ i, j });
                self.board[i][j] = Tile{
                    .pos = pos,
                    .typ = typ,
                    .idx_pos = idx_pos,
                    .clicked = false,
                };
            }
        }

        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        const rand = prng.random();
        for (0..self.mines) |_| {
            var x = rand.intRangeAtMost(usize, 0, self.board_height - 1);
            var y = rand.intRangeAtMost(usize, 0, self.board_width - 1);
            while (self.board[x][y].typ == .bomb) {
                x = rand.intRangeAtMost(usize, 0, self.board_height - 1);
                y = rand.intRangeAtMost(usize, 0, self.board_width - 1);
            }
            self.board[x][y].typ = .bomb;
        }

        for (self.board) |row| {
            for (row) |*tile| {
                if (tile.typ == .bomb) continue;
                const neighbor = self.count_neighbor(tile, .bomb);
                const typ: TileType = @enumFromInt(neighbor + 5);
                tile.typ = typ;
                tile.update();
            }
        }
    }

    pub fn update(self: *Game) anyerror!void {
        var list = std.ArrayList(*Tile).init(self.allocator);
        defer list.deinit();
        for (self.board, 0..) |_, i| {
            for (self.board[i]) |*tile| {
                if (self.dead) {
                    if (tile.flag and tile.typ != .bomb) {
                        // std.debug.print("dead, revealing ({d}, {d})\n", .{ tile.idx_pos.x, tile.idx_pos.y });
                        tile.typ = .crossBomb;
                        tile.flag = !tile.flag;
                        tile.update();
                    }
                    tile.clicked = true;
                } else if (self.win) {
                    self.stop_timer();
                    if (tile.typ == .bomb and !tile.flag) {
                        // std.debug.print("won, flagging ({d}, {d})\n", .{ tile.idx_pos.x, tile.idx_pos.y });
                        tile.flag = true;
                    }
                } else {
                    const mouse_pos = getMousePosition();
                    const in_range = tile.mouse_in_range(mouse_pos);
                    const right_clicked = in_range and rl.isMouseButtonPressed(rl.MouseButton.right);
                    const left_down = in_range and rl.isMouseButtonDown(rl.MouseButton.left);
                    // const left_up = rl.isMouseButtonUp(rl.MouseButton.left);
                    const left_clicked = in_range and rl.isMouseButtonReleased(rl.MouseButton.left);

                    if (tile.typ.is_number() and tile.clicked) {
                        if (left_down) {
                            list.clearRetainingCapacity();
                            try self.get_neighbors(tile, &list);
                        }
                    } else if (!tile.clicked) {
                        if (left_down) {
                            try list.append(tile);
                        } else tile.clicking = .nope;
                    }

                    if (left_clicked and !tile.flag) {
                        // std.debug.print("clicked ({d}, {d}), type = {s}, clicked_count = {d}\n", .{ tile.idx_pos.x, tile.idx_pos.y, @tagName(tile.typ), self.clicked_count });
                        if (tile.typ == .bomb) {
                            tile.explode();
                            self.dead = true;
                        } else if (tile.typ == .clicked and !tile.clicked) {
                            self.expand_from_here(tile);
                        } else if (tile.typ.is_number() and tile.clicked) {
                            self.expand_neighbors(tile);
                        } else tile.clicked = true;
                        self.start_timer();
                    } else if (right_clicked and !tile.clicked) {
                        tile.flag = !tile.flag;
                        self.start_timer();
                    }

                    tile.update();
                    // tile.show();
                    // std.debug.print("tile pos = ({d}, {d})\n", .{ board[i][j].pos.x, board[i][j].pos.y });
                }
            }
        }

        for (list.items) |tile| {
            tile.clicking = .mouse;
        }
    }

    fn start_timer(self: *Game) void {
        if (!self.started) {
            self.started = true;
            self.start_time = std.time.milliTimestamp();
        }
    }

    fn stop_timer(self: *Game) void {
        if (self.finish_time == -1) {
            self.finish_time = std.time.milliTimestamp();
            const time = @as(f64, @floatFromInt(self.finish_time - self.start_time)) / 1000.0;
            std.debug.print("Finish Time: {d}\n", .{time});
        }
    }

    pub fn show(self: *Game) void {
        var count: usize = 0;
        for (self.board, 0..) |_, i| {
            for (self.board[i]) |*tile| {
                if (tile.clicked and tile.typ != .bomb) {
                    // std.debug.print("({d}, {d}) is clicked and not a bomb\n", .{ tile.idx_pos.x, tile.idx_pos.y });
                    count += 1;
                }
                tile.show();
                // std.debug.print("tile pos = ({d}, {d})\n", .{ board[i][j].pos.x, board[i][j].pos.y });
            }
        }
        if (count == (self.board_height * self.board_width - self.mines)) {
            // std.debug.print("clicked = {d}, won!\n", .{count});
            self.win = true;
        }
        self.clicked_count = count;
    }

    fn count_neighbor(self: *Game, tile: *Tile, target: TileType) i32 {
        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        var count: i32 = 0;
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(tile.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(tile.idx_pos.y)) + dir[1];
            if (x < 0 or x >= self.board_height or y < 0 or y >= self.board_width) continue;

            const next = &self.board[@intCast(x)][@intCast(y)];
            if (target == .flag and next.flag) {
                count += 1;
            } else if (next.typ == target) {
                // std.debug.print("({d}, {d}) thinks ({d}, {d}) is bomb\n", .{ self.idx_pos.x, self.idx_pos.y, x, y });
                count += 1;
            }
        }
        return count;
    }

    fn get_neighbors(self: *Game, tile: *Tile, dst: *std.ArrayListAligned(*Tile, null)) anyerror!void {
        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(tile.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(tile.idx_pos.y)) + dir[1];
            if (x < 0 or x >= self.board_height or y < 0 or y >= self.board_width) continue;

            const next = &self.board[@intCast(x)][@intCast(y)];
            if (!next.clicked) {
                // std.debug.print("setting ({d}, {d}) to {s}\n", .{ next.idx_pos.x, next.idx_pos.y, @tagName(typ) });
                try dst.append(next);
            }
        }
    }

    fn expand_neighbors(self: *Game, tile: *Tile) void {
        // std.debug.print("expanding ({d}, {d}) neighbors\n", .{ tile.idx_pos.x, tile.idx_pos.y });
        tile.clicked = true;
        const flag_count = self.count_neighbor(tile, .flag);
        // when expand_neighbors is called, tile is guaranteed to be a number tile
        if (flag_count != @as(i32, @intFromEnum(tile.typ)) - 5) return;

        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(tile.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(tile.idx_pos.y)) + dir[1];
            if (x < 0 or x >= self.board_height or y < 0 or y >= self.board_width) continue;

            const next = &self.board[@intCast(x)][@intCast(y)];
            if (!next.clicked) {
                if (next.typ == .clicked) {
                    self.expand_from_here(next);
                } else if (next.typ == .bomb) {
                    if (!next.flag) {
                        next.explode();
                        self.dead = true;
                    }
                } else next.clicked = true;
            }
        }
    }

    fn expand_from_here(self: *Game, tile: *Tile) void {
        // std.debug.print("expanding ({d}, {d})\n", .{ tile.idx_pos.x, tile.idx_pos.y });
        tile.clicked = true;
        if (tile.typ.is_number()) return;

        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(tile.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(tile.idx_pos.y)) + dir[1];
            if (x < 0 or x >= self.board_height or y < 0 or y >= self.board_width) continue;

            const next = &self.board[@intCast(x)][@intCast(y)];
            if ((next.typ == .clicked or next.typ.is_number()) and !next.clicked) {
                self.expand_from_here(next);
            }
        }
    }
};

const Tile = struct {
    pos: rl.Vector2 = undefined,
    idx_pos: rl.Vector2 = undefined,
    typ: TileType = .clicked,
    frameRec: rl.Rectangle = undefined,
    clicked: bool = false,
    clicking: ClickingType = .nope,
    flag: bool = false,

    pub fn show(self: *Tile) void {
        if (self.flag) {
            TILES.drawRec(FLAG, self.pos, .white);
        } else if (self.clicked) {
            TILES.drawRec(self.frameRec, self.pos, .white);
        } else if (self.clicking != .nope) {
            TILES.drawRec(CLICKED, self.pos, .white);
        } else {
            TILES.drawRec(UNCLICKED, self.pos, .white);
        }
    }

    pub fn update(self: *Tile) void {
        self.update_sprite(self.typ);
    }

    pub fn update_sprite(self: *Tile, typ: TileType) void {
        // std.debug.print("updating sprite of ({d}, {d}) to {s}\n", .{ self.idx_pos.x, self.idx_pos.y, @tagName(self.typ) });
        const spriteX = (@mod(@as(i32, @intFromEnum(typ)), SPRITE_ROW)) * SPRITE_SZ;
        const spriteY = @divFloor(@as(i32, @intFromEnum(typ)), SPRITE_ROW) * SPRITE_SZ;
        self.frameRec = rl.Rectangle.init(@as(f32, @floatFromInt(spriteX)), @as(f32, @floatFromInt(spriteY)), SPRITE_SZ, SPRITE_SZ);
    }

    fn explode(self: *Tile) void {
        // std.debug.print("({d}, {d}) exploded\n", .{ self.idx_pos.x, self.idx_pos.y });
        self.clicked = true;
        self.typ = .clickedBomb;
        self.update();
    }

    fn mouse_in_range(self: *Tile, mousePos: rl.Vector2) bool {
        if (mousePos.x >= self.pos.x and mousePos.x < self.pos.x + SPRITE_SZ and mousePos.y >= self.pos.y and mousePos.y < self.pos.y + SPRITE_SZ) {
            return true;
        } else return false;
    }
};

pub fn renderUI() void {
    c.rlImGuiBegin();
    defer c.rlImGuiEnd();

    // _ = z.DockSpaceOverViewport(0, z.getMainViewport(), z.DockNodeFlags{});

    // var open = true;
    // z.setNextWindowCollapsed(.{ .collapsed = true, .cond = .first_use_ever });
    // z.showDemoWindow(&open);

    const screenHeightf: f32 = @floatFromInt(screenHeight);
    const screenWidthf: f32 = @floatFromInt(screenWidth);
    z.setNextWindowPos(.{ .x = screenWidthf * scale, .y = 0 });
    z.setNextWindowSize(.{ .w = widgetPadding, .h = screenHeightf * scale });
    z.setNextWindowCollapsed(.{ .collapsed = true, .cond = .first_use_ever });
    _ = z.begin("Debug Mouse", .{});
    if (z.collapsingHeader("Raylib", .{})) {
        const mousePos = rl.getMousePosition();
        z.text("Default Mouse Position: ({d:.3}, {d:.3})", .{ mousePos.x, mousePos.y });

        const virtual_mouse = getMousePosition();
        z.text("Virtual Mouse Position: ({d:.3}, {d:.3})", .{ virtual_mouse.x, virtual_mouse.y });

        const ui_mouse: [2]f32 = z.getMousePos();
        z.text("ImGui Mouse Position: ({d:.3}, {d:.3})", .{ ui_mouse[0], ui_mouse[1] });
        z.text("Scale: {d:.3}", .{scale});
    }
    var cur: i32 = @as(i32, @intFromFloat(scale / 0.25)) - 1;
    if (z.combo("Scaling", .{
        .current_item = &cur,
        .items_separated_by_zeros = "0.25\x000.50\x000.75\x001.00\x001.25\x001.50\x001.75\x002.00\x00",
    })) {
        scale = @as(f32, @floatFromInt(cur + 1)) * 0.25;
    }
    _ = z.end();
}

pub fn getMousePosition() rl.Vector2 {
    const mouse = rl.getMousePosition();
    const screenWidthf: f32 = @floatFromInt(screenWidth);
    const screenHeightf: f32 = @floatFromInt(screenHeight);
    // const virtual_mouse = rl.Vector2{ .x = (mouse.x - (@as(f32, @floatFromInt(rl.getScreenWidth())) - (screenWidthf * scale))) / scale, .y = (mouse.y - (@as(f32, @floatFromInt(rl.getScreenHeight())) - (screenHeightf * scale))) / scale };
    const virtual_mouse = rl.Vector2{ .x = (mouse.x) / scale, .y = (mouse.y) / scale };

    return virtual_mouse.clamp(rl.Vector2{ .x = 0, .y = 0 }, rl.Vector2{ .x = screenWidthf, .y = screenHeightf });
}

pub fn scaleScreenSize() [2]i32 {
    const width: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(screenWidth)) * scale));
    const height: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(screenHeight)) * scale));

    return [2]i32{ width, height };
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    var game = try Game.init(.expert, allocator);
    try game.new_game(.expert);
    defer allocator.destroy(game);
    defer game.deinit();

    screenWidth = @intCast(game.board_width * SPRITE_SZ);
    screenHeight = @intCast(game.board_height * SPRITE_SZ);

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = false, .vsync_hint = true });
    rl.initWindow(screenWidth + widgetPadding, screenHeight, "zigsweeper");
    defer rl.closeWindow(); // Close window and OpenGL context

    TILES = try rl.loadTexture("assets/tiles.png");
    defer rl.unloadTexture(TILES);

    rl.setTargetFPS(60); // game to run at 60 frames-per-second
    c.rlImGuiSetup(true);
    z.io.setConfigFlags(z.ConfigFlags{ .dock_enable = true, .viewport_enable = true });
    defer c.rlImGuiShutdown();
    z.initNoContext(allocator);
    defer z.deinitNoContext();
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        if (rl.isKeyPressed(rl.KeyboardKey.one)) {
            try game.new_game(.beginner);
            screenWidth = @intCast(game.board_width * SPRITE_SZ);
            screenHeight = @intCast(game.board_height * SPRITE_SZ);
        } else if (rl.isKeyPressed(rl.KeyboardKey.two)) {
            try game.new_game(.intermediate);
            screenWidth = @intCast(game.board_width * SPRITE_SZ);
            screenHeight = @intCast(game.board_height * SPRITE_SZ);
        } else if (rl.isKeyPressed(rl.KeyboardKey.three)) {
            try game.new_game(.expert);
            screenWidth = @intCast(game.board_width * SPRITE_SZ);
            screenHeight = @intCast(game.board_height * SPRITE_SZ);
        } else if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            try game.new_game(game.mode);
        }
        const new = scaleScreenSize();
        rl.setWindowSize(new[0] + widgetPadding, new[1]);
        const target: rl.RenderTexture2D = try rl.loadRenderTexture(screenWidth, screenHeight);
        defer rl.unloadRenderTexture(target);
        rl.setTextureFilter(target.texture, .bilinear);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginTextureMode(target);
        try game.update();
        game.show();
        rl.endTextureMode();

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.light_gray);
        const source = rl.Rectangle.init(0.0, 0.0, @as(f32, @floatFromInt(target.texture.width)), @as(f32, @floatFromInt(-target.texture.height)));
        const screenHeightf: f32 = @floatFromInt(screenHeight);
        const screenWidthf: f32 = @floatFromInt(screenWidth);
        // const dest = rl.Rectangle.init(@as(f32, screenWidthf) - screenWidthf * scale, @as(f32, screenHeightf) - screenHeightf * scale, screenWidthf * scale, screenHeightf * scale);
        const dest = rl.Rectangle.init(0, 0, screenWidthf * scale, screenHeightf * scale);
        rl.drawTexturePro(target.texture, source, dest, rl.Vector2{ .x = 0, .y = 0 }, 0.0, .white);

        // const area = rl.Rectangle.init(500, 500, 200, 100);
        // _ = rg.panel(area, "shit");
        // _ = rg.button(rl.Rectangle.init(100, 100, 64, 64), "0");
        // _ = rg.panel(rl.Rectangle.init(100, 100, 64, 64), "shit");
        renderUI();
    }
}
