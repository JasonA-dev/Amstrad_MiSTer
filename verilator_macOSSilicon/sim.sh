verilator \
-cc -exe --public --trace-fst --savable --build \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal \
--top-module top sim.v \
    ../rtl/Amstrad_motherboard.v \
    ../rtl/Amstrad_MMU.v \
    ../rtl/crt_filter.v \
    ../rtl/color_mix.sv \
    ../rtl/i8255.v \
    ../rtl/UM6845R.v \
    ../rtl/YM2149.sv \
    ../rtl/dpram.sv \
    ../rtl/hid.sv \
    ../rtl/mock_sdram.v \
    ../rtl/plus_controller.v \
    ../rtl/ASIC.sv \
    ../rtl/cartridge.v \
    ../rtl/GA40010/ga40010.sv \
    ../rtl/GA40010/rslatch.v \
    ../rtl/GA40010/casgen.v \
    ../rtl/GA40010/casgen_sync.v \
    ../rtl/GA40010/syncgen.v \
    ../rtl/GA40010/syncgen_sync.v \
    ../rtl/GA40010/video.sv \
    ../rtl/ASIC/ASIC_io.v \
    ../rtl/ASIC/ASIC_ACID.sv \
    ../rtl/ASIC/ASIC_registers.v \
    ../rtl/tv80/tv80_alu.v \
    ../rtl/tv80/tv80_core.v \
    ../rtl/tv80/tv80_mcode.v \
    ../rtl/tv80/tv80_reg.v \
    ../rtl/tv80/tv80e.v \
    ../rtl/tv80/tv80n.v \
    ../rtl/tv80/tv80s.v \
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
