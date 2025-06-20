const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const expect = std.testing.expect;

const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});
const z = @import("zgui");

const SPRITE_ROW = 4;
var SPRITE_SZ: usize = 64;
var screenWidth: i32 = 800;
var screenHeight: i32 = 600;
var widgetPortion: f32 = 0.2;
const widgetPadding: i32 = 320;
var scale: f32 = 0.75;
var UNCLICKED: rl.Rectangle = undefined;
var FLAG: rl.Rectangle = undefined;
var CLICKED: rl.Rectangle = undefined;
var CLICKING: rl.Rectangle = undefined;
const defaultSpritePath = "assets/minesweeper-sprite-dark-256.png";

var TILES: rl.Texture = undefined;
// var board: [][]Tile = undefined;

// UI shits, TODO: turn this into a struct probably
var showDebug: bool = false;
var showCustom: bool = false;
var enableTimer: bool = true;
var enableMines: bool = true;
var theme: Theme = .dark;
var customWidth: i32 = 8;
var customHeight: i32 = 8;
var customMines: i32 = 10;
var font: z.Font = undefined;
var preferenceWindow = PreferenceWindow{};

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

const Theme = enum { rtx, light, dark, green, purple, poop, pacman };

const Mode = enum { beginner, intermediate, expert, custom };

