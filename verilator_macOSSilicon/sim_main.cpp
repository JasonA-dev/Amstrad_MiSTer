#include <verilated.h>
#include "Vtop.h"
#include "verilated_vcd_c.h"

#include "imgui.h"
#include "implot.h"
#ifndef _MSC_VER
#include <stdio.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#else
#define WIN32
#include <dinput.h>
#endif

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_video.h"
#include "sim_audio.h"
#include "sim_input.h"
#include "sim_clock.h"

#include "../imgui/imgui_memory_editor.h"
#include <verilated_fst_c.h> // FST Trace
#include "../imgui/ImGuiFileDialog.h"

#include <iostream>
#include <fstream>
using namespace std;

// Simulation control
// ------------------
int initialReset = 48;
bool run_enable = 0;
int batchSize   = 150000;
bool single_step = 0;
bool multi_step  = 0;
int  multi_step_amount = 1024;

// Debug GUI 
// ---------
const char* windowTitle = "Verilator Sim: GX4000";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_DebugLog = "Debug log";
const char* windowTitle_Video = "VGA output";
const char* windowTitle_Trace = "Trace/FST control";
const char* windowTitle_Audio = "Audio output";
bool  showDebugLog = true;
DebugConsole console;
MemoryEditor mem_edit;

// HPS emulator
// ------------
SimBus bus(console);

// Input handling
// --------------
SimInput input(12);
const int input_right   = 0;
const int input_left    = 1;
const int input_down    = 2;
const int input_up      = 3;
const int input_fire1   = 4;
const int input_fire2   = 5;
const int input_start_1 = 6;
const int input_start_2 = 7;
const int input_coin_1  = 8;
const int input_coin_2  = 9;
const int input_coin_3  = 10;
const int input_pause   = 11;

// Video
// -----
#define VGA_ROTATE 0
#define VGA_WIDTH  320
#define VGA_HEIGHT 200
#define VGA_SCALE_X vga_scale
#define VGA_SCALE_Y vga_scale
SimVideo video(VGA_WIDTH, VGA_HEIGHT, VGA_ROTATE);
float vga_scale = 2;

// Verilog module
// --------------
Vtop* top = NULL;

// Main simulation time in Verilator
vluint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

int  clk_sys_freq = 64000000;
SimClock clk_48(1); 
//SimClock clk_24(2); 

// FST trace logging
// -----------------
VerilatedFstC* tfp = new VerilatedFstC; //FST Trace
bool Trace = 0;
char Trace_Deep[3] = "99";
char Trace_File[30] = "sim.fst";
char Trace_Deep_tmp[3] = "99";
char Trace_File_tmp[30] = "sim.fst";
int  iTrace_Deep_tmp = 99;
char SaveModel_File_tmp[20] = "test", SaveModel_File[20] = "test";

//Trace Save/Restore
void save_model(const char* filenamep) {
	VerilatedSave os;
	os.open(filenamep);
	os << main_time; // user code must save the timestamp, etc
	os << *top;
}
void restore_model(const char* filenamep) {
	VerilatedRestore os;
	os.open(filenamep);
	os >> main_time;
	os >> *top;
}

// Audio
// -----
//#define DISABLE_AUDIO
#ifndef DISABLE_AUDIO
SimAudio audio(clk_sys_freq, true);
#endif

// Reset simulation variables and clocks
void resetSim() {
	main_time = 0;
	clk_48.Reset();
	//clk_24.Reset();
}

