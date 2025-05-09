verilator \
-cc -exe --public --trace --savable \
--compiler msvc +define+SIMULATION=1 \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal -Wno-NEEDTIMINGOPT \
--top-module top sim.v \
../rtl/mock_sdram.v \
../rtl/Amstrad_motherboard.v \
../rtl/Amstrad_MMU.v \
../rtl/color_mix.sv \
../rtl/i8255.v \
../rtl/UM6845R.v \
../rtl/YM2149.sv \
../rtl/dpram.sv \
../rtl/GA40010/ga40010.sv \
../rtl/GA40010/rslatch.v \
../rtl/GA40010/casgen.v \
../rtl/GA40010/casgen_sync.v \
../rtl/GA40010/syncgen.v \
../rtl/GA40010/syncgen_sync.v \
../rtl/GA40010/video.sv \
../rtl/tv80/tv80_alu.v \
../rtl/tv80/tv80_core.v \
../rtl/tv80/tv80_mcode.v \
../rtl/tv80/tv80_reg.v \
../rtl/tv80/tv80e.v \
../rtl/tv80/tv80n.v \
../rtl/tv80/tv80s.v
