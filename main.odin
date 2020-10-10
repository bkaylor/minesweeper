package sdl_test

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"
import "core:strings"

import sdl "shared:odin-sdl2"
import sdl_ttf "shared:odin-sdl2/ttf"
import sdl_image "shared:odin-sdl2/image"

DEFAULT_BOMBS :: 45;
DEFAULT_WIDTH :: 15;
DEFAULT_HEIGHT :: 15;

MAX_CELLS :: 50*50;

my_rand := rand.create(u64(time.now()._nsec));

Relative_Cell :: struct {
    dx: i32,
    dy: i32,
};

Cell :: struct {
    is_revealed: bool,
    is_bomb: bool,
    is_flagged: bool,
    adjacent_bomb_count: i32,
    rect: sdl.Rect,
};

State :: struct {
    reset: bool,
    width: i32,
    height: i32,
    bomb_count: i32,

    won: bool,
    lost: bool,
    revealed_all: bool,
    check_for_win: bool,
    generated_level: bool,

    start_time: time.Time,
    end_time: time.Time,

    flagged_cells: i32,

    mouse_x: i32,
    mouse_y: i32,

    is_any_hovered: bool,
    hovered: i32,

    cells: [MAX_CELLS]Cell,

    font: ^sdl_ttf.Font,

    origin_x: i32,
    origin_y: i32,
    size: i32,

    window: ^sdl.Window,
    window_w: i32,
    window_h: i32,
};

main :: proc() {
    state: State;
    state.width = DEFAULT_WIDTH;
    state.height = DEFAULT_HEIGHT;
    state.bomb_count = DEFAULT_BOMBS;
    state.reset = true;

    sdl.init(sdl.Init_Flags.Everything);
	state.window = sdl.create_window("Minesweeper", 
                                     i32(sdl.Window_Pos.Undefined), i32(sdl.Window_Pos.Undefined), 
                                     800, 600, 
                                     sdl.Window_Flags(sdl.Window_Flags.Resizable));

	renderer := sdl.create_renderer(state.window, -1, sdl.Renderer_Flags(sdl.Renderer_Flags.Present_VSync));

    sdl_image.init(sdl_image.Init_Flags.PNG);
    sdl_ttf.init();

    // texture := sdl_image.load_texture(renderer, "test.png");

    font := sdl_ttf.open_font("liberation.ttf", 20);
    state.font = font;

    running := true;

    for running {
        running = input(&state);
        update(&state);
        render(renderer, &state);
    }
}

check_for_end_conditions :: proc(state: ^State) -> bool {
    if (state.flagged_cells == state.bomb_count) {
        any_bad_flags := false;

        for x:i32 = 0; x < state.width; x += 1 {
            for y:i32 = 0; y < state.height; y += 1 {
                index := y*state.width + x;
                cell := &state.cells[index];

                if (cell.is_flagged && !cell.is_bomb) ||
                   (cell.is_bomb && !cell.is_flagged) {
                   any_bad_flags = true;
                }
            }
        }

        if !any_bad_flags {
            return true;
        }
    }

    return false;
}

