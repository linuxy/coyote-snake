// Minimal SDL2 + SDL2_image bindings for coyote-snake.
// Avoids translate-c, which fails on some system header chains in Zig 0.17.

pub const SDL_INIT_VIDEO: u32 = 0x0000_0020;

pub const SDL_WINDOWPOS_UNDEFINED: c_int = 0x1FFF0000;
pub const SDL_WINDOW_OPENGL: u32 = 0x0000_0002;

pub const SDL_QUIT: u32 = 0x0100;
pub const SDL_KEYDOWN: u32 = 0x0300;

pub const SDLK_UP: c_int = 1073741906;
pub const SDLK_DOWN: c_int = 1073741905;
pub const SDLK_LEFT: c_int = 1073741904;
pub const SDLK_RIGHT: c_int = 1073741903;
pub const SDLK_w: c_int = 119;
pub const SDLK_a: c_int = 97;
pub const SDLK_s: c_int = 115;
pub const SDLK_d: c_int = 100;

pub const SDL_FLIP_NONE: u32 = 0;

pub const SDL_Window = opaque {};
pub const SDL_Renderer = opaque {};
pub const SDL_Texture = opaque {};

pub const SDL_Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
};

pub const SDL_Keysym = extern struct {
    scancode: c_int,
    sym: c_int,
    mod: u16,
    _padding: u16,
    unused: u32,
};

pub const SDL_KeyboardEvent = extern struct {
    @"type": u32,
    timestamp: u32,
    windowID: u32,
    state: u8,
    repeat: u8,
    padding2: u8,
    padding3: u8,
    keysym: SDL_Keysym,
};

// SDL_Event is a union sized to its largest member (56 bytes on Linux x86_64).
pub const SDL_Event = extern union {
    @"type": u32,
    key: SDL_KeyboardEvent,
    raw: [56]u8,
};

pub extern fn SDL_Init(flags: u32) c_int;
pub extern fn SDL_Quit() void;
pub extern fn SDL_QuitSubSystem(flags: u32) void;
pub extern fn SDL_GetError() [*:0]const u8;
pub extern fn SDL_Log(fmt: [*:0]const u8, ...) void;
pub extern fn SDL_Delay(ms: u32) void;
pub extern fn SDL_GetTicks() u32;
pub extern fn SDL_PollEvent(event: *SDL_Event) c_int;

pub extern fn SDL_CreateWindow(
    title: [*:0]const u8,
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    flags: u32,
) ?*SDL_Window;

pub extern fn SDL_DestroyWindow(window: ?*SDL_Window) void;

pub extern fn SDL_CreateRenderer(
    window: ?*SDL_Window,
    index: c_int,
    flags: u32,
) ?*SDL_Renderer;

pub extern fn SDL_DestroyRenderer(renderer: ?*SDL_Renderer) void;
pub extern fn SDL_RenderClear(renderer: ?*SDL_Renderer) c_int;
pub extern fn SDL_SetRenderDrawColor(renderer: ?*SDL_Renderer, r: u8, g: u8, b: u8, a: u8) c_int;
pub extern fn SDL_RenderPresent(renderer: ?*SDL_Renderer) void;

pub extern fn SDL_RenderCopyEx(
    renderer: ?*SDL_Renderer,
    texture: ?*SDL_Texture,
    srcrect: *const SDL_Rect,
    dstrect: *const SDL_Rect,
    angle: f64,
    center: ?*const SDL_Point,
    flip: u32,
) c_int;

pub const SDL_Point = extern struct {
    x: c_int,
    y: c_int,
};

pub extern fn IMG_LoadTexture(renderer: ?*SDL_Renderer, file: [*:0]const u8) ?*SDL_Texture;