//-----------------------------------------------------------------------
// The primary simulation step function (fixed version)
//-----------------------------------------------------------------------
int verilate() {
	if (!Verilated::gotFinish()) {

		// Assert reset during startup
		//top->reset = 0;
		//if (main_time < initialReset) {
		//	top->reset = 1;
		//}
		//if (main_time == initialReset) {
		//	top->reset = 0;
		//}

		// 1) Tick the clock dividers every call
		clk_48.Tick();
		//clk_24.Tick();

		// 2) Drive those clocks into the DUT
		top->clk_48 = clk_48.clk;
		//top->clk_24 = clk_24.clk;

		// 3) We can do host "BeforeEval" tasks on the rising edge
		//    (e.g. CPU debug hooking, input sampling, etc.)
		if (clk_48.IsRising()) {
			// Possibly do "HPS" or "host" tasks here
			input.BeforeEval();
			bus.BeforeEval();

		}

		// 4) Evaluate the design on *every* call (both edges)
		top->eval_step();

		// 5) If it's the rising edge, do "AfterEval" tasks,
		//    audio sampling, VCD dump, etc.
		if (clk_48.IsRising()) {
			// Possibly do "AfterEval" tasks
			bus.AfterEval();

#ifndef DISABLE_AUDIO
			audio.Clock(top->AUDIO_L, top->AUDIO_R);
#endif

			// If the design has a "pixel" enable at rising edge
			if (top->top__DOT__ce_pix) {
				uint32_t colour = 0xFF000000;
				
				// Scale up the 2-bit color to 8-bit for better visibility
				uint8_t r_val = top->VGA_R * 0x55;  // Scale 0-3 to 0-255
				uint8_t g_val = top->VGA_G * 0x55;
				uint8_t b_val = top->VGA_B * 0x55;
				
				colour = 0xFF000000 | (b_val << 16) | (g_val << 8) | r_val;
				
				video.Clock(top->VGA_HB, top->VGA_VB,
				            top->VGA_HS, top->VGA_VS, colour);
			}

			// FST trace dump
			if (Trace) {
				if (!tfp->isOpen()) {
					tfp->open(Trace_File); // open if not already
				}
				tfp->dump(main_time);
			}

			// Advance main_time here (so next rising edge is a new time)
			main_time++;
		}
		return 1;
	}

	// If Verilator thinks we are finished, stop & cleanup
	top->final();
	tfp->close();
	delete top;
	exit(0);
	return 0;
}

