package dx11

import "core:fmt"
import SDL "vendor:sdl2"

main :: proc() {
  SDL.Init({.VIDEO})
  defer SDL.Quit()

  window := SDL.CreateWindow(
    "Game", 
    SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, 
    500, 500,
    {.ALLOW_HIGHDPI, .HIDDEN, .RESIZABLE},
  )
  defer SDL.DestroyWindow(window)

  SDL.ShowWindow(window)

  for quit := false; !quit; {
    for e: SDL.Event; SDL.PollEvent(&e); {
      #partial switch(e.type) {
        case .QUIT:
          quit = true
        case .KEYDOWN:
          if e.key.keysym.sym == .ESCAPE {
            quit = true
          }
      }
    }
  }
}