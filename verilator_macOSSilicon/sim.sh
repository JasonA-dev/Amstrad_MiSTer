verilator \
-cc -exe --public --trace-fst --savable --build \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal \
--top-module top sim.v \
    ../rtl/Amstrad_motherboard.v \
    ../rtl/UM6845R.v \
    ../rtl/dpram.sv \
    ../rtl/crt_filter.v \
    ../rtl/GA40010/ga40010.sv \
    ../rtl/GA40010/rslatch.v \
    ../rtl/GA40010/casgen.v \
    ../rtl/GA40010/casgen_sync.v \
    ../rtl/GA40010/syncgen.v \
    ../rtl/GA40010/syncgen_sync.v \
    ../rtl/GA40010/video.sv \
    ../rtl/Amstrad_MMU.v \
    ../rtl/i8255.v \
    ../rtl/YM2149.sv \
    ../rtl/hid.sv \
    ../rtl/tv80/tv80s.v \
    ../rtl/tv80/tv80_alu.v \
    ../rtl/tv80/tv80_core.v \
    ../rtl/tv80/tv80_reg.v \
    ../rtl/tv80/tv80_mcode.v \
    sim_main.cpp \
    ../sim/sim_console.cpp \
    ../sim/sim_audio.cpp \
    ../sim/sim_bus.cpp \
    ../sim/sim_clock.cpp \
    ../sim/sim_video.cpp \
    ../sim/sim_input.cpp \
    ../sim/imgui/imgui.cpp \
    ../sim/imgui/imgui_draw.cpp \
    ../sim/imgui/imgui_widgets.cpp \
    ../sim/imgui/imgui_tables.cpp \
    ../sim/imgui/implot.cpp \
    ../sim/imgui/implot_items.cpp \
    ../sim/imgui/ImGuiFileDialog.cpp \
    ../sim/imgui/backends/imgui_impl_sdl2.cpp \
    ../sim/imgui/backends/imgui_impl_opengl3.cpp \
    ../sim/imgui/backends/imgui_impl_opengl2.cpp \
    ../obj_dir/Vtop__ALL.a \
    ../obj_dir/Vtop.cpp \
    ../obj_dir/Vtop__Syms.cpp \
    ../obj_dir/Vtop__Slow.cpp \
    ../obj_dir/Vtop__Trace.cpp \
    ../obj_dir/Vtop__Trace__Slow.cpp \
    ../obj_dir/Vtop__1.cpp \
    ../obj_dir/Vtop__1__Slow.cpp \
    ../obj_dir/Vtop__2.cpp \
    ../obj_dir/Vtop__2__Slow.cpp \
    -CFLAGS "-arch arm64 -I/opt/homebrew/opt/sdl2 -I../sim -I../sim/imgui -I../sim/implot -I../sim/imgui/backends" \
    -LDFLAGS "-arch arm64 -L/opt/homebrew/opt/sdl2/lib -lSDL2 -framework OpenGL -v" && ./obj_dir/Vtop $*
