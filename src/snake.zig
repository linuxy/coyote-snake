const std = @import("std");
const ecs = @import("coyote-ecs");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const World = ecs.World;
const Cast = ecs.Cast;
const Systems = ecs.Systems;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;

pub fn main() !void {
    var game = try Game.init();
    defer game.deinit();

    while(game.isRunning) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    game.isRunning = false;
                },
                else => {},
            }
        }
        try game.render();
        c.SDL_Delay(17);
    }
}

pub const Game = struct {
    isRunning: bool,
    player: ?*Player,

    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    screenWidth: c_int,
    screenHeight: c_int,

    tileMap: ?*TileMap,

    pub fn init() !*Game {
        var self = try allocator.create(Game);

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
        
        self.tileMap = try TileMap.init(self.renderer, 32, 32);
        try self.tileMap.?.addTile("assets/images/grass.bmp", "grass");
        try self.tileMap.?.addTile("assets/images/snake_head.bmp", "snake_head");
        try self.tileMap.?.addTile("assets/images/snake_body.bmp", "snake_body");
        self.isRunning = true;

        return self;
    }

    pub fn render(self: *Game) !void {
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        try self.tileMap.?.fillWith("grass", 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
        //player->render();
        c.SDL_RenderPresent(self.renderer);
    }
    pub fn update() void {}
    pub fn handleEvents() void {}

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

pub const GameObject = struct {

    x: f32,
    y: f32,
    last_update: f64,
    time_delta: f64,
    children: std.ArrayList(GameObject),
    texture: []const u8,

    pub fn init(name: []const u8, x: f32, y: f32) *GameObject {
        var self = allocator.create(GameObject);
        self.x = x;
        self.y = y;
        self.texture = name;
        self.children.init(allocator);
        return self;
    }

    pub fn addChild(self: *GameObject, other: *GameObject) !void {
        try self.children.append(other);
    }

    pub fn distanceTo(self: *GameObject, x: f32, y: f32) f32 {
        return @sqrt((self.x - x)^2 + (self.y - y)^2);
    }

    pub fn distanceToObject(self: *GameObject, other: *GameObject) f32 {
        _ = self;
        return distanceTo(other.x, other.y);
    }

    pub fn render(self: *GameObject, game: *Game) void {
        for(self.children.items) |child| {
            child.render();
        }
        game.tileMap.render(self.texture, self.x, self.y);
    }

    pub fn update(self: *GameObject) void {
        if(self.last_update == 0) {
            self.last_update = c.SDL_GetTicks();
        }

        for(self.children.items) |child| {
            child.update();
        }

        var current_time = c.SDL_GetTicks();
        self.time_delta = (current_time - self.last_update) / 1000.0;
        self.last_update = current_time;
    }


};

pub const Player = struct {
    speed: u32 = 128,
    last_node: *TailNode,
    next_node: *TailNode,

    pub fn init(x: u32, y: u32) void {
        _ = x;
        _ = y;
    }

    pub fn update() void {

    }

    pub fn growTail() void {

    }

    pub fn setDirection() void {

    }

    pub fn directionPependicularTo(new_direction: Direction) bool {
        _ = new_direction;
    }
};

pub const TailNode = struct {

};

pub const TileMap = struct {
    renderer: ?*c.SDL_Renderer,
    tileWidth: c_int,
    tileHeight: c_int,
    tiles: std.StringHashMap(?*c.SDL_Texture),

    pub fn init(renderer: ?*c.SDL_Renderer, tileWidth: c_int, tileHeight: c_int) !*TileMap {
        var self = try allocator.create(TileMap);
        self.renderer = renderer;
        self.tileWidth = tileWidth;
        self.tileHeight = tileHeight;
        self.tiles = std.StringHashMap(?*c.SDL_Texture).init(allocator);
        return self;
    }

    pub fn addTile(self: *TileMap, path: []const u8, name: []const u8) !void {
        var tempSurface = c.SDL_LoadBMP(@ptrCast([*c]const u8, path)) orelse
        {
            c.SDL_Log("Unable to load image: %s", c.SDL_GetError());
            return error.SDL_IMG_LoadFailed;
        };

        var texture = c.SDL_CreateTextureFromSurface(self.renderer, tempSurface) orelse
        {
            c.SDL_Log("Unable to create surface: %s", c.SDL_GetError());
            return error.SDL_CreateTextureFromSurfaceFailed;
        };

        c.SDL_FreeSurface(tempSurface);

        try self.tiles.put(name, texture);
    }

    pub fn fillWith(self: *TileMap, name: []const u8, x: c_int, y: c_int, w: c_int, h: c_int) !void {
        var cur_x = x;
        var cur_y = y;
        while(cur_y < h) : (cur_y += self.tileHeight) {
            while(cur_x < w) : (cur_x += self.tileWidth) {
                try self.render(name, cur_x, cur_y);
            }
            cur_x = 0;
        }
    }
    
    pub fn render(self: *TileMap, name: []const u8, x: c_int, y: c_int) !void {
        var src_rect: c.SDL_Rect = undefined;
        var dest_rect: c.SDL_Rect = undefined;

        src_rect.x = 0;
        src_rect.y = 0;
        src_rect.w = self.tileWidth;
        src_rect.h = self.tileHeight;

        dest_rect.x = x;
        dest_rect.y = y;
        dest_rect.w = self.tileWidth;
        dest_rect.h = self.tileHeight;

        if(c.SDL_RenderCopyEx(self.renderer, self.tiles.get(name).?, &src_rect, &dest_rect, 0, 0, c.SDL_FLIP_NONE) != 0) {
            c.SDL_Log("Unable to render copy: %s", c.SDL_GetError());
            return error.SDL_RenderCopyExFailed;
        }
    }
};

pub const Direction = enum {
    U,
    D,
    L,
    R
};