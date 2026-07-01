# coyote-snake
An example game built with [coyote-ecs](https://github.com/linuxy/coyote-ecs), a fast and simple zig native ECS.

Builds against **Zig 0.17.0** or later. Expects [coyote-ecs](https://github.com/linuxy/coyote-ecs) as a sibling directory (`../coyote-ecs`).

```bash
git clone https://github.com/linuxy/coyote-snake.git
git clone https://github.com/linuxy/coyote-ecs.git
```

To build you need SDL2 and SDL2_image development libraries installed.

On Debian/Ubuntu:
* `sudo apt install libsdl2-dev libsdl2-image-dev`

To build:
* `zig build`

To run:
* `zig build run`

![Snake](<https://github.com/linuxy/coyote-snake/blob/main/assets/snake.gif> "snake!")
