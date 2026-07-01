const std = @import("std");
const ecs = @import("coyote-ecs");
const c = @import("sdl");

const World = ecs.World;
const Entity = ecs.Entity;
const Component = ecs.Component;
const Cast = ecs.Cast;
const SystemContext = ecs.SystemContext;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const START_SIZE = 20;
const TILE_WIDTH = 32;
const TILE_HEIGHT = 32;
const GRID_COLS = SCREEN_WIDTH / TILE_WIDTH;
const GRID_ROWS = SCREEN_HEIGHT / TILE_HEIGHT;
const MAX_APPLES = 5;
const BASE_SPEED: u32 = 128;
const SPEED_PER_APPLE: u32 = 12;
const MAX_SPEED: u32 = 320;

pub fn main() !void {
    var world = try World.create();
    defer world.destroy();

    const initial_game = try Game.init(world);
    try world.insertResource(Game, initial_game);

    var sched = world.scheduler();
    defer sched.deinit();

    try sched.addSystem(0, Input);
    try sched.addSystem(1, MoveSnake);
    try sched.addSystem(1, EatApple);
    try sched.addSystem(2, SpawnApple);
    try sched.addSystem(3, Render);

    while (world.getResource(Game).?.isRunning) {
        try sched.run();
        c.SDL_Delay(1);
    }

    if (world.getResource(Game)) |g| g.deinit();
    world.removeResource(Game);
}

pub const Game = struct {
    player: *Entity,

    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    tails: u32,
    tailResource: ?*c.SDL_Texture,
    appleResource: ?*c.SDL_Texture,
    grassResource: ?*c.SDL_Texture,
    rng: std.Random.DefaultPrng,

    last_move_ms: u32,
    isRunning: bool,

    pub fn init(world: *World) !Game {
        var self: Game = .{
            .player = undefined,
            .window = null,
            .renderer = null,
            .tails = 0,
            .tailResource = null,
            .appleResource = null,
            .grassResource = null,
            .rng = undefined,
            .last_move_ms = 0,
            .isRunning = false,
        };

        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        errdefer c.SDL_Quit();
        self.rng = std.Random.DefaultPrng.init(c.SDL_GetTicks());

        self.window = c.SDL_CreateWindow("Another Snake Game", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_OPENGL) orelse {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        errdefer c.SDL_DestroyWindow(self.window);

        self.renderer = c.SDL_CreateRenderer(self.window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        errdefer c.SDL_DestroyRenderer(self.renderer);

        self.grassResource = try loadTexture(&self, "assets/images/grass.png");
        self.tailResource = try loadTexture(&self, "assets/images/snake_body.png");
        self.appleResource = try loadTexture(&self, "assets/images/apple.png");

        self.player = try world.entities.create();

        const playerPosition = try world.components.create(Components.Position);
        try self.player.attach(playerPosition, Components.Position{ .x = 96, .y = 64 });

        const playerTexture = try world.components.create(Components.Texture);
        try self.player.attach(playerTexture, Components.Texture{
            .id = "snake_head",
            .path = "assets/images/snake_head.png",
            .resource = try loadTexture(&self, "assets/images/snake_head.png"),
        });

        const tailTexture = try world.components.create(Components.Texture);

        var i: usize = 0;
        while (i < START_SIZE) : (i += 1) {
            const tail = try world.entities.create();
            const component = try world.components.create(Components.Tail);
            const position = try world.components.create(Components.Position);
            try tail.attach(component, Components.Tail{ .segment = @intCast(i) });
            try tail.attach(tailTexture, Components.Texture{
                .id = "snake_body",
                .path = "assets/images/snake_body.png",
                .resource = self.tailResource,
            });
            try tail.attach(position, Components.Position{
                .x = 96 - @as(f64, @floatFromInt(@as(i32, @intCast(i + 1)) * TILE_WIDTH)),
                .y = 64,
            });
        }
        self.tails = @intCast(i);
        self.last_move_ms = c.SDL_GetTicks();
        self.isRunning = true;

        var apple_i: u32 = 0;
        while (apple_i < MAX_APPLES) : (apple_i += 1) {
            try spawnAppleEntity(world, &self);
        }

        return self;
    }

    pub fn deinit(self: *Game) void {
        self.isRunning = false;
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        c.SDL_Quit();
    }
};

fn getGame(ctx: *SystemContext) ?*Game {
    return ctx.resource(Game);
}

pub fn Input(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.@"type") {
            c.SDL_QUIT => g.isRunning = false,
            c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                c.SDLK_UP, c.SDLK_w => setDirection(g, .U),
                c.SDLK_DOWN, c.SDLK_s => setDirection(g, .D),
                c.SDLK_LEFT, c.SDLK_a => setDirection(g, .L),
                c.SDLK_RIGHT, c.SDLK_d => setDirection(g, .R),
                else => {},
            },
            else => {},
        }
    }
}

