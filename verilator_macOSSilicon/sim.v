`timescale 1ns/1ns

module top (
    input  wire        clk_48,
    input reg          reset,
    input              inputs,
    
    // Video output
    output wire [5:0]  VGA_R,
    output wire [5:0]  VGA_G,
    output wire [5:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_HB,
    output wire        VGA_VB,
    
    input       [10:0] ps2_key,

    input        ioctl_download,
    input        ioctl_upload,
    input        ioctl_wr,
    input        ioctl_rd,
    input [24:0] ioctl_addr,
    input [7:0]  ioctl_dout,
    input [7:0]  ioctl_din,
    input [7:0]  ioctl_index,
    output reg   ioctl_wait
);

reg ce_pix;

reg plus_rom_loaded = 0;
reg plus_valid = 0;
reg old_download = 0;
//----------------------------------------------------------------
// Keyboard logic (unchanged)
reg         key_strobe;
wire        key_pressed;
wire        key_extended;
wire  [7:0] key_code;
wire        upcase;

assign key_extended = ps2_key[8];
assign key_pressed  = ps2_key[9];
assign key_code     = ps2_key[7:0];

always @(posedge clk_48) begin
    reg old_state;
    old_state <= ps2_key[10];

    if(old_state != ps2_key[10]) begin
       key_strobe <= ~key_strobe;
    end
end
//----------------------------------------------------------------

// Clock dividers for different system components
reg ce_ref, ce_u765;
reg ce_16;
reg [2:0] div;
initial div = 0;
always @(posedge clk_48) begin
	div     <= div + 1'd1;

	ce_ref  <= !div;
	ce_u765 <= !div[2:0]; //8 MHz
	ce_16   <= !div[1:0]; //16 MHz
end

// Generate pixel clock similar to the real implementation
// But simplified for simulation
reg [1:0] pixel_div;
initial pixel_div = 0;

always @(posedge clk_48) begin
    if (ce_16) begin
        pixel_div <= pixel_div + 1'd1;
        // Generate ce_pix at 1/4 of ce_16 rate, more visible for simulation
        ce_pix <= (pixel_div == 0);
    end
    else begin
        ce_pix <= 0;
    end
end

//----------------------------------------------------------------
// Reset logic
reg RESET = 1;
reg rom_loaded = 0;
always @(posedge clk_48) begin
    reg ioctl_downlD;
    ioctl_downlD <= ioctl_download;
    
    // Only come out of reset when ROM download is complete
    // rom_loaded is set when we detect the end of ioctl_download
    if (ioctl_downlD & ~ioctl_download) rom_loaded <= 1;
    
    // Stay in reset until ROM is loaded and user is not pressing reset
    RESET <= reset | ~rom_loaded;
end
//----------------------------------------------------------------

// Memory loading logic - improved to match Amstrad.sv logic
wire        rom_download = ioctl_download && (ioctl_index[4:0] < 4);
wire        tape_download = ioctl_download && (ioctl_index == 4);
wire        plus_cpr_download = ioctl_download && (ioctl_index == 5);  // F5 - CPR files
wire        plus_bin_download = ioctl_download && (ioctl_index == 6);  // F6 - BIN files
wire        plus_download = plus_cpr_download | plus_bin_download;

reg         boot_wr = 0;
reg  [22:0] boot_a;
reg   [1:0] boot_bank;
reg   [7:0] boot_dout;
reg [255:0] rom_map = '0;
reg [8:0]   page = 0;
reg         combo = 0;

// Define the ROM block addresses based on Amstrad.sv logic
localparam ROM_OS_ADDR     = 9'h000; // OS (0,4)
localparam ROM_BASIC_ADDR  = 9'h100; // BASIC (1,5)
localparam ROM_AMSDOS_ADDR = 9'h107; // AMSDOS (2,6)
localparam ROM_MF2_ADDR    = 9'h0ff; // MF2 (3,7)

always @(posedge clk_48) begin
	if((rom_download | plus_download) & ioctl_wr) begin
		boot_wr <= 1;
		boot_dout <= ioctl_dout;
		boot_a[13:0] <= ioctl_addr[13:0];
				
		if(ioctl_index) begin
			if (plus_download) begin
				// Plus ROM is loaded into dedicated area in the second half of memory
				boot_a[22]    <= 1'b1;   // Use second half of memory
				boot_a[21:14] <= ioctl_addr[21:14];  // Use file address directly
				boot_bank     <= 1'b0;   // Always use bank 0 for Plus ROMs
			end else begin
				boot_a[22]    <= page[8];
				boot_a[21:14] <= page[7:0] + ioctl_addr[21:14];
				boot_bank     <= {1'b0, &ioctl_index[7:6]};
			end
		end
		else begin
			case(ioctl_addr[24:14])
				0,4: boot_a[22:14] <= 9'h000; //OS
				1,5: boot_a[22:14] <= 9'h100; //BASIC
				2,6: boot_a[22:14] <= 9'h107; //AMSDOS
				3,7: boot_a[22:14] <= 9'h0ff; //MF2
				default: boot_wr <= 0;
			endcase

			case(ioctl_addr[24:14])
				0,1,2,3: boot_bank <= 0; //CPC6128
				4,5,6,7: boot_bank <= 1; //CPC664
			endcase
		end
	end
	else if(ce_ref && boot_wr) begin
		boot_wr <= 0;
		// load expansion ROM into both banks if manually loaded or boot name is boot.eXX
		if((ioctl_index[7:6]==1 || ioctl_index[5:0]) && !boot_bank) begin
			boot_bank <= 1;
			boot_wr <= 1;
		end
		else begin
			if(boot_a[22]) rom_map[boot_a[21:14]] <= 1;
			if(combo && &boot_a[13:0]) begin
				combo <= 0;
				page  <= 9'h1FF;
			end
		end
	end

	old_download <= ioctl_download;
	if(~old_download & ioctl_download & (rom_download | plus_download)) begin
		if(ioctl_index) begin
			if (plus_download) begin
				// For cartridge files, use the file address directly
				page <= ioctl_addr[21:14];
				combo <= 0;
			end
		end
	end
	
	// Update Plus ROM loaded status
	if(~old_download & plus_download) begin
		plus_rom_loaded <= 0; // Reset when starting download
	end
	else if(~ioctl_download & plus_download & plus_valid) begin
		plus_rom_loaded <= 1; // Set only when valid Plus ROM is loaded
	end
end

// CPU and core signals
wire [15:0] cpu_addr;
wire [7:0]  cpu_dout;
wire        mem_rd;
wire        mem_wr;
wire        iorq;
wire        rd;
wire        wr;
wire        m1;
wire        phi_n;
wire        phi_en_n;
wire        phi_en_p = 1'b1;  // Define as a wire with initial value
wire        mreq = 1'b0;      // Define as a wire with initial value
wire        tape_motor;
wire        cursor;
wire        key_nmi;
wire        key_reset;
wire [6:0]  joy1 = 7'h00;     // 7-bit signal as per module definition
wire [6:0]  joy2 = 7'h00;     // 7-bit signal as per module definition
wire [1:0]  mode = 0;
wire        NMI = 0;
wire        IRQ = 0;
wire [9:0]  Fn = 10'h000;     // 10-bit signal as per module definition

// Video signals
wire        hbl;
wire        vbl;
wire        hs;
wire        vs;
wire [1:0]  r;
wire [1:0]  g;
wire [1:0]  b;
wire        VGA_F1;

// Memory interface signals
wire [7:0]  ram_dout;
wire [22:0] ram_a;
wire [7:0]  cpu_din = ram_dout;

// Video memory interface signals
wire [14:0] vram_addr;
wire [15:0] vram_dout;

// Flag for setting model (0 for CPC6128, 1 for CPC464)
reg model = 1;

// Audio signals - not connected in verilator sim
wire [7:0]  audio_l, audio_r;

// Stub signals for unused components
wire        tape_play = 0;
wire        tape_rec;
wire [7:0]  tape_dout = 8'h00;
wire [22:0] tape_play_addr = 0;
wire [22:0] tape_last_addr = 0;
wire        tape_data_req = 0;
wire        tape_data_ack = 0;
wire [7:0]  tape_din = 8'h00;
wire        tape_wr = 0;
wire        tape_wr_ack = 0;

// Add back Amstrad motherboard instantiation
Amstrad_motherboard motherboard
(
    .reset(RESET),
    .clk(clk_48),
    .ce_16(ce_16),

    .joy1(joy1),
    .joy2(joy2),
    .right_shift_mod(1'b0),
    .keypad_mod(1'b0),
    .ps2_key(ps2_key),
    .ps2_mouse(25'd0),
    .key_nmi(key_nmi),
    .key_reset(key_reset),
    .Fn(Fn),

    .ppi_jumpers(4'd0),
    .crtc_type(1'b0),
    .sync_filter(1'b0),
    .no_wait(1'b0),
    .gx4000_mode(1'b0),
    .plus_mode(1'b0),
    .plus_rom_loaded(1'b0),

    .tape_in(1'b0),
    .tape_out(),
    .tape_motor(tape_motor),

    .audio_l(audio_l),
    .audio_r(audio_r),

    .mode(mode),

    .red(r),
    .green(g),
    .blue(b),
    .hblank(hbl),
    .vblank(vbl),
    .hsync(hs),
    .vsync(vs),
    .field(VGA_F1),

    .vram_din(vram_dout),
    .vram_addr(vram_addr),

    .rom_map(rom_map),
    .ram64k(model),
    .mem_addr(ram_a),
    .mem_rd(mem_rd),
    .mem_wr(mem_wr),

    .phi_n(phi_n),
    .phi_en_n(phi_en_n),
    .phi_en_p(phi_en_p),
    .cpu_addr(cpu_addr),
    .cpu_dout(cpu_dout),
    .cpu_din(cpu_din),
    .iorq(iorq),
    .mreq(mreq),
    .rd(rd),
    .wr(wr),
    .m1(m1),
    .irq(IRQ),
    .nmi(NMI),
    .cursor(cursor)
);

// Video output conversion - expanding 2-bit color to 6-bit
assign VGA_R = {r, r, r};
assign VGA_G = {g, g, g};
assign VGA_B = {b, b, b};
assign VGA_HS = ~hs;  // Invert for VGA
assign VGA_VS = ~vs;  // Invert for VGA
assign VGA_HB = hbl;
assign VGA_VB = vbl;

mock_sdram sdram (
    // SDRAM interface pins (not used in simulation but needed for interface compliance)
    .SDRAM_DQ(),
    .SDRAM_A(),
    .SDRAM_DQML(),
    .SDRAM_DQMH(),
    .SDRAM_BA(),
    .SDRAM_nCS(),
    .SDRAM_nWE(),
    .SDRAM_nRAS(),
    .SDRAM_nCAS(),
    .SDRAM_CLK(),
    .SDRAM_CKE(),
    
    // Actual signals used in simulation - match the logic in Amstrad.sv
    .init(~rom_loaded),
    .clk(clk_48),
    .clkref(ce_ref),

    // Use exact same logic as in Amstrad.sv
    .oe(RESET ? 1'b0 : mem_rd),
    .we(RESET ? boot_wr : mem_wr),
    .addr(RESET ? boot_a : ram_a),  // Make sure address is correct
    .bank(RESET ? boot_bank : {1'b0, model}),
    .din(RESET ? boot_dout : cpu_dout),
    .dout(ram_dout),

    // Video memory access
	.vram_addr({2'b10,vram_addr,1'b0}),
	.vram_dout(vram_dout),

    // Tape access (not used in verilator sim)
    .tape_addr(),
    .tape_din(0),
    .tape_dout(),
    .tape_wr(0),
    .tape_wr_ack(),
    .tape_rd(0),
    .tape_rd_ack()
);

endmodule