place_bombs :: proc(state: ^State, in_x: i32, in_y: i32) {
    neighbors := [8]Relative_Cell {
        {-1, -1}, {0, -1}, {1, -1},
        {-1,  0},          {1,  0},
        {-1,  1}, {0,  1}, {1,  1},
    };

    bombs_placed: i32 = 0;
    for bombs_placed < state.bomb_count {
        x := rand.int31(&my_rand) % state.width;
        y := rand.int31(&my_rand) % state.height;

        if !state.cells[y*state.width + x].is_bomb {
            is_neighbor := (x == in_x && y == in_y);

            for i := 0; i < 8; i += 1 {
                neighbor := neighbors[i];

                nx := in_x + neighbor.dx;
                ny := in_y + neighbor.dy;

                if x == nx && y == ny {
                    is_neighbor = true;
                    break;
                }
            }

            if !is_neighbor {
                state.cells[y*state.width + x].is_bomb = true;
                bombs_placed += 1;
            }
        }
    }

    for x:i32 = 0; x < state.width; x += 1 {
        for y:i32 = 0; y < state.height; y += 1 {
            index := y*state.width + x;
            cell := &state.cells[index];

            for i := 0; i < 8; i += 1 {
                neighbor := neighbors[i];

                nx := x + neighbor.dx;
                ny := y + neighbor.dy;

                if (nx >= 0 && nx < state.width &&
                   ny >= 0 && ny < state.height) {
                    nindex := ny * state.width + nx;
                    ncell := state.cells[nindex];

                    if ncell.is_bomb {
                        state.cells[index].adjacent_bomb_count += 1;
                    }
                }
            }
        }
    }
}

reset_state :: proc(state: ^State) {
    state.reset = false;
    state.won = false;
    state.lost = false;
    state.revealed_all = false;
    state.check_for_win = false;
    state.generated_level = false;

    state.start_time = time.now();

    state.flagged_cells = 0;

    sdl.get_window_size(state.window, &state.window_w, &state.window_h);

    origin_x, origin_y, size: i32;

    padding: f32 = 0.10;

    // The size of a cell is decided by the smaller edge of the window.
    if state.window_w > state.window_h {
        size = (i32)((1.0 - padding) * (f32)(state.window_h)) / state.height;
    } else {
        size = (i32)((1.0 - padding) * (f32)(state.window_w)) / state.width;
    }
    
    state.origin_x = (state.window_w - (state.width * size))/2;
    state.origin_y = (state.window_h - (state.height * size))/2;
    state.size = size;

    for i: i32 = 0; i < state.width*state.height; i += 1 {
        state.cells[i] = {
            false,
            false,
            false,
            0,
            sdl.Rect{0,0,0,0},
        };
    }

    // Build the persistent rects for each cell.
    for x:i32 = 0; x < state.width; x += 1 {
        for y:i32 = 0; y < state.height; y += 1 {
            index := y*state.width + x;
            cell := &state.cells[index];

            cell.rect = sdl.Rect{
                cast(i32)(state.origin_x + x*state.size), 
                cast(i32)(state.origin_y + y*state.size), 
                cast(i32)(state.size), 
                cast(i32)(state.size),
            };
        }
    }
}

reveal :: proc(state: ^State, index: i32) {
    x: i32 = index % state.width;
    y: i32 = index / state.width;

    // If this is the first reveal- place the bombs.
    // We generate the bombs on first reveal so that, the player can be guaranteed that
    // there will not be any bombs on or adjacent to the first clicked square.
    if !state.generated_level {
        place_bombs(state, x, y);
        state.generated_level = true;
    }

    cell := &state.cells[index];

    cell.is_revealed = true;

    state.check_for_win = true;

    if cell.is_bomb {
        state.lost = true;
        return;
    }
    
    if cell.adjacent_bomb_count == 0 {
        
        neighbors := [8]Relative_Cell {
            {-1, -1}, {0, -1}, {1, -1},
            {-1,  0},          {1,  0},
            {-1,  1}, {0,  1}, {1,  1},
        };

        for i := 0; i < 8; i += 1 {
            neighbor := neighbors[i];

            nx := x + neighbor.dx;
            ny := y + neighbor.dy;

            if (nx >= 0 && nx < state.width && ny >= 0 && ny < state.height) {
                nindex := ny * state.width + nx;
                ncell := &state.cells[nindex];

                if !ncell.is_revealed {
                    reveal(state, nindex);
                }
            }
        }
    }
}