//-----------------------------------------------------------------------
// The main() function (mostly unchanged, except it calls the fixed verilate())
//-----------------------------------------------------------------------
int main(int argc, char** argv, char** env) {

	// Prepare Verilator
	Verilated::traceEverOn(true);
	top = new Vtop("top");
	top->trace(tfp, 99);  // up to 99 levels of hierarchy
	Verilated::commandArgs(argc, argv);

#ifdef WIN32
	// Attach debug console
	Verilated::setDebug(console);
#endif

	// Attach bus
	bus.ioctl_addr    = &top->ioctl_addr;
	bus.ioctl_index   = &top->ioctl_index;
	bus.ioctl_wait    = &top->ioctl_wait;
	bus.ioctl_download= &top->ioctl_download;
	bus.ioctl_upload  = &top->ioctl_upload;
	bus.ioctl_wr      = &top->ioctl_wr;
	bus.ioctl_dout    = &top->ioctl_dout;
	bus.ioctl_din     = &top->ioctl_din;

	// Attach input
	input.ps2_key     = &top->ps2_key;

#ifndef DISABLE_AUDIO
	audio.Initialise();
#endif

	input.Initialise();

#ifdef WIN32
	input.SetMapping(input_up, DIK_UP);
	// ...
#else
	input.SetMapping(input_up, SDL_SCANCODE_UP);
	input.SetMapping(input_right, SDL_SCANCODE_RIGHT);
	input.SetMapping(input_down, SDL_SCANCODE_DOWN);
	input.SetMapping(input_left, SDL_SCANCODE_LEFT);
	input.SetMapping(input_fire1, SDL_SCANCODE_SPACE);
	input.SetMapping(input_start_1, SDL_SCANCODE_1);
	input.SetMapping(input_start_2, SDL_SCANCODE_2);
	input.SetMapping(input_coin_1, SDL_SCANCODE_3);
	input.SetMapping(input_coin_2, SDL_SCANCODE_4);
	input.SetMapping(input_coin_3, SDL_SCANCODE_5);
	input.SetMapping(input_pause, SDL_SCANCODE_P);
#endif

	// Setup video
	if (video.Initialise(windowTitle) == 1) { return 1; }

	// Example downloads
	//bus.QueueDownload("./OS6128.rom", 0, true);
	//bus.QueueDownload("./original.rom", 0, true);

	//bus.QueueDownload("./diagnostics.rom", 0, true);
	//bus.QueueDownload("./CPC_PLUS.CPR", 5, true);

	bus.QueueDownload("./cpr/Barbarian II (1990)(Ocean).CPR", 5, true);	   		  // video + text
	//bus.QueueDownload("./cpr/Batman the Movie (1990)(Ocean).CPR", 5, true);	  	  // black border, no protection detected
	//bus.QueueDownload("./cpr/Batman the Movie (1990)(Ocean)[a].CPR", 5, true);  	  // black border, no protection detected
	
	//bus.QueueDownload("./cpr/Burnin' Rubber (1990)(Ocean).CPR", 5, true);	     	  // no execution
	//bus.QueueDownload("./cpr/Crazy Cars 2 (1990)(Titus).CPR", 5, true);       	  // no execution

	//bus.QueueDownload("./cpr/Crazy Cars 2 (1990)(Titus)[a].CPR", 5, true);  		  // black screen, no protection detected, sprite data downloading
	//bus.QueueDownload("./cpr/Dick Tracy (1990)(Titus).CPR", 5, true); 			  // black screen, no protection detected, fixed ACID unlock sequence
	//bus.QueueDownload("./cpr/Enforcer, The (1990)(Trojan).CPR", 5, true);  		  // blue border,  no protection detected, white screen, fixed ACID unlock sequence
	//bus.QueueDownload("./cpr/Fire and Forget 2 (1990)(Titus).CPR", 5, true); 		  // black screen, no protection detected, fixed ACID unlock sequence, sprite data downloading, banding
	//bus.QueueDownload("./cpr/Klax (1990)(Domark).CPR", 5, true);  				  // black screen, no protection detected, no ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/Klax (1990)(Domark)[a].CPR", 5, true); 				  // black screen, no protection detected, no ACID unlock sequence, sprite data downloading

	//bus.QueueDownload("./cpr/Mystical (1990)(Infogrames).CPR", 5, true);			  // no execution, no protection detected, no ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/Navy Seals (1990)(Ocean).CPR", 5, true);				  // no execution, no protection detected, no ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/Navy Seals (1990)(Ocean)[a].CPR", 5, true);			  // no execution, no protection detected, no ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/No Exit (1990)(Tomahawk).CPR", 5, true); 			  // no execution
	//bus.QueueDownload("./cpr/No Exit (1990)(Tomahawk)[a].CPR", 5, true);			  // no execution, no protection detected, no ACID unlock sequence, sprite data downloading

	//bus.QueueDownload("./cpr/Operation Thunderbolt (1990)(Ocean).CPR", 5, true);	  // blue screen,  no protection detected, ACID unlock sequence, stuck at 7CFB
	//bus.QueueDownload("./cpr/Operation Thunderbolt (1990)(Ocean)[a].CPR", 5, true); // blue screen,  no protection detected, ACID unlock sequence, proceeds beyond 7CFB
	//bus.QueueDownload("./cpr/Pang (1990)(Ocean).CPR", 5, true);					  // blue border, white screen, no protection detected, no ACID unlock sequence
	//bus.QueueDownload("./cpr/Pang (1990)(Ocean)[a].CPR", 5, true);				  // blue border, white screen, no protection detected, no ACID unlock sequence, sprite data downloading

	//bus.QueueDownload("./cpr/Panza Kick Boxing (1991)(Loriciel).CPR", 5, true);	  // no execution, no protection detected, no ACID unlock sequence, sprite data downloading		

	//bus.QueueDownload("./cpr/Plotting (1990)(Ocean).CPR", 5, true);				  // black screen, no protection detected, ACID unlock sequence, mode switching
	//bus.QueueDownload("./cpr/Plotting (1990)(Ocean)[a].CPR", 5, true);			  // black screen, no protection detected, ACID unlock sequence, mode switching
	//bus.QueueDownload("./cpr/Pro Tennis Tour (1990)(UBI Soft).CPR", 5, true);       // blue screen,  no protection detected, ACID unlock sequence, secondary palette, stops at frame 11
	//bus.QueueDownload("./cpr/Pro Tennis Tour (1990)(UBI Soft)[a].CPR", 5, true);    // blue screen,  no protection detected, no ACID unlock sequence, secondary palette, stops at frame 11
	//bus.QueueDownload("./cpr/Robocop 2 (1990)(Ocean).CPR", 5, true);                // black screen, no protection detected, ACID unlock sequence, mode switching
	//bus.QueueDownload("./cpr/Robocop 2 (1990)(Ocean)[a].CPR", 5, true); 		      // black screen, no protection detected, ACID unlock sequence, mode switching
	//bus.QueueDownload("./cpr/Skeet Shoot (1990)(Trojan).CPR", 5, true);             // black screen, no protection detected, ACID unlock sequence, mode switching

	//bus.QueueDownload("./cpr/Super Pinball Magic (1991)(Loricel).CPR", 5, true);    // no execution, no protection detected, ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/Switchblade (1990)(Gremlin).CPR", 5, true);            // no execution, no protection detected, no ACID unlock sequence, sprite data downloading, secondary palette

	//bus.QueueDownload("./cpr/Switchblade (1990)(Gremlin)[a].CPR", 5, true);         // blue screen,  no protection detected, no ACID unlock sequence, sprite data downloading, secondary palette
	//bus.QueueDownload("./cpr/Tennis Cup 2 (1990)(Loriciel).CPR", 5, true);          // black screen, no protection detected, ACID unlock sequence

    //bus.QueueDownload("./cpr/Tin Tin on the Moon (1990)(Infogrames).CPR", 5, true); // no execution, no protection detected, ACID unlock sequence, mode switching

	//bus.QueueDownload("./cpr/Wild Streets (1990)(Titus).CPR", 5, true);             // blue screen   no protection detected, ACID unlock sequence, secondary palette, sprite data downloading
	//bus.QueueDownload("./cpr/Wild Streets (1990)(Titus)[a].CPR", 5, true);          // blue screen,  no protection detected, ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/World of Sports (1990)(Epyx).CPR", 5, true);           // black screen, no protection detected, ACID unlock sequence, sprite data downloading
	//bus.QueueDownload("./cpr/World of Sports (1990)(Epyx)[a].CPR", 5, true);        // black screen, no protection detected, ACID unlock sequence, sprite data downloading


#ifdef WIN32
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT) {
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}
#else
	bool done = false;
	while (!done) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT) done = true;
		}
