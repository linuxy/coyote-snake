const std = @import("std");
const ecs = @import("coyote-ecs");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const World = ecs.World;
const Entity = ecs.Entity;
const Cast = ecs.Cast;
const Systems = ecs.Systems;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const MAX_DIST = 4;
const TILE_WIDTH = 32;
const TILE_HEIGHT = 32;

pub fn main() !void {
    var world = World.create();
    defer world.deinit();

    var game = try Game.init(world);
    defer game.deinit();

    while(game.isRunning) {
        game.handleEvents();
        Systems.run(Update, .{world, game});
        Systems.run(Render, .{world, game});
        c.SDL_Delay(17);
    }
}

pub const Game = struct {
    world: *World,
    player: *Entity,
    tileMap: *Entity,

    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    screenWidth: c_int,
    screenHeight: c_int,
    isRunning: bool,
    
    pub fn init(world: *World) !*Game {
        var self = try allocator.create(Game);
        self.world = world;

        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        self.window = c.SDL_CreateWindow("Another Snake Game", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_OPENGL) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        self.renderer = c.SDL_CreateRenderer(self.window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        self.player = try world.entities.create();
        self.tileMap = try world.entities.create();

        var playerPosition = try world.components.create(Components.Position{});
        try self.player.attach(playerPosition, Components.Position{.x = 100, .y = 100});

        var playerTexture = try world.components.create(Components.Texture{});
        try self.player.attach(playerTexture, Components.Texture{.id = "snake_head", .path = "assets/images/snake_head.bmp"});

        self.isRunning = true;

        return self;
    }

    pub fn handleEvents(self: *Game) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    self.isRunning = false;
                },
                else => {},
            }
        }
    }

    pub fn deinit(self: *Game) void {
        self.isRunning = false;
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        c.SDL_Quit();
        defer allocator.destroy(self);
        //Segfault for some reason on exit
    }
};

//Components
pub const Components = struct {

    pub const Position = struct {
        x: f64 = 0.0,
        y: f64 = 0.0,
        speed: u32 = 128,
        direction: Direction = .D,
    };

    pub const Tail = struct {
        next: ?*Tail = null,
        last: ?*Tail = null,
    };

    pub const Texture = struct {
        id: []const u8 = "",
        path: []const u8 = "",
    };

    pub const Tile = struct {
        width: u32,
        height: u32,
    };

    pub const Time = struct {
        updated: u32 = 0,
        delta: f64 = 0.0,
    };

};

pub const Direction = enum {
    U,
    D,
    L,
    R
};

//Systems
pub fn Render(world: *World, game: *Game) !void {
    //Render TileMap entities
    _ = world;
    _ = game;
    //Render Player and Tail entities
}

pub fn Update(world: *World, game: *Game) !void {
    //Update player entity
    _ = world;
    _ = game;
    //Update tail entities
}

pub inline fn render(game: *Game, id: []const u8, x: c_int, y: c_int) !void {
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

    if(c.SDL_RenderCopyEx(game.renderer, game.tiles.get(id).?, &src_rect, &dest_rect, 0, 0, c.SDL_FLIP_NONE) != 0) {
        c.SDL_Log("Unable to render copy: %s", c.SDL_GetError());
        return error.SDL_RenderCopyExFailed;
    }
}