input :: proc(state: ^State) -> bool {

    sdl.get_mouse_state(&state.mouse_x, &state.mouse_y);

    e: sdl.Event;
    for sdl.poll_event(&e) != 0 {
        #partial switch e.type {
        
            case sdl.Event_Type.Quit:
                return false;

            case sdl.Event_Type.Key_Down:
                switch e.key.keysym.sym {
                    case sdl.SDLK_ESCAPE:
                        return false;

                    case sdl.SDLK_r:
                        state.reset = true;

                    case (i32)(sdl.SDLK_RIGHT):
                        state.width += 1;
                        state.height += 1;

                    case (i32)(sdl.SDLK_LEFT):
                        state.width -= 1;
                        state.height -= 1;

                    case (i32)(sdl.SDLK_UP):
                        state.bomb_count += 1;

                    case (i32)(sdl.SDLK_DOWN):
                        state.bomb_count -= 1;
                }

            case sdl.Event_Type.Mouse_Button_Down:

                // Left click reveals the clicked cell.
                if e.button.button == cast(u8)sdl.Mousecode.Left {
                    if state.is_any_hovered {
                        reveal(state, state.hovered);
                    }
                // Right click reveals all adjacent unflagged cells, but only if the number of
                // flags adjacent to the cell is equal to the number of bombs adjacent to the cell.
                } else if e.button.button == 3 { // cast(u8)sdl.Mousecode.Right {
                    if state.is_any_hovered {
                        index := state.hovered;

                        cell := &state.cells[index];
                        x: i32 = index % state.width;
                        y: i32 = index / state.width;

                        if cell.is_revealed {
                                neighbors := [8]Relative_Cell {
                                    {-1, -1}, {0, -1}, {1, -1},
                                    {-1,  0},          {1,  0},
                                    {-1,  1}, {0,  1}, {1,  1},
                                };

                                flagged_neighbors: i32 = 0;

                                for i := 0; i < 8; i += 1 {
                                    neighbor := neighbors[i];

                                    nx := x + neighbor.dx;
                                    ny := y + neighbor.dy;

                                    if (nx >= 0 && nx < state.width && ny >= 0 && ny < state.height) {
                                        nindex := ny * state.width + nx;
                                        ncell := &state.cells[nindex];

                                        if ncell.is_flagged {
                                            flagged_neighbors += 1;
                                        }
                                    }
                                }

                                if (flagged_neighbors == cell.adjacent_bomb_count) {
                                    for i := 0; i < 8; i += 1 {
                                        neighbor := neighbors[i];

                                        nx := x + neighbor.dx;
                                        ny := y + neighbor.dy;

                                        if (nx >= 0 && nx < state.width && ny >= 0 && ny < state.height) {
                                            nindex := ny * state.width + nx;
                                            ncell := &state.cells[nindex];

                                            if (!ncell.is_flagged) {
                                                reveal(state, nindex);
                                            }
                                        }
                                    }
                                }
                        } else {
                            if cell.is_flagged {
                                cell.is_flagged = false;
                                state.flagged_cells -= 1;
                            } else {
                                cell.is_flagged = true;
                                state.flagged_cells += 1;

                                state.check_for_win = true;
                            }
                        }
                    }
                }
        }
    }

    return true;
}

point_in_rect :: proc(x: i32, y: i32, rect: sdl.Rect) -> bool {
    if x > rect.x && x < rect.x + rect.w &&
       y > rect.y && y < rect.y + rect.h {
       return true;
    }

    return false;
}

