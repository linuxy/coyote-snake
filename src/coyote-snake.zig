const std = @import("std");
const ecs = @import("coyote-ecs");
const c = @import("sdl");

const World = ecs.World;
const Entity = ecs.Entity;
const Cast = ecs.Cast;
const SystemContext = ecs.SystemContext;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const MAX_DIST = 8;
const START_SIZE = 20;
const TILE_WIDTH = 32;
const TILE_HEIGHT = 32;

pub fn main() !void {
    var world = try World.create();
    defer world.destroy();

    const initial_game = try Game.init(world);
    try world.insertResource(Game, initial_game);

    var sched = world.scheduler();
    defer sched.deinit();

    try sched.addSystem(0, Input);
    try sched.addSystem(1, UpdateSpaceTime);
    try sched.addSystem(1, UpdatePlayer);
    try sched.addSystem(1, UpdateTail);
    try sched.addSystem(2, Render);

    while (world.getResource(Game).?.isRunning) {
        try sched.run();
        c.SDL_Delay(17);
    }

    if (world.getResource(Game)) |g| g.deinit();
    world.removeResource(Game);
}

pub const Game = struct {
    player: *Entity,
    tileMap: *Entity,

    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    path: std.ArrayList(@Vector(2, f64)) = .empty,
    tails: u32,

    screenWidth: c_int,
    screenHeight: c_int,
    isRunning: bool,

    pub fn init(world: *World) !Game {
        var self: Game = .{
            .player = undefined,
            .tileMap = undefined,
            .window = null,
            .renderer = null,
            .path = .empty,
            .tails = 0,
            .screenWidth = SCREEN_WIDTH,
            .screenHeight = SCREEN_HEIGHT,
            .isRunning = false,
        };

        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        errdefer c.SDL_Quit();

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

        self.player = try world.entities.create();
        self.tileMap = try world.entities.create();

        const playerPosition = try world.components.create(Components.Position);
        try self.player.attach(playerPosition, Components.Position{ .x = 100, .y = 68 });

        const playerTexture = try world.components.create(Components.Texture);
        try self.player.attach(playerTexture, Components.Texture{
            .id = "snake_head",
            .path = "assets/images/snake_head.png",
            .resource = try loadTexture(&self, "assets/images/snake_head.png"),
        });

        const tailTexture = try world.components.create(Components.Texture);
        const tailResource = try loadTexture(&self, "assets/images/snake_body.png");

        var i: usize = 0;
        while (i < START_SIZE) : (i += 1) {
            const tail = try world.entities.create();
            const component = try world.components.create(Components.Tail);
            const position = try world.components.create(Components.Position);
            try tail.attach(component, Components.Tail{});
            try tail.attach(tailTexture, Components.Texture{
                .id = "snake_body",
                .path = "assets/images/snake_body.png",
                .resource = tailResource,
            });
            try tail.attach(position, Components.Position{ .x = 100, .y = 100 });
        }
        self.tails = @intCast(i);

        var cur_x: c_int = 0;
        var cur_y: c_int = 0;
        const grassResource = try loadTexture(&self, "assets/images/grass.png");
        while (cur_y < SCREEN_HEIGHT) : (cur_y += TILE_HEIGHT) {
            while (cur_x < SCREEN_WIDTH) : (cur_x += TILE_WIDTH) {
                try addTile(world, "grass", "assets/images/grass.png", grassResource, cur_x, cur_y);
            }
            cur_x = 0;
        }
        self.isRunning = true;

        return self;
    }

    pub fn deinit(self: *Game) void {
        self.isRunning = false;
        if (self.path.capacity > 0) self.path.deinit(allocator);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        c.SDL_Quit();
    }
};

fn getGame(ctx: *SystemContext) ?*Game {
    return ctx.resource(Game);
}

// Stage 0: poll SDL events and update input state.
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
                else => std.log.info("Unhandled key was pressed: {}", .{event.key.keysym.sym}),
            },
            else => {},
        }
    }
}