#endif

		video.StartFrame();
		input.Read();
		ImGui::NewFrame();

		//---------------------------------------------------------
		// Build your ImGui windows (control, memory, debug, etc.)
		//---------------------------------------------------------

		//ImGuiIO& io = ImGui::GetIO();
		//ImGuiViewport* viewport = ImGui::GetMainViewport();
		//ImGui::SetWindowPos(windowTitle_Control, viewport->Pos, ImGuiCond_Always);
		//ImGui::SetWindowSize(windowTitle_Control, viewport->Size, ImGuiCond_Always);

		ImGui::Begin(windowTitle_Control);
		ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 150), ImGuiCond_Once);

		if (ImGui::Button("Reset simulation")) {
			resetSim();
		} 
		ImGui::SameLine();
		if (ImGui::Button("Start running")) { run_enable = 1; }
		ImGui::SameLine();
		if (ImGui::Button("Stop running"))  { run_enable = 0; }
		ImGui::SameLine();
		ImGui::Checkbox("RUN", &run_enable);

		ImGui::SliderInt("Run batch size", &batchSize, 1, 250000);

		if (single_step == 1) { single_step = 0; }
		if (ImGui::Button("Single Step")) { 
			run_enable = 0; 
			single_step = 1; 
		}
		ImGui::SameLine();
		if (multi_step == 1)  { multi_step = 0; }
		if (ImGui::Button("Multi Step")) { 
			run_enable = 0; 
			multi_step = 1; 
		}
		ImGui::SliderInt("Multi step amount", &multi_step_amount, 8, 1024);

		if (ImGui::Button("Load ST2"))
    		ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose File", ".st2", ".");
		ImGui::SameLine();
		if (ImGui::Button("Load BIN"))
    		ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose File", ".bin", ".");
		ImGui::End();

		// Debug log window
		console.Draw(windowTitle_DebugLog, &showDebugLog, ImVec2(500, 700));
		ImGui::SetWindowPos(windowTitle_DebugLog, ImVec2(0, 160), ImGuiCond_Once);

		// Memory editor window
		ImGui::Begin("Memory Editor");
		ImGui::SetWindowPos("Memory Editor", ImVec2(0, 160), ImGuiCond_Once);
		ImGui::SetWindowSize("Memory Editor", ImVec2(500, 200), ImGuiCond_Once);
		if (ImGui::BeginTabBar("##memory_editor")) {
			if (ImGui::BeginTabItem("RAM (8MB)")) {
				mem_edit.DrawContents(&top->top__DOT__sdram__DOT__ram[0], 8388608, 0); // 8MB
				ImGui::EndTabItem();
			}
			if (ImGui::BeginTabItem("ASIC RAM (16K)")) {
				mem_edit.DrawContents(&top->top__DOT__asic_inst__DOT__asic_ram[0], 16384, 0); // 16K
				ImGui::EndTabItem();
			}
			if (ImGui::BeginTabItem("VIDEO RAM (16K)")) {
				mem_edit.DrawContents(&top->top__DOT__sdram__DOT__ram[0x3000], 16384, 0); // 16K
				ImGui::EndTabItem();
			}
			ImGui::EndTabBar();
		}
		ImGui::End();

		// CPU Debug window
		ImGui::Begin("CPU Debug");
		ImGui::SetWindowPos("CPU Debug", ImVec2(0, 370), ImGuiCond_Once);
		ImGui::SetWindowSize("CPU Debug", ImVec2(500, 200), ImGuiCond_Once);
		ImGui::Text("Control Signals:");
		ImGui::Text("M1_n:    0x%01X", top->top__DOT__motherboard__DOT__M1_n);
		ImGui::Text("MREQ_n:  0x%01X", top->top__DOT__motherboard__DOT__MREQ_n);
		ImGui::Text("IORQ_n:  0x%01X", top->top__DOT__motherboard__DOT__IORQ_n);
		ImGui::Text("INT_n:   0x%01X", top->top__DOT__motherboard__DOT__INT_n);
		ImGui::Text("RD_n:    0x%01X", top->top__DOT__motherboard__DOT__RD_n);
		ImGui::Text("WR_n:    0x%01X", top->top__DOT__motherboard__DOT__WR_n);
		ImGui::Separator();
		ImGui::Text("Data Path:");
		ImGui::Text("Address:     0x%04X", top->top__DOT__motherboard__DOT__cpu_addr);
		ImGui::Text("Data Out:    0x%02X", top->top__DOT__motherboard__DOT__cpu_dout);
		ImGui::Text("Data In:     0x%02X", top->top__DOT__motherboard__DOT__cpu_din);
		ImGui::Separator();
		ImGui::Text("CPU Status:");
		ImGui::Text("Reset:    0x%01X", top->top__DOT__RESET);  
		ImGui::End();
		
		/*
		ImGui::Begin("Z80 Debugger");
		ImGui::SetWindowPos("Z80 Debugger",  ImVec2(510, 370), ImGuiCond_Once);
		ImGui::SetWindowSize("Z80 Debugger", ImVec2(500, 300), ImGuiCond_Once);
		ImGui::Separator();
		ImGui::SameLine();
		ImGui::End();
		*/

		// VDP Debug window
		ImGui::Begin("VDP Debug");
		ImGui::SetWindowPos("VDP Debug",  ImVec2(0, 710), ImGuiCond_Once);
		ImGui::SetWindowSize("VDP Debug", ImVec2(500, 200), ImGuiCond_Once);
		if (ImGui::BeginTabBar("VDP")) {
			if (ImGui::BeginTabItem("Video Output")) {
				ImGui::Text("Frame: %d", video.count_frame);
				ImGui::Text("R:          0x%02X", top->VGA_R);
				ImGui::Text("G:          0x%02X", top->VGA_G);
				ImGui::Text("B:          0x%02X", top->VGA_B);
				ImGui::Text("HSync:      0x%01X", top->VGA_HS);
				ImGui::Text("VSync:      0x%01X", top->VGA_VS);
				ImGui::Text("HBlank:     0x%01X", top->VGA_HB);
				ImGui::Text("VBlank:     0x%01X", top->VGA_VB);
				ImGui::Separator();
				ImGui::Text("CRTC Internal:");
				ImGui::Text("RS:               0x%04X", top->top__DOT__motherboard__DOT__CRTC__DOT__RS);
				ImGui::Text("Data OUT:         0x%04X", top->top__DOT__motherboard__DOT__CRTC__DOT__DO);
				ImGui::Text("Data IN:          0x%04X", top->top__DOT__motherboard__DOT__CRTC__DOT__DI);
				ImGui::EndTabItem();
			}
			if (ImGui::BeginTabItem("CRTC Registers")) {
				ImGui::Text("R0_h_total:       0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R0_h_total);
				ImGui::Text("R1_h_displayed:   0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R1_h_displayed);
				ImGui::Text("R2_hsync_pos:     0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R2_h_sync_pos);
				ImGui::Text("R3_sync_width:    0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R3_v_sync_width);
				ImGui::Text("R3_h_sync_width:  0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R3_h_sync_width);
				ImGui::Text("R4_v_total:       0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R4_v_total);
				ImGui::Text("R5_v_total_adj:   0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R5_v_total_adj);
	    		ImGui::Text("R6_v_displayed:   0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R6_v_displayed);
				ImGui::Text("R7_vsync_pos:     0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R7_v_sync_pos);
				ImGui::Text("R8_skew:          0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R8_skew);
				ImGui::Text("R8_interlace:     0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R8_interlace);
				ImGui::Text("R9_v_max_line:    0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R9_v_max_line);
				ImGui::Text("R10_cursor_mode:  0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R10_cursor_mode);
				ImGui::Text("R10_cursor_start: 0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R10_cursor_start);
				ImGui::Text("R11_cursor_end:   0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R11_cursor_end);
				ImGui::Text("R12_start_addr_h: 0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R12_start_addr_h);
				ImGui::Text("R13_start_addr_l: 0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R13_start_addr_l);
				ImGui::Text("R14_cursor_h:     0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R14_cursor_h);
				ImGui::Text("R15_cursor_l:     0x%02X", top->top__DOT__motherboard__DOT__CRTC__DOT__R15_cursor_l);
				ImGui::EndTabItem();
			}
			ImGui::EndTabBar();
		}
		ImGui::End();

		// ASIC Debug window
		ImGui::Begin("ASIC Debug");
		ImGui::SetWindowPos("ASIC Debug",  ImVec2(0, 710), ImGuiCond_Once);
		ImGui::SetWindowSize("ASIC Debug", ImVec2(500, 200), ImGuiCond_Once);
		if (ImGui::BeginTabBar("ASIC")) {
			if (ImGui::BeginTabItem("General")) {
				ImGui::Text("ASIC General Status:");
				ImGui::Text("rmr2:              0x%04X", top->top__DOT__asic_inst__DOT__rmr2);
				ImGui::Text("plus_bios_valid:   0x%04X", top->top__DOT__asic_inst__DOT__plus_bios_valid);
				ImGui::Text("pri_irq:           0x%04X", top->top__DOT__asic_inst__DOT__pri_irq);
				ImGui::Text("asic_video_active: 0x%04X", top->top__DOT__asic_inst__DOT__asic_video_active);
				ImGui::Text("config_mode:       0x%04X", top->top__DOT__asic_inst__DOT__config_mode);
				ImGui::Text("mrer_mode:         0x%04X", top->top__DOT__asic_inst__DOT__mrer_mode);
				ImGui::Text("asic_mode:         0x%04X", top->top__DOT__asic_inst__DOT__asic_mode);
				ImGui::Text("asic_enabled:      0x%04X", top->top__DOT__asic_inst__DOT__asic_enabled);
				ImGui::Separator();
				ImGui::Text("ACID:");
				ImGui::Text("state:             0x%04X", top->top__DOT__asic_inst__DOT__acid_inst__DOT__state);
				ImGui::Text("seq_index:         0x%04X", top->top__DOT__asic_inst__DOT__acid_inst__DOT__seq_index);
				ImGui::Text("status_reg:        0x%04X", top->top__DOT__asic_inst__DOT__acid_inst__DOT__status_reg);
				ImGui::Text("next_byte:         0x%04X", top->top__DOT__asic_inst__DOT__acid_inst__DOT__next_byte);
				ImGui::Text("unlock_addr:       0x%04X", top->top__DOT__asic_inst__DOT__acid_inst__DOT__unlock_addr);
				ImGui::Separator();
				ImGui::Text("DMA:");
				ImGui::Text("dma_status_audio:  0x%04X", top->top__DOT__asic_inst__DOT__dma_status_audio);
				ImGui::Text("dma_irq_audio:     0x%04X", top->top__DOT__asic_inst__DOT__dma_irq_audio);
				ImGui::EndTabItem();
			}
			if (ImGui::BeginTabItem("Control Registers")) {
				ImGui::Text("ASIC Control Registers (0x7F00-0x7F0F):");
				ImGui::Text("asic_control:      0x%04X", top->top__DOT__asic_inst__DOT__asic_control);
				ImGui::Text("asic_config:       0x%04X", top->top__DOT__asic_inst__DOT__asic_config);
				ImGui::Text("asic_version:      0x%04X", top->top__DOT__asic_inst__DOT__asic_version);
				ImGui::Separator();
				ImGui::Text("Video Control Registers (0x7F10-0x7F1F):");
				ImGui::Text("video_control:     0x%04X", top->top__DOT__asic_inst__DOT__video_control);
				ImGui::Text("video_status:      0x%04X", top->top__DOT__asic_inst__DOT__video_status);
				ImGui::Text("video_config:      0x%04X", top->top__DOT__asic_inst__DOT__video_config);
				ImGui::Text("video_palette:     0x%04X", top->top__DOT__asic_inst__DOT__video_palette);
				ImGui::Text("video_effect:      0x%04X", top->top__DOT__asic_inst__DOT__video_effect);
				ImGui::Separator();
				ImGui::Text("Sprite Control Registers (0x7F20-0x7F2F):");
				ImGui::Text("sprite_control:    0x%04X", top->top__DOT__asic_inst__DOT__sprite_control);
				ImGui::Text("sprite_status:     0x%04X", top->top__DOT__asic_inst__DOT__sprite_status);
				ImGui::Text("sprite_config:     0x%04X", top->top__DOT__asic_inst__DOT__sprite_config);
				ImGui::Text("sprite_priority:   0x%04X", top->top__DOT__asic_inst__DOT__sprite_priority);
				ImGui::Text("sprite_collision   0x%04X", top->top__DOT__asic_inst__DOT__sprite_collision);
				ImGui::Separator();
				ImGui::Text("Audio Control Registers (0x7F30-0x7F3F):");
				ImGui::Text("audio_control:     0x%04X", top->top__DOT__asic_inst__DOT__audio_control);
				ImGui::Text("audio_config:      0x%04X", top->top__DOT__asic_inst__DOT__audio_config);
				ImGui::Text("audio_volume:      0x%04X", top->top__DOT__asic_inst__DOT__audio_volume);
				ImGui::EndTabItem();
			}
			/*
			if (ImGui::BeginTabItem("Palette Registers")) {
				ImGui::Text("Palette Registers:");
				ImGui::Text("palette_pointer:       0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_pointer);
				ImGui::Text("selected_palette:      0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__selected_palette);
				ImGui::Text("palette_latch_r:       0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_latch_r);
				ImGui::Text("palette_latch_g:       0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_latch_g);
				ImGui::Text("palette_latch_b:       0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_latch_b);
				ImGui::Separator();
				ImGui::Text("Palette Data:");
				ImGui::Text("pal_idx:               0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__pal_idx);
				ImGui::Text("pal_data:              0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__pal_data);
				ImGui::Text("pal_base:              0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__pal_base);
				ImGui::Separator();
				ImGui::Text("alt_palette_en:        0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__alt_palette_en);
				ImGui::Text("effect_en:             0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__effect_en);
				ImGui::Text("raster_effect_en:      0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__raster_effect_en);
				ImGui::Text("split_screen_cfg:      0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__split_screen_cfg);
				ImGui::Text("palette_update_en:     0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_update_en);
				ImGui::Text("palette_bank_sel:      0x%04X", top->top__DOT__cart_inst__DOT__video_inst__DOT__palette_bank_sel);
				ImGui::EndTabItem();
			}
			*/
			ImGui::EndTabBar();
		}
		ImGui::End();

		// Trace window
		ImGui::Begin(windowTitle_Trace);
		ImGui::SetWindowPos(windowTitle_Trace, ImVec2(0, 870), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Trace, ImVec2(500, 150), ImGuiCond_Once);

		if (ImGui::Button("Start FST Export")) { Trace = 1; } ImGui::SameLine();
		if (ImGui::Button("Stop FST Export"))  { Trace = 0; } ImGui::SameLine();
		if (ImGui::Button("Flush FST Export")) { tfp->flush(); } ImGui::SameLine();
		ImGui::Checkbox("Export FST", &Trace);

		ImGui::PushItemWidth(120);
		if (ImGui::InputInt("Deep Level", &iTrace_Deep_tmp, 1, 100, ImGuiInputTextFlags_EnterReturnsTrue))
		{
			top->trace(tfp, iTrace_Deep_tmp);
		}

		if (ImGui::InputText("TraceFilename", Trace_File_tmp, IM_ARRAYSIZE(Trace_File), ImGuiInputTextFlags_EnterReturnsTrue))
		{
			strcpy(Trace_File, Trace_File_tmp); 
			tfp->close();
			if (Trace) tfp->open(Trace_File);
		};
		ImGui::Separator();
		if (ImGui::Button("Save Model")) { save_model(SaveModel_File); } ImGui::SameLine();
		if (ImGui::Button("Load Model")) { restore_model(SaveModel_File); } 
		ImGui::SameLine();
		if (ImGui::InputText("SaveFilename", SaveModel_File_tmp, IM_ARRAYSIZE(SaveModel_File), ImGuiInputTextFlags_EnterReturnsTrue))
		{
			strcpy(SaveModel_File, SaveModel_File_tmp);
		}
		ImGui::End();

		int windowX = 550;
		int windowWidth = (VGA_WIDTH * VGA_SCALE_X) + 24;
		int windowHeight = (VGA_HEIGHT * VGA_SCALE_Y) + 90;

		// Video window
		ImGui::Begin(windowTitle_Video);
		ImGui::SetWindowPos(windowTitle_Video, ImVec2(windowX, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Video, ImVec2(windowWidth, windowHeight), ImGuiCond_Once);

		ImGui::SetNextItemWidth(400);
		ImGui::SliderFloat("Zoom", &vga_scale, 1, 8); 
		ImGui::SameLine();
		ImGui::SetNextItemWidth(200);
		ImGui::SliderInt("Rotate", &video.output_rotate, -1, 1);
		ImGui::SameLine();
		ImGui::Checkbox("Flip V", &video.output_vflip);

		ImGui::Text("main_time: %lu frame_count: %d sim FPS: %f", main_time, video.count_frame, video.stats_fps);
		ImGui::Image(video.texture_id, ImVec2(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y));
		ImGui::End();

		// File dialog
		if (ImGuiFileDialog::Instance()->Display("ChooseFileDlgKey")) {
			if (ImGuiFileDialog::Instance()->IsOk()) {
				std::string filePathName = ImGuiFileDialog::Instance()->GetFilePathName();
				std::string filePath = ImGuiFileDialog::Instance()->GetCurrentPath();
				bus.QueueDownload(filePathName, 1, 1);
			}
			ImGuiFileDialog::Instance()->Close();
		}

#ifndef DISABLE_AUDIO
		// Audio window
		ImGui::Begin(windowTitle_Audio);
		ImGui::SetWindowPos(windowTitle_Audio, ImVec2(windowX, windowHeight), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Audio, ImVec2(windowWidth, 250), ImGuiCond_Once);

		if (run_enable) {
			audio.CollectDebug((signed short)top->AUDIO_L, (signed short)top->AUDIO_R);
		}
		int channelWidth = (windowWidth / 2) - 16;
		ImPlot::CreateContext();
		if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImGui::SameLine();
		if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImPlot::DestroyContext();
		ImGui::End();
#endif

		//----------------------------------------------------------
		// Render ImGui
		//----------------------------------------------------------
		ImGui::Render();
		video.UpdateTexture();

		// Handle user inputs
		top->inputs = 0;
		for (int i = 0; i < input.inputCount; i++) {
			if (input.inputs[i]) { top->inputs |= (1 << i); }
		}

		//----------------------------------------------------------
		// Actually run the simulation in batches
		//----------------------------------------------------------
		if (run_enable) {
			for (int step = 0; step < batchSize; step++) {
				verilate();
			}
		}
		else {
			if (single_step) {
				verilate();
			}
			if (multi_step) {
				for (int step = 0; step < multi_step_amount; step++) {
					verilate();
				}
			}
		}
	}

#ifndef DISABLE_AUDIO
	audio.CleanUp();
#endif
	video.CleanUp();
	input.CleanUp();
	

	return 0;
}