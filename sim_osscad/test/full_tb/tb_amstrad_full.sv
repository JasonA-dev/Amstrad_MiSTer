`timescale 1ns / 1ps

`define STUB_MODULES

module tb_amstrad_full;

    // Clock and reset
    reg CLK_50M = 0;
    reg RESET = 1;
    
    // HPS interface
    wire [48:0] HPS_BUS;
    
    // Video output
    wire CLK_VIDEO;
    wire CE_PIXEL;
    wire [12:0] VIDEO_ARX;
    wire [12:0] VIDEO_ARY;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire VGA_HS, VGA_VS, VGA_DE;
    wire VGA_F1;
    wire [1:0] VGA_SL;
    wire VGA_SCALER;
    wire VGA_DISABLE;
    wire HDMI_FREEZE;
    
    // HDMI input dimensions 
    reg [11:0] HDMI_WIDTH = 1920;
    reg [11:0] HDMI_HEIGHT = 1080;
    
    // Audio
    wire [15:0] AUDIO_L, AUDIO_R;
    wire AUDIO_S;
    wire [1:0] AUDIO_MIX;
    reg CLK_AUDIO = 0;   // 24.576 MHz
    
    // Other interfaces
    wire [3:0] ADC_BUS;
    wire SD_SCK, SD_MOSI, SD_CS;
    wire SD_MISO = 0;
    wire SD_CD = 0;
    
    // DDR/SDRAM interfaces (not used in simulation)
    wire DDRAM_CLK;
    wire DDRAM_BUSY = 0;
    wire [7:0] DDRAM_BURSTCNT;
    wire [28:0] DDRAM_ADDR;
    wire [63:0] DDRAM_DOUT = 0;
    wire DDRAM_DOUT_READY = 0;
    wire DDRAM_RD;
    wire [63:0] DDRAM_DIN;
    wire [7:0] DDRAM_BE;
    wire DDRAM_WE;
    
    wire SDRAM_CLK;
    wire SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire [1:0] SDRAM_BA;
    wire [15:0] SDRAM_DQ;  // Bidirectional
    wire SDRAM_DQML;
    wire SDRAM_DQMH;
    wire SDRAM_nCS;
    wire SDRAM_nCAS;
    wire SDRAM_nRAS;
    wire SDRAM_nWE;
    
    // UART interfaces
    wire UART_CTS = 0;
    reg UART_RXD = 1; 
    wire UART_RTS, UART_TXD, UART_DTR;
    wire UART_DSR = 0;
    
    // User port
    reg [6:0] USER_IN = 7'h7F;
    wire [6:0] USER_OUT;
    
    // OSD Status
    reg OSD_STATUS = 0;
    
    // Buttons and joysticks
    wire [1:0] BUTTONS;
    
    // Assign bidirectional signals using weak pullup/pulldown
    assign (weak0, weak1) SDRAM_DQ = 16'hZZZZ;
    assign (weak0, weak1) ADC_BUS = 4'hZ;

    // Generate clocks
    always #10 CLK_50M = ~CLK_50M;      // 50 MHz (period = 20ns)
    always #20.345 CLK_AUDIO = ~CLK_AUDIO; // 24.576 MHz (period = 40.69ns)
    
    // HPS_BUS virtual interface
    reg [63:0] status = 0;
    reg [15:0] joystick1 = 0;
    reg [15:0] joystick2 = 0;
    
    // Simulation control for the HPS BUS (mimicking the MiSTer framework)
    initial begin
        // Wait for reset sequence
        #100;
        
        // Set GX4000 mode (bit 32 in status)
        status[32] = 1;
        
        // Pass settings to the DUT
        hps.status_in = status;
        hps.status_set = 1;
        #10;
        hps.status_set = 0;
    end
    
    // HPS_IO mock
    hps_io #(.CONF_STR("")) hps(
        .clk_sys(CLK_50M),
        .HPS_BUS(HPS_BUS),
        .status(status),
        .status_in(status),
        .status_set(1'b0),
        .joystick_0(joystick1),
        .joystick_1(joystick2)
    );

    // Module under test
    emu uut (
        .CLK_50M(CLK_50M),
        .RESET(RESET),
        .HPS_BUS(HPS_BUS),
        .CLK_VIDEO(CLK_VIDEO),
        .CE_PIXEL(CE_PIXEL),
        .VIDEO_ARX(VIDEO_ARX),
        .VIDEO_ARY(VIDEO_ARY),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_DE(VGA_DE),
        .VGA_F1(VGA_F1),
        .VGA_SL(VGA_SL),
        .VGA_SCALER(VGA_SCALER),
        .VGA_DISABLE(VGA_DISABLE),
        .HDMI_WIDTH(HDMI_WIDTH),
        .HDMI_HEIGHT(HDMI_HEIGHT),
        .HDMI_FREEZE(HDMI_FREEZE),
        .CLK_AUDIO(CLK_AUDIO),
        .AUDIO_L(AUDIO_L),
        .AUDIO_R(AUDIO_R),
        .AUDIO_S(AUDIO_S),
        .AUDIO_MIX(AUDIO_MIX),
        .ADC_BUS(ADC_BUS),
        .SD_SCK(SD_SCK),
        .SD_MOSI(SD_MOSI),
        .SD_MISO(SD_MISO),
        .SD_CS(SD_CS),
        .SD_CD(SD_CD),
        .DDRAM_CLK(DDRAM_CLK),
        .DDRAM_BUSY(DDRAM_BUSY),
        .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
        .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT),
        .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
        .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN),
        .DDRAM_BE(DDRAM_BE),
        .DDRAM_WE(DDRAM_WE),
        .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_A(SDRAM_A),
        .SDRAM_BA(SDRAM_BA),
        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_DQML(SDRAM_DQML),
        .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_nCS(SDRAM_nCS),
        .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nWE(SDRAM_nWE),
        .UART_CTS(UART_CTS),
        .UART_RTS(UART_RTS),
        .UART_RXD(UART_RXD),
        .UART_TXD(UART_TXD),
        .UART_DTR(UART_DTR),
        .UART_DSR(UART_DSR),
        .USER_IN(USER_IN),
        .USER_OUT(USER_OUT),
        .OSD_STATUS(OSD_STATUS),
        .BUTTONS(BUTTONS)
    );
    
    // Test sequence
    initial begin
        $display("Starting Amstrad CPC / GX4000 Testbench");
        
        // Initialize simulation
        RESET = 1;
        #100;
        RESET = 0;
        
        // Wait for system to initialize
        #1000;
        
        // Run for 10ms to see video output
        $display("Running extended simulation...");
        #10000000;
        
        // End simulation
        $display("Testbench completed");
        $finish;
    end
    
    // Create VCD file
    initial begin
        $dumpfile("amstrad_full.vcd");
        $dumpvars(0, tb_amstrad_full);
    end
    
    // Monitor video signals
    initial begin
        $monitor("Time=%0t: VGA_HS=%b VGA_VS=%b VGA_DE=%b", $time, VGA_HS, VGA_VS, VGA_DE);
    end