fn moveIntervalMs(speed: u32) u32 {
    return @max(40, 16000 / speed);
}

// Stage 1: move the snake one grid tile when its move timer elapses.
pub fn MoveSnake(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    if (!g.isRunning) return;

    const world = ctx.world;
    const head = g.player.get(Components.Position) orelse return;
    const now = c.SDL_GetTicks();

    if (now - g.last_move_ms < moveIntervalMs(head.speed)) return;
    g.last_move_ms = now;

    var prev_x = head.x;
    var prev_y = head.y;

    switch (head.direction) {
        .U => head.y -= TILE_HEIGHT,
        .D => head.y += TILE_HEIGHT,
        .L => head.x -= TILE_WIDTH,
        .R => head.x += TILE_WIDTH,
    }

    if (headOutOfBounds(head.x, head.y)) {
        g.isRunning = false;
        std.log.info("Game over: hit the wall", .{});
        return;
    }

    var seg: u32 = 0;
    while (seg < g.tails) : (seg += 1) {
        const tail = findTailBySegment(world, seg) orelse continue;
        const pos = tail.get(Components.Position) orelse continue;
        const next_x = prev_x;
        const next_y = prev_y;
        prev_x = pos.x;
        prev_y = pos.y;
        pos.x = next_x;
        pos.y = next_y;
    }
}

pub fn EatApple(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    if (!g.isRunning) return;

    const world = ctx.world;
    const head = g.player.get(Components.Position) orelse return;

    var eaten_apple: ?*Entity = null;

    var it = world.entities.iteratorFilter(Components.Apple);
    while (it.next()) |apple| {
        const pos = apple.get(Components.Position) orelse continue;
        if (!positionsOverlap(head.x, head.y, pos.x, pos.y)) continue;
        eaten_apple = apple;
        break;
    }

    const apple = eaten_apple orelse return;
    const tail_pos = lastTailPosition(world, head.x, head.y);

    apple.destroy();

    const tail = try world.entities.create();
    const tail_marker = try world.components.create(Components.Tail);
    const tail_position = try world.components.create(Components.Position);
    const tail_texture = try world.components.create(Components.Texture);
    try tail.attach(tail_marker, Components.Tail{ .segment = g.tails });
    try tail.attach(tail_position, Components.Position{
        .x = tail_pos.x,
        .y = tail_pos.y,
    });
    try tail.attach(tail_texture, Components.Texture{
        .id = "snake_body",
        .path = "assets/images/snake_body.png",
        .resource = g.tailResource,
    });

    g.tails += 1;
    acceleratePlayer(g);
}

fn acceleratePlayer(g: *Game) void {
    const position = g.player.get(Components.Position) orelse return;
    position.speed = @min(position.speed + SPEED_PER_APPLE, MAX_SPEED);
}

pub fn SpawnApple(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    const world = ctx.world;

    var apple_count: u32 = 0;
    var it = world.entities.iteratorFilter(Components.Apple);
    while (it.next()) |_| apple_count += 1;

    while (apple_count < MAX_APPLES) {
        const cell = randomOpenCell(g, world) orelse break;
        const deferred = try ctx.commands.createEntity();
        try ctx.commands.attachDeferred(deferred, Components.Apple{});
        try ctx.commands.attachDeferred(deferred, Components.Position{
            .x = cell.x,
            .y = cell.y,
        });
        try ctx.commands.attachDeferred(deferred, Components.Texture{
            .id = "apple",
            .path = "assets/images/apple.png",
            .resource = g.appleResource,
        });
        apple_count += 1;
    }
}