// Stage 1: advance frame timing for all positions.
pub fn UpdateSpaceTime(ctx: *SystemContext) !void {
    const world = ctx.world;
    var it = world.components.iteratorFilter(Components.Position);

    while (it.next()) |component| {
        if (!component.attached) continue;

        const position = Cast(Components.Position, component);
        const last_update = position.time.updated;
        const delta = @as(f64, @floatFromInt(c.SDL_GetTicks() - last_update)) / 1000.0;
        const speed_delta = @as(f64, @floatFromInt(position.speed)) * delta;
        try component.set(Components.Position, .{
            .speed_delta = speed_delta,
            .time = Time{ .updated = c.SDL_GetTicks(), .delta = delta },
        });
    }
}

// Stage 1: move the player and record its path for tail segments.
pub fn UpdatePlayer(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    const position = g.player.get(Components.Position).?;

    switch (position.direction) {
        .U => position.y -= position.speed_delta,
        .D => position.y += position.speed_delta,
        .L => position.x -= position.speed_delta,
        .R => position.x += position.speed_delta,
    }

    if (position.y <= 0) position.y = 0;
    if (position.x <= 0) position.x = 0;
    if (position.x >= SCREEN_WIDTH - TILE_WIDTH) position.x = SCREEN_WIDTH - TILE_WIDTH;
    if (position.y >= SCREEN_HEIGHT - TILE_HEIGHT) position.y = SCREEN_HEIGHT - TILE_HEIGHT;

    try g.path.append(allocator, .{ position.x, position.y });
}

// Stage 1: move tail segments along the recorded path.
pub fn UpdateTail(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    const world = ctx.world;

    var it = world.entities.iteratorFilter(Components.Tail);
    var i: u32 = 0;
    while (it.next()) |tail| : (i += 1) {
        if (g.path.items.len > i) {
            const target = g.path.items[i];
            const position = tail.get(Components.Position).?;
            position.x = target[0];
            position.y = target[1];
        }
        if (g.path.items.len > g.tails)
            _ = g.path.orderedRemove(0);
    }
}

// Stage 2: draw tiles, tails, and the player.
pub fn Render(ctx: *SystemContext) !void {
    const g = getGame(ctx) orelse return;
    const world = ctx.world;

    _ = c.SDL_RenderClear(g.renderer);
    _ = c.SDL_SetRenderDrawColor(g.renderer, 255, 255, 255, 255);

    var it = world.components.iteratorFilter(Components.Tile);
    while (it.next()) |component| {
        const data = Cast(Components.Tile, component);
        try renderToTile(g, data.texture.resource, data.x, data.y);
    }

    const texture = g.player.get(Components.Texture).?;
    const position = g.player.get(Components.Position).?;

    var tails = world.entities.iteratorFilter(Components.Tail);
    while (tails.next()) |tail| {
        const tailTexture = tail.get(Components.Texture).?;
        const tailPosition = tail.get(Components.Position).?;
        try renderToTile(
            g,
            tailTexture.resource,
            @as(c_int, @intFromFloat(@round(tailPosition.x))),
            @as(c_int, @intFromFloat(@round(tailPosition.y))),
        );
    }

    try renderToTile(
        g,
        texture.resource,
        @as(c_int, @intFromFloat(@round(position.x))),
        @as(c_int, @intFromFloat(@round(position.y))),
    );

    c.SDL_RenderPresent(g.renderer);
}

pub const Components = struct {
    pub const Position = struct {
        x: f64 = 0.0,
        y: f64 = 0.0,
        in_motion: bool = false,
        speed: u32 = 128,
        speed_delta: f64 = 0.0,
        direction: Direction = .D,
        time: Time = .{ .updated = 0, .delta = 0.0 },
    };

    pub const Tail = struct {};

    pub const Texture = struct {
        id: []const u8 = "",
        path: []const u8 = "",
        resource: ?*c.SDL_Texture = null,
    };

    pub const Tile = struct {
        x: c_int = 0,
        y: c_int = 0,
        texture: Texture = .{},
    };
};

pub const Time = struct {
    updated: u32 = 0,
    delta: f64 = 0.0,
};

pub const Direction = enum {
    U,
    D,
    L,
    R,
};

fn addTile(world: *World, id: []const u8, path: []const u8, texture: ?*c.SDL_Texture, x: c_int, y: c_int) !void {
    const tile = try world.entities.create();
    const comp = try world.components.create(Components.Tile);
    try tile.attach(comp, Components.Tile{
        .x = x,
        .y = y,
        .texture = Components.Texture{
            .id = id,
            .path = path,
            .resource = texture,
        },
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
