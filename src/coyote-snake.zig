const std = @import("std");
const ecs = @import("coyote-ecs");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

const World = ecs.World;
const Entity = ecs.Entity;
const Cast = ecs.Cast;
const Systems = ecs.Systems;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const MAX_DIST = 8;
const START_SIZE = 20;
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

    path: std.ArrayList(@Vector(2, f64)) = undefined,
    tails: u32,

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

        var playerPosition = try world.components.create(Components.Position);
        try self.player.attach(playerPosition, Components.Position{.x = 100, .y = 68});

        var playerTexture = try world.components.create(Components.Texture);
        try self.player.attach(playerTexture, Components.Texture{.id = "snake_head", .path = "assets/images/snake_head.png", .resource = try loadTexture(self, "assets/images/snake_head.png")});

        //One component, many entities
        var tailTexture = try world.components.create(Components.Texture);
        var tailResource = try loadTexture(self, "assets/images/snake_body.png");

        //Many entities, many components
        var i: usize = 0;
        while(i < START_SIZE) : (i += 1) {
            var tail = try world.entities.create();
            var component = try world.components.create(Components.Tail);
            var position = try world.components.create(Components.Position);
            try tail.attach(component, Components.Tail{});
            try tail.attach(tailTexture, Components.Texture{.id = "snake_body", .path = "assets/images/snake_body.png", .resource = tailResource});
            try tail.attach(position, Components.Position{.x = 100, .y = 100});
        }
        self.tails = @intCast(u32, i); //Tail count

        //Initialize path
        self.path = std.ArrayList(@Vector(2, f64)).init(allocator);

        //Create tiles
        var cur_x: c_int = 0;
        var cur_y: c_int = 0;
        var grassResource = try loadTexture(self, "assets/images/grass.png");
        while(cur_y < SCREEN_HEIGHT) : (cur_y += TILE_HEIGHT) {
            while(cur_x < SCREEN_WIDTH) : (cur_x += TILE_WIDTH) {
                try addTile(world, "grass", "assets/images/grass.png", grassResource, cur_x, cur_y);
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
                c.SDL_KEYDOWN => {
                    switch(event.key.keysym.sym) {
                        c.SDLK_UP => setDirection(self, .U),
                        c.SDLK_DOWN => setDirection(self, .D),
                        c.SDLK_LEFT => setDirection(self, .L),
                        c.SDLK_RIGHT => setDirection(self, .R),
                        c.SDLK_w => setDirection(self, .U),
                        c.SDLK_s => setDirection(self, .D),
                        c.SDLK_a => setDirection(self, .L),
                        c.SDLK_d => setDirection(self, .R),
                        else => std.log.info("Unhandled key was pressed: {}", .{event.key.keysym.sym}),
                    }
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
        in_motion: bool = false,
        speed: u32 = 128,
        speed_delta: f64 = 0.0,
        direction: Direction = .D,
        time: Time = .{.updated = 0,
                       .delta = 0.0},
    };

    //Empty attribute
    pub const Tail = struct {
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

};

pub const Time = struct {
    updated: u32 = 0,
    delta: f64 = 0.0,
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
    var it = world.components.iteratorFilter(Components.Tile);
    var i: usize = 0;
    while(it.next()) |component| : (i += 1) {
        var data = Cast(Components.Tile, component);
        try renderToTile(game, data.texture.resource, data.x, data.y);
    }

    var player = game.player;

    //Get one
    var texture = Cast(Components.Texture, player.getOneComponent(Components.Texture));
    var position = Cast(Components.Position, player.getOneComponent(Components.Position));

    //Render Tails
    var tails = world.entities.iteratorFilter(Components.Tail);
    while(tails.next()) |tail| {
        var tailTexture = Cast(Components.Texture, tail.getOneComponent(Components.Texture));
        var tailPosition = Cast(Components.Position, tail.getOneComponent(Components.Position));
        try renderToTile(game, tailTexture.resource, @floatToInt(c_int, @round(tailPosition.x)), @floatToInt(c_int, @round(tailPosition.y)));
    }

    //Render Player
    try renderToTile(game, texture.resource, @floatToInt(c_int, @round(position.x)), @floatToInt(c_int, @round(position.y)));

    c.SDL_RenderPresent(game.renderer);
}

pub fn Update(world: *World, game: *Game) !void {
    //Update player entity

    try updateSpaceTime(world);
    try updatePlayer(world, game);
    try updateTail(world, game);
}

//Prefer component iterators to entity
pub inline fn updateSpaceTime(world: *World) !void {
    var it = world.components.iteratorFilter(Components.Position);
    var i: u32 = 0;

    while(it.next()) |component| : (i += 1) {
        if(component.attached) {
            var position = Cast(Components.Position, component);
            var last_update = position.time.updated;
            var delta = @intToFloat(f64, c.SDL_GetTicks() - last_update) / 1000.0;
            var speed_delta = @intToFloat(f64, position.speed) * delta;
            try component.set(Components.Position, .{ .speed_delta = speed_delta, .time = .{.updated = c.SDL_GetTicks(), .delta = delta} });
        }
    }
}

pub inline fn updateSpeed(world: *World, game: *Game) !void {
    var position = Cast(Components.Position, game.player.getOneComponent(Components.Position));
    var time = Cast(Components.Time, game.player.getOneComponent(Components.Time));
    position.speed_delta = @intToFloat(f64, position.speed) * time.delta;
    _ = world;
}

pub inline fn updatePlayer(world: *World, game: *Game) !void {
    var player = game.player;
    var position = Cast(Components.Position, player.getOneComponent(Components.Position));

    switch(position.direction) {
        .U => { position.y -= position.speed_delta; },
        .D => { position.y += position.speed_delta; },
        .L => { position.x -= position.speed_delta; },
        .R => { position.x += position.speed_delta; },
    }

    if(position.y <= 0)
        position.y = 0;

    if(position.x <= 0)
        position.x = 0;

    if(position.x >= SCREEN_WIDTH - TILE_WIDTH)
        position.x = SCREEN_WIDTH - TILE_WIDTH;

    if(position.y >= SCREEN_HEIGHT - TILE_HEIGHT)
        position.y = SCREEN_HEIGHT - TILE_HEIGHT;

    try game.path.append(.{position.x, position.y});
    _ = world;
}

pub inline fn updateTail(world: *World, game: *Game) !void {

    //Iterate through tails
    //Move along path
    var it = world.entities.iteratorFilter(Components.Tail);
    var i: u32 = 0;
    while(it.next()) |tail| : (i += 1) {
        if(game.path.items.len > i) {
            var target = game.path.items[i];
            var position = Cast(Components.Position, tail.getOneComponent(Components.Position));
            position.x = target[0];
            position.y = target[1];
        }
        if(game.path.items.len > game.tails)
            _ = game.path.orderedRemove(0);
    }
}

pub inline fn addTile(world: *World, id: []const u8, path: []const u8, texture: ?*c.SDL_Texture, x: c_int, y: c_int) !void {
    var tile = try world.entities.create();
    var comp = try world.components.create(Components.Tile);
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
    var texture = c.IMG_LoadTexture(game.renderer, @ptrCast([*c]const u8, path)) orelse
    {
        c.SDL_Log("Unable load image: %s", c.SDL_GetError());
        return error.SDL_LoadTextureFailed;
    };

    return texture;
}

pub inline fn distanceTo(self: *Components.Position, x: f64, y: f64) f64 {
    return @sqrt(@exp2(@fabs(x - self.x))) + @exp2((@fabs(y - self.y)));
}

pub inline fn distanceToPosition(self: *Components.Position, other: *Components.Position) f64 {
    return distanceTo(self, other.x, other.y);
}

pub fn moveTowards(self: *Components.Position, target: @Vector(2, f64)) f64 {
    if(self.speed_delta > MAX_DIST)
        self.speed_delta = MAX_DIST;

    if(distanceTo(self, target[0], target[1]) > self.speed_delta) {
        if(self.x < target[0])
            self.x += self.speed_delta;

        if(self.x > target[0])
            self.x -= self.speed_delta;

        if(self.y < target[1])
            self.y += self.speed_delta;

        if(self.y > target[1])
            self.y -= self.speed_delta;
    }
    self.in_motion = true;
    return distanceTo(self, target[0], target[1]);
}

//Good DoD should minimize one-off instructions like this
pub fn setDirection(self: *Game, new_direction: Direction) void {
    var position = Cast(Components.Position, self.player.getOneComponent(Components.Position));
    if(directionPependicularTo(position, new_direction)) {
        position.direction = new_direction;
    }
}

pub fn directionPependicularTo(position: *Components.Position, new_direction: Direction) bool {
    switch(position.direction) {
        .L => {
            switch(new_direction) {
                .U => { return true; },
                .D => { return true; },
                else => {},
            }
        },
        .R => {
            switch(new_direction) {
                .U => { return true; },
                .D => { return true; },
                else => {},
            }
        },
        .U => {
            switch(new_direction) {
                .L => { return true; },
                .R => { return true; },
                else => {},
            }
        },
        .D => {
            switch(new_direction) {
                .L => { return true; },
                .R => { return true; },
                else => {},
            }
        },
    }
    return false;
}