endmodule

// HPS_IO mock module
module hps_io #(parameter CONF_STR="", parameter VDNUM=0) (
    input             clk_sys,
    inout      [48:0] HPS_BUS,
    
    output reg [63:0] status,
    input      [63:0] status_in,
    input             status_set,
    
    output     [15:0] joystick_0,
    output     [15:0] joystick_1,
    output     [15:0] joystick_2,
    output     [15:0] joystick_3,
    
    output     [10:0] ps2_key,
    output     [24:0] ps2_mouse,
    
    output            ioctl_download,
    output     [7:0]  ioctl_index,
    output            ioctl_wr,
    output    [24:0]  ioctl_addr,
    output    [7:0]   ioctl_dout,
    output    [31:0]  ioctl_file_ext,
    input             ioctl_wait,
    
    output            forced_scandoubler,
    output            gamma_bus,

    // SD card interface
    output reg        img_mounted,
    output            img_readonly,
    output     [63:0] img_size,
    
    output            sd_rd,
    output            sd_wr,
    output            sd_ack,
    output     [7:0]  sd_buff_addr,
    output     [15:0] sd_req_type,
    output     [7:0]  sd_buff_dout,
    output            sd_buff_wr,
    output     [31:0] sd_lba,
    
    output     [1:0]  buttons
);
    // Mock implementation for simulation
    assign joystick_0 = 16'h0;
    assign joystick_1 = 16'h0;
    assign joystick_2 = 16'h0;
    assign joystick_3 = 16'h0;
    
    assign ps2_key = 11'h0;
    assign ps2_mouse = 25'h0;
    
    assign ioctl_download = 0;
    assign ioctl_index = 8'h0;
    assign ioctl_wr = 0;
    assign ioctl_addr = 25'h0;
    assign ioctl_dout = 8'h0;
    assign ioctl_file_ext = 32'h0;
    
    assign forced_scandoubler = 0;
    assign gamma_bus = 0;
    
    assign img_readonly = 0;
    assign img_size = 64'h0;
    
    assign sd_rd = 0;
    assign sd_wr = 0;
    assign sd_ack = 0;
    assign sd_buff_addr = 8'h0;
    assign sd_req_type = 16'h0;
    assign sd_buff_dout = 8'h0;
    assign sd_buff_wr = 0;
    assign sd_lba = 32'h0;
    
    assign buttons = 2'h0;

    // Update status based on input
    always @(posedge clk_sys) begin
        if (status_set) status <= status_in;
    end
    
    // Bidirectional HPS_BUS handling
    reg [48:0] hps_bus_out = 0;
    
    // Simple bidirectional handling
    assign HPS_BUS = hps_bus_out;