pub fn Render(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    const world = ctx.world;

    _ = c.SDL_RenderClear(g.renderer);
    _ = c.SDL_SetRenderDrawColor(g.renderer, 255, 255, 255, 255);

    var y: c_int = 0;
    while (y < SCREEN_HEIGHT) : (y += TILE_HEIGHT) {
        var x: c_int = 0;
        while (x < SCREEN_WIDTH) : (x += TILE_WIDTH) {
            try renderToTile(g, g.grassResource, x, y);
        }
    }

    var apples = world.entities.iteratorFilter(Components.Apple);
    while (apples.next()) |apple| {
        const texture = apple.get(Components.Texture) orelse continue;
        const position = apple.get(Components.Position) orelse continue;
        try renderToTile(g, texture.resource, @intFromFloat(position.x), @intFromFloat(position.y));
    }

    var tails = world.entities.iteratorFilter(Components.Tail);
    while (tails.next()) |tail| {
        const tailTexture = tail.get(Components.Texture).?;
        const tailPosition = tail.get(Components.Position).?;
        try renderToTile(g, tailTexture.resource, @intFromFloat(tailPosition.x), @intFromFloat(tailPosition.y));
    }

    const texture = g.player.get(Components.Texture).?;
    const position = g.player.get(Components.Position).?;
    try renderToTile(g, texture.resource, @intFromFloat(position.x), @intFromFloat(position.y));

    c.SDL_RenderPresent(g.renderer);
}

pub const Components = struct {
    pub const Position = struct {
        x: f64 = 0.0,
        y: f64 = 0.0,
        speed: u32 = BASE_SPEED,
        direction: Direction = .R,
    };

    pub const Tail = struct {
        segment: u32 = 0,
    };
    pub const Apple = struct {};

    pub const Texture = struct {
        id: []const u8 = "",
        path: []const u8 = "",
        resource: ?*c.SDL_Texture = null,
    };
};

pub const Direction = enum {
    U,
    D,
    L,
    R,
};

const GridCell = struct { col: c_int, row: c_int };
const GridPoint = struct { x: f64, y: f64 };

fn gridCellFromPixels(x: f64, y: f64) GridCell {
    return .{
        .col = @divFloor(@as(c_int, @intFromFloat(x)), TILE_WIDTH),
        .row = @divFloor(@as(c_int, @intFromFloat(y)), TILE_HEIGHT),
    };
}

fn pixelsFromGridCell(cell: GridCell) GridPoint {
    return .{
        .x = @as(f64, @floatFromInt(cell.col * TILE_WIDTH)),
        .y = @as(f64, @floatFromInt(cell.row * TILE_HEIGHT)),
    };
}

fn cellsEqual(a: GridCell, b: GridCell) bool {
    return a.col == b.col and a.row == b.row;
}

fn headOutOfBounds(x: f64, y: f64) bool {
    return x < 0 or y < 0 or
        x + @as(f64, @floatFromInt(TILE_WIDTH)) > SCREEN_WIDTH or
        y + @as(f64, @floatFromInt(TILE_HEIGHT)) > SCREEN_HEIGHT;
}

fn positionsOverlap(ax: f64, ay: f64, bx: f64, by: f64) bool {
    return gridCellFromPixels(ax, ay).col == gridCellFromPixels(bx, by).col and
        gridCellFromPixels(ax, ay).row == gridCellFromPixels(bx, by).row;
}

fn findTailBySegment(world: *World, segment: u32) ?*Entity {
    var it = world.entities.iteratorFilter(Components.Tail);
    while (it.next()) |tail| {
        if (tail.get(Components.Tail)) |data| {
            if (data.segment == segment) return tail;
        }
    }
    return null;
}

