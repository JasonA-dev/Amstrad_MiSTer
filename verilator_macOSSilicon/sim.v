`timescale 1ns/1ns

// Include ASIC_io module
`include "../rtl/ASIC/ASIC_io.v"

module top (
    input  wire        clk_48,
    input reg          reset,
    input              inputs,
    
    // Video output
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
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
        // Generate ce_pix at 1/2 of ce_16 rate for proper frame width
        ce_pix <= (pixel_div[0] == 0);
    end
    else begin
        ce_pix <= 0;
    end
end


//----------------------------------------------------------------
// Reset logic
reg RESET = 1;
reg rom_loaded = 0;

// Add download tracking
reg download_started = 0;
reg [24:0] last_addr = 0;
reg [24:0] download_addr = 0;  // Track actual download address

always @(posedge clk_48) begin
    reg ioctl_downlD;
    ioctl_downlD <= ioctl_download;
    
    // Track download progress
    if (ioctl_download && ioctl_wr) begin
        if (!download_started) begin
            download_started <= 1;
            download_addr <= 0;  // Start from 0
            $display("DEBUG: Starting new download");
        end else begin
            download_addr <= download_addr + 1;
        end
        last_addr <= download_addr;
    end
    
    // Come out of reset when CPR download starts
    if (plus_download) begin
        //$display("DEBUG: CPR Download starting, releasing reset");
        RESET <= 0;
    end
    
    // Handle download completion
    if (ioctl_downlD && !ioctl_download) begin
        rom_loaded <= 1;
        download_started <= 0;
        RESET <= 0;
        $display("DEBUG: Download complete at addr=%h, plus_download=%b, plus_valid=%b", 
                 download_addr, plus_download, plus_valid);
    end
    
    // Only reset when explicitly requested
    if (reset) begin
        RESET <= 1;
        rom_loaded <= 0;
        download_started <= 0;
        download_addr <= 0;
        last_addr <= 0;
        $display("DEBUG: External reset requested");
    end
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
// original.rom layout (128KB total):
// First 64KB (CPC6128 ROMs):
// 0x00000-0x03FFF: OS6128 (16KB)
// 0x04000-0x07FFF: BASIC1.1 (16KB)
// 0x08000-0x0BFFF: AMSDOS (16KB)
// 0x0C000-0x0FFFF: MF2 (16KB)
// Second 64KB (CPC664 ROMs) - ignored:
// 0x10000-0x13FFF: OS664 (16KB)
// 0x14000-0x17FFF: BASIC664 (16KB)
// 0x18000-0x1BFFF: AMSDOS (16KB)
// 0x1C000-0x1FFFF: MF2 (16KB)
localparam ROM_OS_ADDR     = 9'h000; // OS6128
localparam ROM_BASIC_ADDR  = 9'h100; // BASIC1.1
localparam ROM_AMSDOS_ADDR = 9'h107; // AMSDOS
localparam ROM_MF2_ADDR    = 9'h0ff; // MF2

always @(posedge clk_48) begin
	if((rom_download | plus_download) & ioctl_wr) begin
		// Only process addresses in first 64KB (CPC6128 ROMs)
		if (ioctl_addr[24:16] < 9'h100) begin
			boot_wr <= 1;
			boot_dout <= ioctl_dout;
			boot_a[13:0] <= ioctl_addr[13:0];
					
			if(ioctl_index) begin
				if (plus_download) begin
					// Plus ROM is loaded into first half of memory to match MAME behavior
					boot_a[22]    <= 1'b0;   // Use first half of memory
					boot_a[21:14] <= ioctl_addr[21:14];  // Use file address directly
					boot_bank     <= 1'b0;   // Always use bank 0 for Plus ROMs
				end else begin
					boot_a[22]    <= page[8];
					boot_a[21:14] <= page[7:0] + ioctl_addr[21:14];
					boot_bank     <= {1'b0, &ioctl_index[7:6]};
				end
			end
			else begin
				// Map ROM components to their correct addresses in original.rom
				// Only handle CPC6128 ROMs (first 64KB)
				case(ioctl_addr[24:14])
					0: boot_a[22:14] <= ROM_OS_ADDR;     // OS6128
					1: boot_a[22:14] <= ROM_BASIC_ADDR;  // BASIC1.1
					2: boot_a[22:14] <= ROM_AMSDOS_ADDR; // AMSDOS
					3: boot_a[22:14] <= ROM_MF2_ADDR;    // MF2
					default: boot_wr <= 0;
				endcase

				// Always use bank 0 for CPC6128
				boot_bank <= 0;
			end
		end
		else begin
			// Ignore addresses 0x10000 and above (CPC664 ROMs)
			boot_wr <= 0;
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

// Define I/O control signals
wire        io_rd = rd & iorq;
wire        io_wr = wr & iorq;

// Multiface Two implementation
wire  [7:0] mf2_dout = (mf2_ram_en & mem_rd) ? mf2_ram_out : 8'hFF;

reg         mf2_nmi = 0;
reg         mf2_en = 0;
reg         mf2_hidden = 0;
reg   [7:0] mf2_ram[8192];
wire        mf2_ram_en = mf2_en & cpu_addr[15:13] == 3'b001;
wire        mf2_rom_en = mf2_en & cpu_addr[15:13] == 3'b000;
reg   [4:0] mf2_pen_index;
reg   [3:0] mf2_crtc_register;
reg  [12:0] mf2_store_addr;
reg  [12:0] mf2_ram_a;
reg         mf2_ram_we;
reg   [7:0] mf2_ram_in, mf2_ram_out;

always_comb begin
    casex({ cpu_addr[15:8], cpu_dout[7:6] })
        { 8'h7f, 2'b00 }: mf2_store_addr = 13'h1fcf;  // pen index
        { 8'h7f, 2'b01 }: mf2_store_addr = mf2_pen_index[4] ? 13'h1fdf : { 9'h1f9, mf2_pen_index[3:0] }; // border/pen color
        { 8'h7f, 2'b10 }: mf2_store_addr = 13'h1fef; // screen mode
        { 8'h7f, 2'b11 }: mf2_store_addr = 13'h1fff; // banking
        { 8'hbc, 2'bXX }: mf2_store_addr = 13'h1cff; // CRTC register select
        { 8'hbd, 2'bXX }: mf2_store_addr = { 9'h1db, mf2_crtc_register[3:0] }; // CRTC register value
        { 8'hf7, 2'bXX }: mf2_store_addr = 13'h17ff; //8255
        { 8'hdf, 2'bXX }: mf2_store_addr = 13'h1aac; //upper rom
        default: mf2_store_addr = 0;
    endcase
end

always @(posedge clk_48) begin
    if (mf2_ram_we) begin
        mf2_ram[mf2_ram_a] <= mf2_ram_in;
        mf2_ram_out <= mf2_ram_in;
    end
    else mf2_ram_out <= mf2_ram[mf2_ram_a];
end

always @(posedge clk_48) begin
    reg old_key_nmi, old_m1, old_io_wr;

    old_key_nmi <= key_nmi;
    old_m1 <= m1;
    old_io_wr <= io_wr;

    if (RESET) begin
        mf2_en <= 0;
        mf2_hidden <= 0;  // Simplified for simulation
        mf2_nmi <= 0;
    end

    if(~old_key_nmi & key_nmi & ~mf2_en) mf2_nmi <= 1;
    if (mf2_nmi & ~old_m1 & m1 & (cpu_addr == 'h66)) begin
        mf2_en <= 1;
        mf2_hidden <= 0;
        mf2_nmi <= 0;
    end
    if (mf2_en & ~old_m1 & m1 & cpu_addr == 'h65) begin
        mf2_hidden <= 1;
    end

    if (~old_io_wr & io_wr & cpu_addr[15:2] == 14'b11111110111010) begin //fee8/feea
        mf2_en <= ~cpu_addr[1] & ~mf2_hidden;
    end else if (~old_io_wr & io_wr & |mf2_store_addr[12:0]) begin //store hw register in MF2 RAM
        if (cpu_addr[15:8] == 8'h7f & cpu_dout[7:6] == 2'b00) mf2_pen_index <= cpu_dout[4:0];
        if (cpu_addr[15:8] == 8'hbc) mf2_crtc_register <= cpu_dout[3:0];
        mf2_ram_a <= mf2_store_addr;
        mf2_ram_in <= cpu_dout;
        mf2_ram_we <= 1;
    end else if (mem_wr & mf2_ram_en) begin //normal MF2 RAM write
        mf2_ram_a <= ram_a[12:0];
        mf2_ram_in <= cpu_dout;
        mf2_ram_we <= 1;
    end else begin //MF2 RAM read
        mf2_ram_a <= ram_a[12:0];
        mf2_ram_we <= 0;
    end
end

// Video signals
wire        hbl;
wire        vbl;
wire        hs;
wire        vs;
wire [3:0]  r;
wire [3:0]  g;
wire [3:0]  b;
wire        VGA_F1;

// raw 2‑bit GA outputs (LSBs of motherboard colour buses)
wire [1:0] ga_r2 = r[1:0];
wire [1:0] ga_g2 = g[1:0];
wire [1:0] ga_b2 = b[1:0];

// Memory interface signals
wire [7:0]  ram_dout;
wire [22:0] ram_a;
wire [7:0]  cpu_din = ram_dout & mf2_dout; // & asic_data_out;  // Add ASIC data to CPU input

// Video memory interface signals
wire [14:0] vram_addr;
wire [15:0] vram_dout;

// Flag for setting model (0 for CPC6128, 1 for CPC464)
reg model = 0;  // Initialize to CPC6128 mode for OS6128.rom

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

// GX4000 I/O test signals
wire [7:0] gx4000_io_dout;
wire [7:0] printer_data;
wire       printer_strobe;
wire [7:0] rs232_data;
wire       rs232_tx;
wire       rs232_rts;
wire [7:0] playcity_data;
wire       playcity_wr;
wire       playcity_rd;
wire [7:0] peripheral_data;
wire       peripheral_ready;

// ASIC register signals
wire [7:0] asic_data_out;
wire [7:0] ram_config;
wire [7:0] pen_registers;
wire [4:0] current_pen;

// ACID signals
wire [7:0]  acid_data_out;
wire [7:0]  acid_ram_q;
wire        acid_valid;
wire [7:0]  acid_status;

// ACID address decode - using memory reads/writes instead of I/O
wire acid_io_rd = mem_rd && (cpu_addr[15:8] == 8'hBC);
wire acid_io_wr = mem_wr && (cpu_addr[15:8] == 8'hBC);
wire acid_ram_rd = mem_rd && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF);
wire acid_ram_wr = mem_wr && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF);

// ASIC signals
wire [7:0] asic_data_out;
wire asic_data_out_en;
wire [7:0] ppi_port_a;
wire [7:0] ppi_port_b;
wire [7:0] ppi_port_c;
wire [7:0] crtc_regs[0:31];
wire [7:0] crtc_reg_select;

wire acid_unlocked;

wire [7:0]  rom_config;
wire [7:0]  rom_select;
wire [31:0] break_point;

// Instantiate ASIC
ASIC asic
(
    .clk_sys(clk_48),
    .reset(RESET),
    .plus_mode(plus_rom_loaded),
    
    // CPU interface
    .cpu_addr(cpu_addr),
    .cpu_data_in(cpu_dout),
    .cpu_wr(io_wr),
    .cpu_rd(io_rd),
    .cpu_data_out(cpu_data_out),
    .cpu_data_out_en(cpu_data_out_en),
    .asic_data_out(asic_data_out),
    .asic_data_out_en(asic_data_out_en),
    
    // Video outputs
    .ppi_port_a(ppi_port_a),
    .ppi_port_b(ppi_port_b),
    .ppi_port_c(ppi_port_c),
    .crtc_regs(crtc_regs),
    .crtc_reg_select(crtc_reg_select),
    .acid_unlocked(acid_unlocked),
    
    // Configuration outputs
    .ram_config(ram_config),
    .rom_config(rom_config),
    .rom_select(rom_select),
    .current_pen(current_pen),
    .pen_registers(pen_registers),
    .mrer(mrer),
    .rmr2(rmr2)
);

// ASIC Register signals
wire [7:0]  mrer;
wire [7:0]  rom_select;
wire [7:0]  rmr2;

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

    // PPI jumpers for proper hardware detection
    // Format is {motor on/off, distributor, cpc type, vsync/index}
    .ppi_jumpers({1'b1, 1'b1, ~model, 1'b1}),
    .crtc_type(1'b1),  // Type 1 CRTC
    .sync_filter(1'b1),
    .no_wait(1'b0),    // Enable proper wait states
    //.plus_mode(plus_mode),  // Enable Plus mode to match GX4000_registers

    .tape_in(1'b0),
    .tape_out(),
    .tape_motor(tape_motor),

    .audio_l(audio_l),
    .audio_r(audio_r),

    .mode(mode),

    .red_o(r),
    .green_o(g),
    .blue_o(b),
    .hblank(hbl),
    .vblank(vbl),
    .hsync(hs),
    .vsync(vs),
    .field(VGA_F1),

    .vram_din(vram_dout),
    .vram_addr(vram_addr),

    .rom_map(rom_map),
    .ram64k(model),
    .mem_rd(mem_rd),
    .mem_wr(mem_wr),
    .mem_addr(ram_a),

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
    .cursor(cursor),

    // Register outputs from ASIC to motherboard
    .ram_config(ram_config),
    .mrer(mrer),
    .rom_select(rom_select),
    .pen_registers(pen_registers),
    .current_pen(current_pen)
);

// ---------------------------------------------------------------------
// Convert original Gate‑Array 2‑bit coding to 8‑bit RGB for simulation
// (Plus‑mode 4‑bit colours already arrive as full‑range values, so we
// simply pass them through when any upper nibble bit is set).
// ---------------------------------------------------------------------
wire [7:0] ga_r8, ga_g8, ga_b8;
color_mix ga2rgb (
    .clk_vid     (clk_48),
    .ce_pix      (ce_pix),
    .mix         (3'b000),   // normal colour
    .R_in        (r),
    .G_in        (g),
    .B_in        (b),
    .HSync_in    (hs),
    .VSync_in    (vs),
    .HBlank_in   (hbl),
    .VBlank_in   (vbl),
    .R_out       (ga_r8),
    .G_out       (ga_g8),
    .B_out       (ga_b8),
    .HSync_out   (),         // not used here
    .VSync_out   (),
    .HBlank_out  (),
    .VBlank_out  ()
);

// If Plus palette is active (upper nibble non‑zero) use it, otherwise GA
assign VGA_R = ga_r8;
assign VGA_G = ga_g8;
assign VGA_B = ga_b8;

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

    // Memory interface - handle ROM downloads during reset, CPR during normal operation
    .oe(RESET ? 1'b0 : mem_rd & ~mf2_ram_en),  // Allow reads during cartridge writes
    .we(RESET ? boot_wr : (rom_wr | (mem_wr & ~mf2_ram_en & ~mf2_rom_en))),  // Use boot_wr during reset
    .addr(RESET ? boot_a : (rom_wr ? rom_addr : mf2_rom_en ? { 9'h0ff, cpu_addr[13:0] } : ram_a)),  // Use boot_a during reset
    .bank(RESET ? boot_bank : { 1'b0, model }),  // Use boot_bank during reset, model-based bank otherwise
    .din(RESET ? boot_dout : (rom_wr ? rom_data : cpu_dout)),  // Use boot_dout during reset
    .dout(ram_dout),

    // Video memory access - match sdram.v exactly
    .vram_addr({2'b10, vram_addr, 1'b0}),
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

// Cartridge signals
wire [22:0] rom_addr;
wire [7:0]  rom_data;
wire        rom_wr;
wire        rom_rd;
wire [7:0]  rom_q;

wire        cart_auto_boot;
wire [15:0] cart_boot_addr;
wire [7:0]  cart_rom_type;
wire [15:0] cart_rom_size;
wire [15:0] cart_rom_checksum;
wire [7:0]  cart_rom_version;
wire [31:0] cart_rom_date;
wire [63:0] cart_rom_title;
wire        cart_plus_bios_valid;
wire [15:0] cart_plus_bios_checksum;
wire [7:0]  cart_plus_bios_version;

// Instantiate cartridge module
cartridge cart
(
    .clk_sys(clk_48),
    .reset(RESET),
    
    // ROM loading interface
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_download(plus_download),
    .ioctl_index(ioctl_index),
    
    // Memory interface
    .rom_addr(rom_addr),
    .rom_data(rom_data),
    .rom_wr(rom_wr),
    .rom_rd(rom_rd),
    .rom_q(rom_q),
    
    // Auto-boot interface
    .auto_boot(cart_auto_boot),
    .boot_addr(cart_boot_addr),
    
    // Cartridge information
    .rom_type(cart_rom_type),
    .rom_size(cart_rom_size),
    .rom_checksum(cart_rom_checksum),
    .rom_version(cart_rom_version),
    .rom_date(cart_rom_date),
    .rom_title(cart_rom_title),
    
    // Plus ROM validation outputs
    .plus_bios_valid(cart_plus_bios_valid),
    .plus_bios_checksum(cart_plus_bios_checksum),
    .plus_bios_version(cart_plus_bios_version)
);

// Update plus_valid based on cartridge validation
always @(posedge clk_48) begin
    if (plus_download) begin
        plus_valid <= cart_plus_bios_valid;
    end
end

endmodule