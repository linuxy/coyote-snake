const std = @import("std");
const ecs = @import("coyote-ecs");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const World = ecs.World;
const Cast = ecs.Cast;
const Systems = ecs.Systems;

pub fn main() void {
    std.log.info("hi", .{});
}

pub const Game = struct {
    isRunning: bool,
    player: *Player,

    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,

    screenWidth: u32,
    screenHeight: u32,

    pub fn init() *Game {}
    pub fn render() void {}
    pub fn update() void {}
    pub fn handleEvents() void {}
    pub fn deinit() void {}
};

pub const Player = struct {
    speed: u32 = 128,
    last_node: *TailNode,
    next_node: *TailNode,

    pub fn init(x: u32, y: u32) void {

    }

    pub fn update() void {

    }

    pub fn growTail() void {

    }

    pub fn setDirection() void {

    }

    pub fn directionPependicularTo(new_direction: Direction) bool {

    }
};