fn lastTailPosition(world: *World, head_x: f64, head_y: f64) struct { x: f64, y: f64 } {
    var last_x = head_x;
    var last_y = head_y;
    var last_segment: u32 = 0;

    var tails = world.entities.iteratorFilter(Components.Tail);
    while (tails.next()) |tail| {
        if (tail.get(Components.Tail)) |data| {
            if (tail.get(Components.Position)) |pos| {
                if (data.segment >= last_segment) {
                    last_segment = data.segment;
                    last_x = pos.x;
                    last_y = pos.y;
                }
            }
        }
    }
    return .{ .x = last_x, .y = last_y };
}

fn isCellOccupied(g: *Game, world: *World, cell: GridCell) bool {
    if (g.player.get(Components.Position)) |pos| {
        if (cellsEqual(gridCellFromPixels(pos.x, pos.y), cell)) return true;
    }

    var tails = world.entities.iteratorFilter(Components.Tail);
    while (tails.next()) |tail| {
        if (tail.get(Components.Position)) |pos| {
            if (cellsEqual(gridCellFromPixels(pos.x, pos.y), cell)) return true;
        }
    }

    var apples = world.entities.iteratorFilter(Components.Apple);
    while (apples.next()) |apple| {
        if (apple.get(Components.Position)) |pos| {
            if (cellsEqual(gridCellFromPixels(pos.x, pos.y), cell)) return true;
        }
    }

    return false;
}

fn randomOpenCell(g: *Game, world: *World) ?GridPoint {
    var attempts: u32 = 0;
    while (attempts < 200) : (attempts += 1) {
        const cell = GridCell{
            .col = @intCast(g.rng.random().intRangeAtMost(u32, 0, GRID_COLS - 1)),
            .row = @intCast(g.rng.random().intRangeAtMost(u32, 0, GRID_ROWS - 1)),
        };
        if (!isCellOccupied(g, world, cell)) return pixelsFromGridCell(cell);
    }
    return null;
}

fn spawnAppleEntity(world: *World, g: *Game) !void {
    const cell = randomOpenCell(g, world) orelse return;
    const apple = try world.entities.create();
    const marker = try world.components.create(Components.Apple);
    const position = try world.components.create(Components.Position);
    const texture = try world.components.create(Components.Texture);
    try apple.attach(marker, Components.Apple{});
    try apple.attach(position, Components.Position{ .x = cell.x, .y = cell.y });
    try apple.attach(texture, Components.Texture{
        .id = "apple",
        .path = "assets/images/apple.png",
        .resource = g.appleResource,
    });
}

fn renderToTile(g: *Game, texture: ?*c.SDL_Texture, x: c_int, y: c_int) !void {
    var src_rect: c.SDL_Rect = undefined;
    var dest_rect: c.SDL_Rect = undefined;

    src_rect.x = 0;
    src_rect.y = 0;
    src_rect.w = TILE_WIDTH;
    src_rect.h = TILE_HEIGHT;

    dest_rect.x = x;
    dest_rect.y = y;
    dest_rect.w = TILE_WIDTH;
    dest_rect.h = TILE_HEIGHT;

    if (c.SDL_RenderCopyEx(g.renderer, texture, &src_rect, &dest_rect, 0, null, c.SDL_FLIP_NONE) != 0) {
        c.SDL_Log("Unable to render copy: %s", c.SDL_GetError());
        return error.SDL_RenderCopyExFailed;
    }
}

fn loadTexture(g: *Game, path: [*:0]const u8) !?*c.SDL_Texture {
    const texture = c.IMG_LoadTexture(g.renderer, path) orelse {
        c.SDL_Log("Unable load image: %s", c.SDL_GetError());
        return error.SDL_LoadTextureFailed;
    };
    return texture;
}

fn setDirection(g: *Game, new_direction: Direction) void {
    const position = g.player.get(Components.Position).?;
    if (directionPependicularTo(position, new_direction)) {
        position.direction = new_direction;
    }
}

fn directionPependicularTo(position: *Components.Position, new_direction: Direction) bool {
    return switch (position.direction) {
        .L, .R => switch (new_direction) {
            .U, .D => true,
            else => false,
        },
        .U, .D => switch (new_direction) {
            .L, .R => true,
            else => false,
        },
    };
}
