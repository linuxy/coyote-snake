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
const START_SIZE = 4;
const TILE_WIDTH = 32;
const TILE_HEIGHT = 32;

pub fn main() !void {
    var world = try World.create();
    defer world.deinit();

    var game = try Game.init(world);
    defer game.deinit();

    while(game.isRunning) {
        game.handleEvents();
        try Systems.run(Update, .{world, game});
        try Systems.run(Render, .{world, game});
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

        //One entity, many components
        self.player = try world.entities.create();
        self.tileMap = try world.entities.create();

        var playerPosition = try world.components.create(Components.Position{});
        try self.player.attach(playerPosition, Components.Position{.x = 100, .y = 100});

        var playerTexture = try world.components.create(Components.Texture{});
        try self.player.attach(playerTexture, Components.Texture{.id = "snake_head", .path = "assets/images/snake_head.bmp", .resource = try loadTexture(self, "assets/images/snake_head.bmp")});

        //One component, many entities
        var tailTexture = try world.components.create(Components.Texture{});
        var tailResource = try loadTexture(self, "assets/images/snake_body.bmp");

        //Many entities, many components
        var i: usize = 0;
        while(i < START_SIZE) : (i += 1) {
            var tail = try world.entities.create();
            var comp = try world.components.create(Components.Tail{});
            try tail.attach(comp, Components.Tail{.x = 0.0, .y = 0.0});
            try tail.attach(tailTexture, Components.Texture{.id = "snake_body", .path = "assets/images/snake_body.bmp", .resource = tailResource});
            //std.log.info("setup tail: {*} id: {} comp id: {} comp type: {}", .{self.tails.items[i], self.tails.items[i].id, tailTexture.id, tailTexture.typeId.?});
        }

        //Create tiles
        var cur_x: c_int = 0;
        var cur_y: c_int = 0;
        var grassResource = try loadTexture(self, "assets/images/grass.bmp");
        while(cur_y < SCREEN_HEIGHT) : (cur_y += TILE_HEIGHT) {
            while(cur_x < SCREEN_WIDTH) : (cur_x += TILE_WIDTH) {
                try addTile(world, "grass", "assets/images/grass.bmp", grassResource, cur_x, cur_y);
            }
            cur_x = 0;
        }
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
        x: f64 = 0.0,
        y: f64 = 0.0,
        path: std.ArrayList(@Vector(2, f64)) = std.ArrayList(@Vector(2, f64)).init(allocator),
    };

    pub const Texture = struct {
        id: []const u8 = "",
        path: []const u8 = "",
        resource: ?*c.SDL_Texture = null,
    };

    //Composition
    pub const Tile = struct {
        x: c_int = 0,
        y: c_int = 0,
        texture: Texture = Texture{},
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

    _ = c.SDL_RenderClear(game.renderer);
    _ = c.SDL_SetRenderDrawColor(game.renderer, 255, 255, 255, 255);
    
    //Render tileMap
    var it = world.components.iteratorFilter(Components.Tile{});
    var i: usize = 0;
    while(it.next()) |component| : (i += 1) {
        var data = Cast(Components.Tile).get(component).?;
        try renderToTile(game, data.texture.resource, data.x, data.y);
    }

    var player = game.player;

    //Get one
    var texture = Cast(Components.Texture).get(player.getByComponent(Components.Texture{}).?).?;
    var position = Cast(Components.Position).get(player.getByComponent(Components.Position{}).?).?;

    //Render Player
    try renderToTile(game, texture.resource, @floatToInt(c_int, @round(position.x)), @floatToInt(c_int, @round(position.y)));

    //Render Tails
    var tails = world.entities.iteratorFilter(Components.Tail{});
    while(tails.next()) |tail| {
        var tailTexture = Cast(Components.Texture).get(tail.getByComponent(Components.Texture{}).?).?;
        var tailPosition = Cast(Components.Tail).get(tail.getByComponent(Components.Tail{}).?).?;
        try renderToTile(game, tailTexture.resource, @floatToInt(c_int, @round(tailPosition.x)), @floatToInt(c_int, @round(tailPosition.y)));
    }
    c.SDL_RenderPresent(game.renderer);
}

pub fn Update(world: *World, game: *Game) !void {
    //Update player entity
    _ = world;
    _ = game;
    //Update tail entities
}

pub inline fn addTile(world: *World, id: []const u8, path: []const u8, texture: ?*c.SDL_Texture, x: c_int, y: c_int) !void {
    var tile = try world.entities.create();
    var comp = try world.components.create(Components.Tile{});
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

pub inline fn renderToTile(game: *Game, texture: ?*c.SDL_Texture, x: c_int, y: c_int) !void {
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

    if(c.SDL_RenderCopyEx(game.renderer, texture, &src_rect, &dest_rect, 0, 0, c.SDL_FLIP_NONE) != 0) {
        c.SDL_Log("Unable to render copy: %s", c.SDL_GetError());
        return error.SDL_RenderCopyExFailed;
    }
}

pub inline fn loadTexture(game: *Game, path: []const u8) !?*c.SDL_Texture {
    var tempSurface = c.SDL_LoadBMP(@ptrCast([*c]const u8, path)) orelse
    {
        c.SDL_Log("Unable to load image: %s", c.SDL_GetError());
        return error.SDL_IMG_LoadFailed;
    };

    var texture = c.SDL_CreateTextureFromSurface(game.renderer, tempSurface) orelse
    {
        c.SDL_Log("Unable to create surface: %s", c.SDL_GetError());
        return error.SDL_CreateTextureFromSurfaceFailed;
    };

    c.SDL_FreeSurface(tempSurface);

    return texture;
}