endmodule

// Stub modules for problematic components
`ifdef STUB_MODULES

// YM2149 stub
module YM2149 (
    input             CLK,
    input             CE,
    input             RESET,
    input             BDIR,
    input             BC1,
    input      [7:0]  DI,
    output     [7:0]  DO,
    output     [7:0]  CHANNEL_A,
    output     [7:0]  CHANNEL_B,
    output     [7:0]  CHANNEL_C,
    output     [5:0]  ACTIVE,
    input      [7:0]  SEL,
    input             MODE,
    input      [1:0]  PRESCALER
);
    // Simple stub implementation
    assign DO = 8'h00;
    assign CHANNEL_A = 8'h00;
    assign CHANNEL_B = 8'h00;
    assign CHANNEL_C = 8'h00;
    assign ACTIVE = 6'h00;
endmodule

// HID stub
module hid (
    input             CLK,
    input             CE,
    input             reset,
    input      [31:0] joystick_0,
    input      [31:0] joystick_1,
    input      [15:0] joystick_analog_0,
    input      [15:0] joystick_analog_1,
    input      [7:0]  paddle_0,
    input      [7:0]  paddle_1,
    input      [8:0]  spinner_0,
    input      [8:0]  spinner_1,
    input      [10:0] ps2_key,
    input      [24:0] ps2_mouse,
    input      [1:0]  buttons,
    output     [7:0]  out,
    input             strobe
);
    // Stub implementation
    assign out = 8'h00;
endmodule

// Mouse_axis stub
module mouse_axis (
    input        clk,
    input        reset,
    input  [8:0] delta,
    input        strobe,
    output [7:0] pos
);
    // Stub implementation
    assign pos = 8'h00;
endmodule

// Stub for AMSTRAD_motherboard
module Amstrad_motherboard (
    input             clock,
    input             CLK_VIDEO,
    input             CLK_CPU_n,
    input             CLK_CPU_p,
    input             clk4_en,
    input             clk4_en_n,
    input             cclk_en_n,
    input             cclk_en_p,
    input             reset_n,
    input             RESET_n,
    input             RESET,
    input             key_strobe,
    input      [7:0]  key_data,
    input             sel15khz,
    input             center,
    input             video_mode,
    input      [1:0]  scale,
    output     [2:0]  resolution,
    output            phi_n,
    output            phi_en_n,
    output     [15:0] addr,
    output     [7:0]  ram_din,
    input      [7:0]  ram_dout,
    output            ram_we,
    output            ram_rd,
    output     [7:0]  cpu_dout,
    input      [7:0]  cpu_din,
    output            m1,
    output            iorq,
    output            rd,
    output            wr,
    output            cursor,
    output            vblank,
    output            hblank,
    output            hb_out,
    output            vb_out,
    output            hblank_falling,
    output            vblank_falling,
    input             CRT,
    input      [1:0]  CHROMA,
    input             palette_download,
    input      [1:0]  palette_index,
    input             palette_strobe,
    input      [15:0] palette_data,
    input      [1:0]  mode,
    input             plus,
    input             vid_mode,
    input             upper,
    input             lower,
    output            hs,
    output            vs,
    output     [8:0]  r,
    output     [8:0]  g,
    output     [8:0]  b,
    input      [9:0]  audio_l,
    input      [9:0]  audio_r,
    output     [9:0]  audio_l_out,
    output     [9:0]  audio_r_out,
    input      [8:0]  joystick1,
    input      [8:0]  joystick2,
    input             mod_plus4, 
    input             use_mouse,
    input      [7:0]  mouse_x,
    input      [7:0]  mouse_y,
    input      [7:0]  mouse_buttons,
    input      [1:0]  mouse_type,
    input             paletteRW,
    input      [1:0]  paletteAddr,
    input      [7:0]  cpu_addr,
    input             romen_n
);
    // Stub implementation
    assign phi_n = 1'b0;
    assign phi_en_n = 1'b0;
    assign addr = 16'h0000;
    assign ram_din = 8'h00;
    assign ram_we = 1'b0;
    assign ram_rd = 1'b0;
    assign cpu_dout = 8'h00;
    assign m1 = 1'b0;
    assign iorq = 1'b0;
    assign rd = 1'b0;
    assign wr = 1'b0;
    assign cursor = 1'b0;
    assign vblank = 1'b0;
    assign hblank = 1'b0;
    assign hb_out = 1'b0;
    assign vb_out = 1'b0;
    assign hblank_falling = 1'b0;
    assign vblank_falling = 1'b0;
    assign hs = 1'b0;
    assign vs = 1'b0;
    assign r = 9'h000;
    assign g = 9'h000;
    assign b = 9'h000;
    assign audio_l_out = 10'h000;
    assign audio_r_out = 10'h000;
    assign resolution = 3'b000;
endmodule

// GX4000_ASIC stub
module GX4000_ASIC (
    input             clk,
    input             ce_4,
    input             reset,
    input      [15:0] addr,
    output     [7:0]  data_out,
    input      [7:0]  data_in,
    input             wr,
    input             rd,
    input             iorq,
    input             m1,
    output     [1:0]  rom_bank,
    output     [7:0]  ram_bank,
    output            rom_enable,
    output            ram_enable,
    output            cart_rd,
    input             vs_n,
    input             hs_n,
    input      [3:0]  r_in,
    input      [3:0]  g_in,
    input      [3:0]  b_in,
    output     [3:0]  r_out,
    output     [3:0]  g_out,
    output     [3:0]  b_out,
    output     [7:0]  joy1_dir,
    output     [1:0]  joy1_btn,
    output     [7:0]  joy2_dir,
    output     [1:0]  joy2_btn
);
    // Stub implementation
    assign data_out = 8'h00;
    assign rom_bank = 2'b00;
    assign ram_bank = 8'h00;
    assign rom_enable = 1'b0;
    assign ram_enable = 1'b0;
    assign cart_rd = 1'b0;
    assign r_out = 4'h0;
    assign g_out = 4'h0;
    assign b_out = 4'h0;
    assign joy1_dir = 8'h00;
    assign joy1_btn = 2'b00;
    assign joy2_dir = 8'h00;
    assign joy2_btn = 2'b00;
endmodule

`endif 