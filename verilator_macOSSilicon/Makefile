#
#
#

V = verilator
#V = /usr/local/bin/verilator
#V = /usr/local/src/verilator-3.876/bin/verilator
COSIM = n

TOP = --top-module top
RTL = ../rtl
V_INC = +incdir+$(RTL) 

V_DEFINE = +define+debug=1 +define+SIMULATION=1   -CFLAGS "-I../sim/imgui -I../sim/vinc -I../sim/ -O3" 
#V_DEFINE += --converge-limit 2000 -Wno-WIDTH -Wno-IMPLICIT -Wno-MODDUP -Wno-UNSIGNED -Wno-CASEINCOMPLETE -Wno-CASEX -Wno-SYMRSVDWORD -Wno-COMBDLY -Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-UNOPTFLAT -Wno-SELRANGE -Wno-CMPCONST -Wno-CASEOVERLAP -Wno-PINMISSING -Wno-MULTIDRIVEN
#V_DEFINE += --threads 8  # this slows it way down
V_DEFINE += 

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S), Darwin) #APPLE
	ECHO_MESSAGE = "Mac OS X"
	LIBS += -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo `sdl2-config --libs`
	LIBS += -L/usr/local/lib -L/opt/local/lib

	CXXFLAGS += `sdl2-config --cflags` -Iimgui
	CXXFLAGS += -I/usr/local/include -I/opt/local/include 
	CFLAGS = $(CXXFLAGS) -Iimgui
endif

ifeq ($(UNAME_S), Linux) #LINUX
	ECHO_MESSAGE = "Linux"
	LIBS += -lGL -ldl `sdl2-config --libs`

	CXXFLAGS += `sdl2-config --cflags` -Iimgui
	CFLAGS = $(CXXFLAGS)
endif

ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
	ECHO_MESSAGE = "MinGW"
	LIBS += -lgdi32 -lopengl32 -limm32 `pkg-config --static --libs sdl2`

	CXXFLAGS += `pkg-config --cflags sdl2`
	CFLAGS = $(CXXFLAGS)
endif

CFLAGS += $(CC_OPT) $(CC_DEFINE) -Iimgui
LDFLAGS = $(LIBS)
EXE = ./obj_dir/Vtop
V_OPT = -O3 --x-assign fast --x-initial fast --noassert 
CC_OPT = -O
#V_OPT = 
#CC_OPT =   

V_SRC = \
	sim.v \
	$(RTL)/rcastudioii.sv \
	$(RTL)/cdp1802.v \
	$(RTL)/cdp1861.v \	
	$(RTL)/dpram.sv \
	$(RTL)/dma.v \		
	$(RTL)/rom.v \
	$(RTL)/pixie/pixie_video_studioii.v \
	$(RTL)/pixie/pixie_video.v

C_SRC = \
	sim_main.cpp  \
sim/sim_bus.cpp		sim/sim_clock.cpp	sim/sim_console.cpp	sim/sim_video.cpp sim/sim_input.cpp \
 sim/imgui/imgui_impl_sdl.cpp sim/imgui/imgui_impl_opengl2.cpp sim/imgui/imgui_draw.cpp sim/imgui/imgui_widgets.cpp sim/imgui/imgui_tables.cpp sim/imgui/imgui.cpp
VOUT = obj_dir/Vtop.cpp

# Compiler flags
CXXFLAGS = -std=c++17 -Wall -O2
VERILATOR_FLAGS = -Wall -cc --exe --build -j 0

# Source files
VERILOG_SOURCES = sim.v
CPP_SOURCES = sim_main.cpp

# Default target
all: sim

# Generate Verilator files and build simulation
sim: $(VERILOG_SOURCES) $(CPP_SOURCES)
	verilator $(VERILATOR_FLAGS) $(VERILOG_SOURCES) $(CPP_SOURCES)
	$(MAKE) -C obj_dir -f Vtop.mk

# Run simulation
run: sim
	./obj_dir/Vtop

# Clean build files
clean:
	rm -rf obj_dir
	rm -f sim.vcd

.PHONY: all sim run clean