update :: proc(state: ^State) {
    if (state.reset) {
        reset_state(state);
    }

    found := false;
    state.is_any_hovered = false;

    // Find if the mouse is hovering a cell.
    for x: i32 = 0; x < state.width; x += 1 {
        for y: i32 = 0; y < state.height; y += 1 {
            index := y * state.width + x;

            cell := &state.cells[index];

            if point_in_rect(state.mouse_x, state.mouse_y, cell.rect) {
                state.is_any_hovered = true;
                state.hovered = index;
                found = true;
            }

            if found { break };
        }

        if found { break };
    }

    if state.check_for_win {
        state.won = check_for_end_conditions(state);

        // Reveal all remaining non-bombs if all bombs were flagged properly.
        if state.won {
            for x: i32 = 0; x < state.width; x += 1 {
                for y: i32 = 0; y < state.height; y += 1 {
                    index := y * state.width + x;
                    cell := &state.cells[index];

                    if !cell.is_bomb {
                        cell.is_revealed = true;
                    }
                }
            }
        }

        state.check_for_win = false;
    }

    if state.lost && !state.revealed_all {
        // Reveal rest of the board.
        for x: i32 = 0; x < state.width; x += 1 {
            for y: i32 = 0; y < state.height; y += 1 {
                index := y * state.width + x;
                cell := &state.cells[index];
                cell.is_revealed = true;
            }
        }

        state.revealed_all = true;
    }
}

draw_text :: proc(renderer: ^sdl.Renderer, state: ^State, message: cstring, x: i32, y: i32) {
    text_surface := sdl_ttf.render_utf8_blended(state.font, message, sdl.Color{255, 255, 255, 255});
    text_texture := sdl.create_texture_from_surface(renderer, text_surface);
    sdl.free_surface(text_surface);

    rect := sdl.Rect{x, y, 200, 200};
    sdl.query_texture(text_texture, nil, nil, &rect.w, &rect.h);
    rect.x = rect.x - rect.w/2;

    sdl.render_copy(renderer, text_texture, nil, &rect);
    sdl.destroy_texture(text_texture);
}

render :: proc(renderer: ^sdl.Renderer, state: ^State) {
    sdl.set_render_draw_color(renderer, 0, 0, 0, 255);
    sdl.render_clear(renderer);

    for x: i32 = 0; x < state.width; x += 1 {
        for y: i32 = 0; y < state.height; y += 1 {
            index := y * state.width + x;
            cell := state.cells[index];

            if cell.is_revealed {
                if cell.is_bomb {
                    sdl.set_render_draw_color(renderer, 120, 0, 0, 255);
                } else {
                    sdl.set_render_draw_color(renderer, 0, 0, 120, 255);
                }
            } else {
                sdl.set_render_draw_color(renderer, 120, 120, 120, 255);
            }

            sdl.render_fill_rect(renderer, &cell.rect);

            if cell.is_revealed && !cell.is_bomb && cell.adjacent_bomb_count > 0{
                text := strings.clone_to_cstring(fmt.tprintf("%d", cell.adjacent_bomb_count));
                draw_text(renderer, state, text, cell.rect.x + state.size/2, cell.rect.y + state.size/5);
            }

            if cell.is_flagged {
                text := strings.clone_to_cstring(fmt.tprintf("!"));
                draw_text(renderer, state, text, cell.rect.x + state.size/2, cell.rect.y + state.size/5);
            }

            sdl.set_render_draw_color(renderer, 0, 0, 0, 255);
            sdl.render_draw_rect(renderer, &cell.rect);

            if state.is_any_hovered {
                if index == state.hovered {
                    sdl.set_render_draw_color(renderer, 200, 200, 200, 255);
                    sdl.render_draw_rect(renderer, &cell.rect);
                }
            }
        }
    }

    text: cstring;

    if state.won {
        sdl.set_render_draw_color(renderer, 0, 255, 0, 255);
        text = strings.clone_to_cstring(fmt.tprintf("Win! (R to continue)."));
    } else if state.lost {
        sdl.set_render_draw_color(renderer, 255, 0, 0, 255);
        text = strings.clone_to_cstring(fmt.tprintf("Loss. (R to continue)."));
    } else {
        text = strings.clone_to_cstring(fmt.tprintf("%d/%d (%d by %d)", state.flagged_cells, state.bomb_count, state.width, state.height));
    }

    draw_text(renderer, state, text, state.window_w/2, 4);

    sdl.render_present(renderer);
}
