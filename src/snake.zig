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
        game.handleEvents();
        game.update();
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
        self.player = try Player.init(0,0);
        self.isRunning = true;

        return self;
    }

    pub fn render(self: *Game) !void {
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        try self.tileMap.?.fillWith("grass", 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
        try self.player.?.render(self);
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn update(self: *Game) void {
        self.player.?.update();
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

pub const GameObject = struct {

    x: f64,
    y: f64,
    last_update: u32 = 0,
    time_delta: f64,
    children: std.ArrayList(*GameObject),
    texture: []const u8,

    pub fn init(name: []const u8, x: f64, y: f64) !*GameObject {
        var self = try allocator.create(GameObject);
        self.x = x;
        self.y = y;
        self.texture = name;
        self.children = std.ArrayList(*GameObject).init(allocator);
        self.last_update = 0;
        return self;
    }

    pub fn addChild(self: *GameObject, other: *GameObject) !void {
        try self.children.append(other);
    }

    pub fn distanceTo(self: *GameObject, x: f64, y: f64) f64 {
        return @sqrt(@exp2(self.x - x)) + @exp2((self.y - y));
    }

    pub fn distanceToObject(self: *GameObject, other: *GameObject) f64 {
        return self.distanceTo(other.x, other.y);
    }

    pub fn render(self: *GameObject, game: *Game) !void {
        for(self.children.items) |child| {
            try child.render(game);
        }
        try game.tileMap.?.render(self.texture, @floatToInt(c_int, self.x), @floatToInt(c_int, self.y));
    }

    pub fn update(self: *GameObject) void {
        if(self.last_update == 0) {
            self.last_update = c.SDL_GetTicks();
            std.log.info("0 {}", .{self.last_update});
        }

        for(self.children.items) |child| {
            child.update();
        }

        var current_time = c.SDL_GetTicks();
        std.log.info("{} : {}", .{current_time, self.last_update});
        self.time_delta = @intToFloat(f64, current_time - self.last_update) / 1000.0;
        self.last_update = current_time;
    }
};

pub const Player = struct {
    speed: u32 = 128,
    last_node: ?*TailNode,
    next_node: ?*TailNode,
    direction: Direction = .D,

    parent: *GameObject,
    
    pub fn init(x: f64, y: f64) !*Player {
        var self = try allocator.create(Player);
        var parent = try GameObject.init("snake_head", x, y);
        self.parent = parent;
        self.last_node = null;
        self.next_node = null;
        return self;
    }

    pub fn update(self: *Player) void {
        self.parent.update();
        var speed_delta = @intToFloat(f64, self.speed) * self.parent.time_delta;
        self.next_node.?.speed_delta = speed_delta;
        switch(self.direction) {
            .U => { self.parent.y -= speed_delta; },
            .D => { self.parent.y += speed_delta; },
            .L => { self.parent.x -= speed_delta; },
            .R => { self.parent.x += speed_delta; },
        }

        if(self.next_node.?.collidesWith(self.parent, 0)) {
            self.speed = 0;
        }

        if(!(self.next_node.?.path.len == 0)) {
            var last_path = self.next_node.?.path.last.?.data;
            if(self.parent.distanceTo(last_path.x, last_path.y) > speed_delta)
                try self.next_node.?.addPath(PathPoint{.x = self.parent.x, .y = self.parent.y});
        } else {
            if(self.parent.distanceTo(self.next_node.?.parent.x, self.next_node.?.parent.y) > speed_delta)
                try self.next_node.?.addPath(PathPoint{.x = self.parent.x, .y = self.parent.y});
        }
    }

    pub fn growTail(self: *Player) void {
        var node = TailNode {};
        if(self.next_node == null) {
            node.addTo(self);
            self.next_node = node;
        } else {
            node.addTo(self.last_node);
            self.last_node.next_node = node;
        }
        self.last_node = node;
    }

    pub fn render(self: *Player, game: *Game) !void {
        try self.parent.render(game);
    }

    pub fn setDirection(self: *Player, new_direction: Direction) void {
        if(directionPependicularTo(new_direction)) {
            self.direction = new_direction;
            self.next_node.addPath(PathPoint{.x = self.x, .y = self.y});
        }
    }

    pub fn directionPependicularTo(self: *Player, new_direction: Direction) bool {
        switch(self.direction) {
            .L => {},
            .R => {
                switch(new_direction) {
                    .U => {},
                    .D => { return true; },
                    else => {},
                }
            },
            .U => {},
            .D => {
                switch(new_direction) {
                    .L => {},
                    .R => { return true; },
                    else => {},
                }
            },
            else => {}
        }
    }
};

pub const PathPoint = struct {
    x: f64,
    y: f64,
};

pub const TailNode = struct {
    in_motion: bool = false,
    speed_delta: f64 = 0,
    next_node: ?*TailNode,
    node_number: u32,
    path: *std.TailQueue(*PathPoint),

    parent: *GameObject,

    pub fn addTo(self: *TailNode, parent: *GameObject) !void {
        _ = self;
        _ = parent;
    }

    pub fn addPath(self: *TailNode, path_point: PathPoint) !void {
        _ = self;
        _ = path_point;
    }

    pub fn collidesWith(self: *TailNode, other: *GameObject, node_number: u32) bool {
        if(!self.in_motion)
            return false;

        if(self.node_number > 10 and self.parent.distanceToObject(other) < 16)
            return true;

        if(self.next_node != null)
            return self.collidesWith(other, node_number + 1);

        return false;
    }

    pub fn update(self: *TailNode) void {
        self.parent.update();
    }

    pub fn moveTowards(self: *TailNode, target: *PathPoint) f64 {
        _ = self;
        _ = target;
    }
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