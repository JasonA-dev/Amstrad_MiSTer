`timescale 1ns / 1ps

// This testbench wraps around the existing Amstrad.sv module to test it without modifications
module tb_amstrad_wrapper;

    // Clock and reset
    reg CLK_50M = 0;
    reg RESET = 1;
    
    // HPS interface (simplified)
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
    
    // DDR/SDRAM interfaces (not used in simulation but required for the module)
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
    
    // Buttons
    wire [1:0] BUTTONS;
    
    // Assign bidirectional signals using weak pullup/pulldown
    assign (weak0, weak1) SDRAM_DQ = 16'hZZZZ;
    assign (weak0, weak1) ADC_BUS = 4'hZ;

    // Generate clocks
    always #10 CLK_50M = ~CLK_50M;      // 50 MHz (period = 20ns)
    always #20.345 CLK_AUDIO = ~CLK_AUDIO; // 24.576 MHz (period = 40.69ns)
    
    // HPS_BUS virtual interface
    reg [63:0] status = 0;
    reg [6:0] joy1 = 0;
    reg [6:0] joy2 = 0;
    
    // Simulation control for the HPS BUS
    initial begin
        // Wait for reset sequence
        #100;
        
        // Set Plus/GX4000 mode (bit 21 in status)
        status[21] = 1;
        
        // Pass settings to the HPS_IO
        hps.status_in = status;
        hps.status_set = 1;
        #10;
        hps.status_set = 0;
    end
    
    // Instantiate the HPS_IO mock
    hps_io #(.CONF_STR("")) hps(
        .clk_sys(CLK_50M),
        .HPS_BUS(HPS_BUS),
        .status(status),
        .status_in(status),
        .status_set(1'b0),
        .joystick_0(joy1),
        .joystick_1(joy2),
        
        // Other necessary signals to satisfy the interface
        .ps2_key(),
        .ps2_mouse(),
        .ioctl_download(1'b0),
        .ioctl_index(8'd0),
        .ioctl_wr(1'b0),
        .ioctl_addr(25'd0),
        .ioctl_dout(8'd0),
        .ioctl_file_ext(32'd0),
        .ioctl_wait(1'b0),
        .forced_scandoubler(),
        .gamma_bus(),
        .img_mounted(),
        .img_readonly(1'b0),
        .img_size(64'd0),
        .sd_lba(),
        .sd_rd(),
        .sd_wr(),
        .sd_ack(1'b0),
        .sd_buff_addr(9'd0),
        .sd_buff_dout(8'd0),
        .sd_buff_din(),
        .sd_buff_wr(1'b0),
        .buttons(2'd0),
        .status_menumask(64'd0)
    );

    // Instantiate the Amstrad module
    Amstrad amstrad_inst(
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
        $display("Starting Amstrad Wrapper Testbench");
        
        // Initialize simulation
        RESET = 1;
        #100;
        RESET = 0;
        
        // Wait for system to initialize
        #1000;
        
        // Run simulation for a reasonable time to see video output
        $display("Running simulation...");
        #10000000;
        
        // End simulation
        $display("Testbench completed");
        $finish;
    end
    
    // Create VCD file for waveform viewing
    initial begin
        $dumpfile("amstrad_wrapper.vcd");
        $dumpvars(0, tb_amstrad_wrapper);
    end
    
    // Monitor important signals
    initial begin
        $monitor("Time=%0t: VGA_HS=%b VGA_VS=%b VGA_DE=%b", $time, VGA_HS, VGA_VS, VGA_DE);
    end

endmodule

// HPS_IO mock module to provide the interface expected by Amstrad.sv
module hps_io #(parameter CONF_STR="", parameter VDNUM=0) (
    input             clk_sys,
    inout      [48:0] HPS_BUS,
    
    output reg [63:0] status,
    input      [63:0] status_in,
    input             status_set,
    output     [63:0] status_menumask,
    
    output     [6:0]  joystick_0,
    output     [6:0]  joystick_1,
    
    output     [10:0] ps2_key,
    output     [24:0] ps2_mouse,
    
    output     [1:0]  buttons,
    
    output            ioctl_download,
    output     [7:0]  ioctl_index,
    output            ioctl_wr,
    output    [24:0]  ioctl_addr,
    output    [7:0]   ioctl_dout,
    output    [31:0]  ioctl_file_ext,
    input             ioctl_wait,
    
    output            forced_scandoubler,
    output    [21:0]  gamma_bus,
    
    // SD card interface
    output     [1:0]  img_mounted,
    output            img_readonly,
    output    [63:0]  img_size,
    output    [31:0]  sd_lba,
    output     [1:0]  sd_rd,
    output     [1:0]  sd_wr,
    input             sd_ack,
    input      [8:0]  sd_buff_addr,
    input      [7:0]  sd_buff_dout,
    output     [7:0]  sd_buff_din,
    input             sd_buff_wr
);
    // Simple implementation to support the interface
    always @(posedge clk_sys) begin
        if (status_set) status <= status_in;
    end
    
    // Assign default values to the outputs
    assign joystick_0 = 7'h00;
    assign joystick_1 = 7'h00;
    assign ps2_key = 11'h000;
    assign ps2_mouse = 25'h0000000;
    assign buttons = 2'b00;
    assign ioctl_download = 1'b0;
    assign ioctl_index = 8'h00;
    assign ioctl_wr = 1'b0;
    assign ioctl_addr = 25'h0000000;
    assign ioctl_dout = 8'h00;
    assign ioctl_file_ext = 32'h00000000;
    assign forced_scandoubler = 1'b0;
    assign gamma_bus = 22'h000000;
    assign img_mounted = 2'b00;
    assign img_readonly = 1'b0;
    assign img_size = 64'h0000000000000000;
    assign sd_lba = 32'h00000000;
    assign sd_rd = 2'b00;
    assign sd_wr = 2'b00;
    assign sd_buff_din = 8'h00;
    assign status_menumask = 64'h0000000000000000;
    
    // Assign HPS_BUS as output
    assign HPS_BUS = 49'hz;
endmodule 