const CustomGame = struct {
    width: usize = 8,
    height: usize = 8,
    mines: usize = 10,
};

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
    flag_count: usize = 0,
    easy: bool = false,

    // set the fields, allocates the board
    pub fn init(mode: Mode, allocator: std.mem.Allocator) anyerror!*Game {
        const game = try allocator.create(Game);
        game.setup(mode, .{}, allocator);
        try game.alloc_board();
        return game;
    }

    pub fn setup(self: *Game, mode: Mode, args: CustomGame, allocator: std.mem.Allocator) void {
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
        } else if (mode == .custom) {
            self.board_width = args.width;
            self.board_height = args.height;
            self.mines = @min(args.mines, self.board_height * self.board_width);
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

    pub fn new_game(self: *Game, mode: Mode, args: CustomGame) anyerror!void {
        self.deinit();
        self.setup(mode, args, self.allocator);
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
        try self.generate_mines();

        self.generate_numbers();
        screenWidth = @intCast(self.board_width * SPRITE_SZ);
        screenHeight = @intCast(self.board_height * SPRITE_SZ);
    }

    pub fn generate_mines(self: *Game) anyerror!void {
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
    }

    pub fn generate_numbers(self: *Game) void {
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

    fn move_mine(self: *Game, mine: *Tile) void {
        // moves the mine to the first available slot
        // this is for saving the player when the first click is a mine
        for (self.board) |row| {
            for (row) |*tile| {
                if (tile.typ != .bomb and mine != tile) {
                    const tmp = tile.typ;
                    tile.typ = mine.typ;
                    mine.typ = tmp;
                    return;
                }
            }
        }
    }

    pub fn update(self: *Game) anyerror!void {
        var list = std.ArrayList(*Tile).init(self.allocator);
        defer list.deinit();
        for (self.board, 0..) |_, i| {
            for (self.board[i]) |*tile| {
                if (self.dead) {
                    self.stop_timer();
                    if (tile.flag and tile.typ != .bomb) {
                        // std.debug.print("dead, revealing ({d}, {d})\n", .{ tile.idx_pos.x, tile.idx_pos.y });
                        tile.typ = .crossBomb;
                        tile.flag = !tile.flag;
                        tile.update();
                    }

                    if (tile.typ == .bomb) tile.clicked = true;
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
                            if (!self.started) {
                                self.move_mine(tile);
                                self.generate_numbers();
                                if (tile.typ == .clicked) {
                                    self.expand_from_here(tile);
                                }
                                tile.clicked = true;
                            } else {
                                tile.explode();
                                self.dead = true;
                            }
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

    pub fn get_timer(self: *Game) i64 {
        if (self.finish_time != -1) {
            return self.finish_time - self.start_time;
        } else if (self.started) {
            return std.time.milliTimestamp() - self.start_time;
        } else {
            return 0;
        }
    }

    pub fn show(self: *Game) void {
        var count: usize = 0;
        self.flag_count = 0;
        for (self.board, 0..) |_, i| {
            for (self.board[i]) |*tile| {
                if (tile.clicked and tile.typ != .bomb) {
                    // std.debug.print("({d}, {d}) is clicked and not a bomb\n", .{ tile.idx_pos.x, tile.idx_pos.y });
                    count += 1;
                }
                tile.show();
                // std.debug.print("tile pos = ({d}, {d})\n", .{ board[i][j].pos.x, board[i][j].pos.y });
                if (tile.flag) self.flag_count += 1;
            }
        }
        if (!self.started) {
            self.mark_expand_start();
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
            if ((next.typ == .clicked or next.typ.is_number()) and !next.clicked and !next.flag) {
                self.expand_from_here(next);
            }
        }
    }

    fn mark_expand_start(self: *Game) void {
        // On easy mode, mark the tile that can expand the most tiles when the game hasn't started
        const ret: *Tile = self.find_expand_start() catch &self.board[0][0];
        const tile_pos: rl.Vector2 = rl.Vector2{ .x = ret.pos.x + @as(f32, @floatFromInt(SPRITE_SZ)) / 2, .y = ret.pos.y + @as(f32, @floatFromInt(SPRITE_SZ)) / 2 };
        // std.debug.print("marking ({d}, {d}) to red\n", .{ tile_pos.x, tile_pos.y });
        rl.drawCircleV(tile_pos, 10.0, rl.Color.init(200, 100, 100, 255));
    }

    fn find_expand_start(self: *Game) anyerror!*Tile {
        var idx_max: usize = 0;
        var max: usize = 0;
        var group_of_group: std.ArrayList(std.ArrayList(*Tile)) = std.ArrayList(std.ArrayList(*Tile)).init(self.allocator);
        defer group_of_group.deinit();
        defer for (group_of_group.items) |group| {
            group.deinit();
        };
        var visited: [][]bool = try self.allocator.alloc([]bool, self.board_height);
        for (0..self.board_height) |i| {
            visited[i] = try self.allocator.alloc(bool, self.board_width);
        }
        defer self.allocator.free(visited);
        defer for (0..self.board_height) |i| {
            self.allocator.free(visited[i]);
        };
        // std.debug.print("searching expand groups...\n", .{});
        for (self.board, 0..) |row, j| {
            for (row, 0..) |*tile, i| {
                if ((tile.typ == .clicked or tile.typ.is_number()) and !visited[j][i]) {
                    var group = std.ArrayList(*Tile).init(self.allocator);
                    try self.get_expand_group(tile, &group, &visited);
                    try group_of_group.append(group);
                    if (group.items.len > max) {
                        max = group.items.len;
                        idx_max = group_of_group.items.len - 1;
                    }
                }
            }
        }
        if (group_of_group.items.len == 0) {
            // this should only happen when the board is full of mines
            return &self.board[0][0];
        }

        // TODO: I am not making sure the one is unclicked type
        var ret = group_of_group.items[idx_max].items[0];
        for (group_of_group.items[idx_max].items) |tile| {
            if (tile.typ == .clicked) {
                ret = tile;
            }
        }
        return ret;
    }

    fn get_expand_group(self: *Game, tile: *Tile, dst: *std.ArrayList(*Tile), visited: *[][]bool) anyerror!void {
        // std.debug.print("traversing ({d}, {d}), type = {s}...\n", .{ tile.idx_pos.x, tile.idx_pos.y, @tagName(tile.typ) });
        try dst.append(tile);
        visited.*[@as(usize, @intFromFloat(tile.idx_pos.x))][@as(usize, @intFromFloat(tile.idx_pos.y))] = true;
        if (tile.typ.is_number()) return;

        const direction = [_][2]i8{ [_]i8{ -1, -1 }, [_]i8{ -1, 0 }, [_]i8{ -1, 1 }, [_]i8{ 0, -1 }, [_]i8{ 0, 1 }, [_]i8{ 1, -1 }, [_]i8{ 1, 0 }, [_]i8{ 1, 1 } };
        for (direction) |dir| {
            const x = @as(i32, @intFromFloat(tile.idx_pos.x)) + dir[0];
            const y = @as(i32, @intFromFloat(tile.idx_pos.y)) + dir[1];
            if (x < 0 or x >= self.board_height or y < 0 or y >= self.board_width) continue;
            if (visited.*[@as(usize, @intCast(x))][@as(usize, @intCast(y))]) continue;

            const next = &self.board[@intCast(x)][@intCast(y)];
            if ((next.typ == .clicked or next.typ.is_number())) {
                try self.get_expand_group(next, dst, visited);
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
            TILES.drawRec(CLICKING, self.pos, .white);
        } else {
            TILES.drawRec(UNCLICKED, self.pos, .white);
        }
    }

    pub fn update(self: *Tile) void {
        self.update_sprite(self.typ);
    }

    pub fn update_sprite(self: *Tile, typ: TileType) void {
        // std.debug.print("updating sprite of ({d}, {d}) to {s}\n", .{ self.idx_pos.x, self.idx_pos.y, @tagName(self.typ) });
        const spriteX = (@mod(@as(usize, @intFromEnum(typ)), SPRITE_ROW)) * SPRITE_SZ;
        const spriteY = @divFloor(@as(usize, @intFromEnum(typ)), SPRITE_ROW) * SPRITE_SZ;
        self.frameRec = rl.Rectangle.init(@as(f32, @floatFromInt(spriteX)), @as(f32, @floatFromInt(spriteY)), @as(f32, @floatFromInt(SPRITE_SZ)), @as(f32, @floatFromInt(SPRITE_SZ)));
    }

    fn explode(self: *Tile) void {
        // std.debug.print("({d}, {d}) exploded\n", .{ self.idx_pos.x, self.idx_pos.y });
        self.clicked = true;
        self.typ = .clickedBomb;
        self.update();
    }

    fn mouse_in_range(self: *Tile, mousePos: rl.Vector2) bool {
        const sprite_sz = @as(f32, @floatFromInt(SPRITE_SZ));
        if (!z.isWindowFocused(.{ .any_window = true }) and mousePos.x >= self.pos.x and mousePos.x < self.pos.x + sprite_sz and mousePos.y >= self.pos.y and mousePos.y < self.pos.y + sprite_sz) {
            return true;
        } else return false;
    }
};

pub fn showDebugPanel() void {
    if (z.collapsingHeader("Debug", .{ .default_open = true })) {
        const mousePos = rl.getMousePosition();
        z.textWrapped("Default Mouse Position: ({d:.3}, {d:.3})", .{ mousePos.x, mousePos.y });

        const virtual_mouse = getMousePosition();
        z.textWrapped("Virtual Mouse Position: ({d:.3}, {d:.3})", .{ virtual_mouse.x, virtual_mouse.y });

        const ui_mouse: [2]f32 = z.getMousePos();
        z.textWrapped("ImGui Mouse Position: ({d:.3}, {d:.3})", .{ ui_mouse[0], ui_mouse[1] });
        z.text("Is window focus: {}", .{z.isWindowFocused(.{})});
        z.text("Is any window focus: {}", .{z.isWindowFocused(.{ .any_window = true })});
        z.text("Font size: {d:.1}", .{z.getFontSize()});
        z.text("Scale: {d:.3}", .{scale});
    }
}

pub fn showCustomWindow() bool {
    // z.setNextWindowSize(.{ .w = 200, .h = 100 });
    z.setNextWindowPos(.{ .x = z.getWindowWidth() / 2, .y = z.getWindowHeight() / 2, .cond = .appearing });
    _ = z.begin("Custom Game", .{ .flags = z.WindowFlags{
        .no_resize = true,
        .no_collapse = true,
        .no_docking = true,
        .always_auto_resize = true,
    } });
    defer z.end();
    _ = z.inputInt("Width", .{ .v = &customWidth });
    _ = z.inputInt("Height", .{ .v = &customHeight });
    _ = z.inputInt("Mines", .{ .v = &customMines });
    const confirmed = z.button("Confirm", .{ .h = 30, .w = 100 });
    z.sameLine(.{});
    const canceled = z.button("Cancel", .{ .h = 30, .w = 100 });
    if (canceled or confirmed) {
        showCustom = false;
    }
    return if (confirmed) true else false;
}

pub fn renderUI(game: *Game, allocator: std.mem.Allocator) anyerror!void {
    c.rlImGuiBegin();
    defer c.rlImGuiEnd();
    z.pushFont(font);
    defer z.popFont();

    // _ = z.DockSpaceOverViewport(0, z.getMainViewport(), z.DockNodeFlags{});

    // var open = true;
    // z.setNextWindowCollapsed(.{ .collapsed = true, .cond = .first_use_ever });
    // z.showDemoWindow(&open);

    const screenHeightf: f32 = @floatFromInt(screenHeight);
    const screenWidthf: f32 = @floatFromInt(screenWidth);
    z.setNextWindowPos(.{ .x = screenWidthf * scale, .y = 0 });
    z.setNextWindowSize(.{ .w = widgetPadding, .h = screenHeightf * scale });
    _ = z.begin("Menu", .{ .flags = z.WindowFlags{
        .no_resize = true,
        .no_move = true,
        .menu_bar = true,
        .no_collapse = true,
    } });
    if (z.beginMenuBar()) {
        defer z.endMenuBar();
        if (z.beginMenu("Game", true)) {
            defer z.endMenu();
            if (z.menuItem("New Game", .{ .shortcut = "r" })) {
                try game.new_game(game.mode, .{ .width = game.board_width, .height = game.board_height, .mines = game.mines });
            }
            if (z.menuItem("New Beginner", .{ .shortcut = "1" })) {
                try game.new_game(.beginner, .{});
            }
            if (z.menuItem("New Intermediate", .{ .shortcut = "2" })) {
                try game.new_game(.intermediate, .{});
            }
            if (z.menuItem("New Expert", .{ .shortcut = "3" })) {
                try game.new_game(.expert, .{});
            }
            showCustom = z.menuItem("New Custom", .{ .shortcut = "4" });
            z.separator();
            _ = z.menuItem("Quit", .{ .shortcut = "esc" });
        }
        if (z.beginMenu("Option", true)) {
            defer z.endMenu();
            _ = z.menuItemPtr("Preferences", .{ .selected = &preferenceWindow.show, .shortcut = "Ctrl + ," });
            _ = z.menuItemPtr("Show debug info", .{ .selected = &showDebug });
        }
    }

    if (enableTimer) {
        z.bullet();
        const timer = @as(f64, @floatFromInt(game.get_timer())) / 1000.0;
        z.text("Time: {d:.3}", .{timer});
    }
    if (enableMines) {
        z.bullet();
        z.text("Mines Left: {d}", .{game.mines - game.flag_count});
    }

    if (showCustom) {
        if (showCustomWindow()) {
            try game.new_game(.custom, .{ .width = @as(usize, @intCast(customWidth)), .height = @as(usize, @intCast(customHeight)), .mines = @as(usize, @intCast(customMines)) });
        }
    }
    if (showDebug) {
        showDebugPanel();
    }
    if (preferenceWindow.show) {
        preferenceWindow.showPreferenceWindow();
        if (preferenceWindow.themeChanged) {
            try changeTheme(game, allocator);
        }
    }
    _ = z.end();
}

const PreferenceWindow = struct {
    show: bool = false,
    tabPos: i32 = 1,
    themeChanged: bool = false,
    style_id: i32 = 0,
    uiAlpha: f32 = 1.0,

    pub fn showPreferenceWindow(self: *PreferenceWindow) void {
        z.setNextWindowPos(.{ .x = 100, .y = 50, .cond = .appearing });
        z.setNextWindowSize(.{ .w = 700, .h = 0 });
        _ = z.begin("Preference", .{ .flags = z.WindowFlags{
            .always_auto_resize = true,
            .no_resize = true,
            .no_docking = true,
            .no_collapse = true,
        } });
        defer z.end();

        const leftHeight = 500;
        _ = z.beginChild("left panel", .{
            .w = 150,
            .h = leftHeight,
            .child_flags = .{ .border = true, .auto_resize_x = true, .auto_resize_y = true, .always_auto_resize = true },
        });
        if (z.selectable("Appearance", .{ .selected = self.tabPos == 1 })) self.tabPos = 1;
        if (z.selectable("Tools", .{ .selected = self.tabPos == 2 })) self.tabPos = 2;
        if (z.selectable("Cheat Mode", .{ .selected = self.tabPos == 3 })) self.tabPos = 3;
        z.endChild();

        z.sameLine(.{});

        z.beginGroup();
        _ = z.beginChild("item view", .{ .h = leftHeight - 30, .child_flags = .{
            .auto_resize_x = true,
            .auto_resize_y = true,
            .always_auto_resize = true,
        } });
        switch (self.tabPos) {
            1 => {
                z.separatorText("Game");
                if (z.comboFromEnum("Theme", &theme)) self.themeChanged = true;
                z.textColored(.{ 1.0, 0, 0, 1.0 }, "Warning:", .{});
                z.sameLine(.{});
                z.text(" changing the theme will start a new game", .{});
                z.textColored(.{ 1.0, 0, 0, 1.0 }, "Warning:", .{});
                z.sameLine(.{});
                z.text(" RTX theme has default scale of 0.25", .{});
                var cur: i32 = @as(i32, @intFromFloat(scale / 0.25)) - 1;
                if (z.combo("Game Board Scale", .{
                    .current_item = &cur,
                    .items_separated_by_zeros = "0.25\x000.50\x000.75\x001.00\x001.25\x001.50\x001.75\x002.00\x00",
                })) {
                    const s = @as(f32, @floatFromInt(cur + 1)) * 0.25;
                    scale = s;
                }
                z.separatorText("UI");
                var style = z.getStyle();
                if (z.combo("UI Colors", .{ .current_item = &self.style_id, .items_separated_by_zeros = "Dark\x00Light\x00Classic\x00" })) {
                    switch (self.style_id) {
                        0 => style.setColorsDark(),
                        1 => style.setColorsLight(),
                        2 => style.setColorsClassic(),
                        else => unreachable,
                    }
                }
                if (z.sliderFloat("UI Transparency", .{ .v = &self.uiAlpha, .min = 0.1, .max = 1.0, .cfmt = "%.2f" })) {
                    style.alpha = self.uiAlpha;
                }
            },
            2 => {
                _ = z.checkbox("Enable Timer", .{ .v = &enableTimer });
                _ = z.checkbox("Enable Mines Left", .{ .v = &enableMines });
            },
            3 => {
                z.text("Coming Soon!", .{});
            },
            else => unreachable,
        }
        z.endChild();
        const closed = z.button("Close", .{ .h = 30, .w = 100 });
        if (closed) {
            self.show = false;
        }
        z.endGroup();

        // z.text("originalTheme: {s}, preference.newTheme: {s}", .{ @tagName(originalTheme), @tagName(preference.newTheme) });
    }
};

pub fn changeTheme(game: *Game, allocator: std.mem.Allocator) anyerror!void {
    // the global theme is already set by this point
    preferenceWindow.themeChanged = false;
    unloadSprites();
    switch (theme) {
        .rtx => {
            SPRITE_SZ = 256;
            scale = 0.25;
            try loadSprites("assets/minesweeper-sprite-rtx-1024.png");
        },
        else => {
            SPRITE_SZ = 64;

            // convert enum tag to lowercase string if needed
            const theme_str = @tagName(theme); // this gives "light", "dark", etc.
            const path = try std.fmt.allocPrintZ(allocator, "assets/minesweeper-sprite-{s}-256.png", .{theme_str});
            defer allocator.free(path);

            try loadSprites(path);
        },
    }
    try game.new_game(game.mode, .{
        .width = game.board_width,
        .height = game.board_height,
        .mines = game.mines,
    });
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

pub fn calculateSpritesPos() void {
    const sprite_sz = @as(f32, @floatFromInt(SPRITE_SZ));
    UNCLICKED = rl.Rectangle.init(0, sprite_sz, sprite_sz, sprite_sz);
    FLAG = rl.Rectangle.init(2 * sprite_sz, 0, sprite_sz, sprite_sz);
    CLICKED = rl.Rectangle.init(1 * sprite_sz, 1 * sprite_sz, sprite_sz, sprite_sz);
    CLICKING = rl.Rectangle.init(2 * sprite_sz, 3 * sprite_sz, sprite_sz, sprite_sz);
}

pub fn loadSprites(path: [:0]const u8) anyerror!void {
    TILES = try rl.loadTexture(path);
    calculateSpritesPos();
}

pub fn unloadSprites() void {
    rl.unloadTexture(TILES);
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
    try game.new_game(.expert, .{});
    defer allocator.destroy(game);
    defer game.deinit();

    screenWidth = @intCast(game.board_width * SPRITE_SZ);
    screenHeight = @intCast(game.board_height * SPRITE_SZ);

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = false, .vsync_hint = true });
    rl.initWindow(screenWidth + widgetPadding, screenHeight, "zigsweeper");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTraceLogLevel(.err);

    // TILES = try rl.loadTexture("assets/sprite.png");
    try loadSprites(defaultSpritePath);
    defer unloadSprites();

    rl.setTargetFPS(60); // game to run at 60 frames-per-second
    c.rlImGuiSetup(true);
    z.io.setConfigFlags(z.ConfigFlags{ .dock_enable = true, .viewport_enable = true });
    defer c.rlImGuiShutdown();
    z.initNoContext(allocator);
    defer z.deinitNoContext();
    font = z.io.addFontFromFile("fonts/UbuntuMonoNerdFont-Regular.ttf", 20.0);
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        if (!z.isWindowFocused(.{ .any_window = true })) {
            if (rl.isKeyPressed(rl.KeyboardKey.one)) {
                try game.new_game(.beginner, .{});
            } else if (rl.isKeyPressed(rl.KeyboardKey.two)) {
                try game.new_game(.intermediate, .{});
            } else if (rl.isKeyPressed(rl.KeyboardKey.three)) {
                try game.new_game(.expert, .{});
            } else if (rl.isKeyPressed(rl.KeyboardKey.four)) {
                showCustom = true;
            } else if (rl.isKeyPressed(rl.KeyboardKey.r)) {
                try game.new_game(game.mode, .{ .width = game.board_width, .height = game.board_height, .mines = game.mines });
            }
        }
        if (z.isKeyDown(z.Key.left_ctrl) and z.isKeyDown(z.Key.comma)) {
            preferenceWindow.show = true;
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
        try renderUI(game, allocator);
    }
}
