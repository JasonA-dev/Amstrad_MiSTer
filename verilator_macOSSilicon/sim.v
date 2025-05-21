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
reg plus_mode = 0;  // Start with Plus mode disabled

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
        if (plus_download & plus_valid) begin
            plus_mode <= 1; // was 1
        end
        download_started <= 0;
        RESET <= 0;
        $display("DEBUG: Download complete at addr=%h, plus_download=%b, plus_valid=%b", 
                 download_addr, plus_download, plus_valid);
    end
    
    // Only reset when explicitly requested
    if (reset) begin
        RESET <= 1;
        rom_loaded <= 0;
        plus_mode <= 0;
        download_started <= 0;
        download_addr <= 0;
        last_addr <= 0;
        $display("DEBUG: External reset requested");
    end
end
//----------------------------------------------------------------

// ROM Memory Map:
// 0x00000-0x03FFF: OS6128
// 0x04000-0x07FFF: BASIC1.1
// 0x08000-0x0BFFF: AMSDOS
// 0x0C000-0x0FFFF: MF2

// Memory interface
wire        ram_ready;
wire [22:0] ram_a;
wire [7:0]  ram_dout;
wire        ram_rd;
wire        ram_we;
wire [7:0]  cpu_dout;

// Memory loading logic
wire        rom_download = ioctl_download && (ioctl_index[4:0] < 4);
wire        tape_download = ioctl_download && (ioctl_index == 4);
wire        plus_cpr_download = ioctl_download && (ioctl_index == 5);  // F5 - CPR files
wire        plus_bin_download = ioctl_download && (ioctl_index == 6);  // F6 - BIN files
wire        plus_download = plus_cpr_download | plus_bin_download;

reg         boot_wr = 0;
reg  [22:0] boot_a;
reg   [7:0] boot_dout;
reg [255:0] rom_map = '0;
reg [8:0]   page = 0;
reg         combo = 0;

// Cartridge interface signals
wire [22:0] cart_addr;
wire [7:0]  cart_data;
wire        cart_wr;

// Memory write and boot loading logic
always @(posedge clk_48) begin
    if(ioctl_download & ioctl_wr) begin
        boot_wr <= 0;
        
        // Handle different file types
        if (rom_download && ioctl_addr[24:16] < 9'h100) begin
            boot_wr <= 1;
            boot_dout <= ioctl_dout;
            boot_a[13:0] <= ioctl_addr[13:0];
            
            case(ioctl_addr[24:14])
                0: boot_a[22:14] <= 9'h000; // OS6128
                1: boot_a[22:14] <= 9'h100; // BASIC1.1
                2: boot_a[22:14] <= 9'h107; // AMSDOS
                3: boot_a[22:14] <= 9'h0ff; // MF2
                default: boot_wr <= 0;
            endcase
        end
    end
    
    if(boot_wr && boot_a[22]) begin
        rom_map[boot_a[21:14]] <= 1;
    end

    // Handle file loading start
    if(~old_download & ioctl_download) begin
        if(rom_download | plus_bin_download | plus_cpr_download) begin
            page <= 0;  // Reset page counter
            combo <= 0; // Reset combo flag
        end
    end
    
    // Update old download state
    old_download <= ioctl_download;
end

// Memory write logic
always @(posedge clk_48) begin
    if(boot_wr) begin
        case(boot_a[22:14])
            0: begin // 0-3FFFF - ROM
                rom_map[boot_a[17:14]] <= 1'b1;
            end
            1,2: begin // 40000-BFFFF - RAM
                // RAM writes handled by sdram module
            end
        endcase
    end
end

// CPU and core signals
wire [15:0] cpu_addr;
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
wire [7:0]  mf2_dout = (mf2_ram_en & mem_rd) ? mf2_ram_out : 8'hFF;

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
        mf2_ram_a <= boot_a[12:0];
        mf2_ram_in <= boot_dout;
        mf2_ram_we <= 1;
    end else begin //MF2 RAM read
        mf2_ram_a <= boot_a[12:0];
        mf2_ram_we <= 0;
    end
end

// Video signals
wire        hbl;
wire        vbl;
wire        hs;
wire        vs;
wire [1:0]  r;
wire [1:0]  g;
wire [1:0]  b;
wire        VGA_F1;

// Internal signals for Plus mode output
wire [3:0] plus_r, plus_g, plus_b;
wire [7:0] plus_audio_l, plus_audio_r;

// Memory interface signals
wire [7:0]  cpu_din = ram_dout & mf2_dout;  // Add MF2 data to CPU input


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

// Add back Amstrad motherboard instantiation
Amstrad_motherboard motherboard
(
    .reset(RESET),
    .clk(clk_48),
    .ce_16(ce_16),

    .joy1(7'h00),
    .joy2(7'h00),
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
    .gx4000_mode(1'b0),  // Not needed, using plus_mode only
    .plus_mode(plus_mode),
    .plus_rom_loaded(plus_rom_loaded),

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
    .cursor(cursor)
);

// PlusMode instance (handles all Plus mode functionality)
PlusMode cart_inst
(
    .clk_sys(clk_48),
    .reset(RESET),
    .plus_mode(plus_mode),
    .use_asic(plus_mode), // or another appropriate signal for ASIC enable

    // CPU interface
    .cpu_addr(cpu_addr),
    .cpu_data_in(cpu_dout),
    .cpu_wr(wr),
    .cpu_rd(rd),
    .cpu_data_out(), // not used in this sim

    // Video interface
    .r_in(r),
    .g_in(g),
    .b_in(b),
    .hblank(hbl),
    .vblank(vbl),
    .hsync(hs),
    .r_out(plus_r),
    .g_out(plus_g),
    .b_out(plus_b),

    // CRTC interface from motherboard
    .cclk_en_n(ce_16),
    .crtc_clken(ce_16),
    .crtc_nclken(~ce_16),
    .crtc_ma(MA),
    .crtc_ra(RA),
    .crtc_de(crtc_de),
    .crtc_field(field),
    .crtc_cursor(cursor),
    .crtc_vsync(crtc_vs),
    .crtc_hsync(crtc_hs),

    // CRTC register write interface to motherboard
    .crtc_enable(),
    .crtc_cs_n(),
    .crtc_r_nw(),
    .crtc_rs(),
    .crtc_data(),

    // Audio interface
    .cpc_audio_l(audio_l),
    .cpc_audio_r(audio_r),
    .audio_l(plus_audio_l),
    .audio_r(plus_audio_r),

    // Joystick interface
    .joy1(joy1),
    .joy2(joy2),
    .joy_swap(1'b0),

    // Cartridge interface
    .cart_addr(cart_addr),
    .cart_data(cart_data),
    .cart_wr(cart_wr),

    // ROM loading interface
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),

    // Status outputs
    .rom_type(),
    .rom_size(),
    .rom_checksum(),
    .rom_version(),
    .rom_date(),
    .rom_title(),
    .asic_valid(),
    .asic_status(),
    .audio_status(),
    .plus_bios_valid(plus_valid),
    .pri_irq(pri_irq)
);

// Add debug statements for PlusMode signals
always @(posedge clk_48) begin
    if (ce_pix) begin
        /*
        $display("[PLUS_DEBUG] Timing: cclk_en_n=%b, crtc_de=%b, plus_mode=%b", 
                cclk_en_n, crtc_de, plus_mode);
        $display("[PLUS_DEBUG] Video: r_in=%b, g_in=%b, b_in=%b, r_out=%h, g_out=%h, b_out=%h", 
                r, g, b, plus_r, plus_g, plus_b);
        $display("[PLUS_DEBUG] CRTC: ma=%h, ra=%h, de=%b, vsync=%b, hsync=%b", 
                MA, RA, crtc_de, crtc_vs, crtc_hs);
        */
    end
end

// Add debug for ROM loading
always @(posedge clk_48) begin
    if (ioctl_download && ioctl_wr) begin
       // $display("[PLUS_DEBUG] ROM Load: addr=%h, data=%h, index=%h", 
       //         download_addr, ioctl_dout, ioctl_index);
    end
end

// Add debug for cartridge interface
always @(posedge clk_48) begin
    if (cart_wr) begin
        //$display("[PLUS_DEBUG] Cart Write: addr=%h, data=%h", cart_addr, cart_data);
    end
end

// Connect motherboard outputs to intermediate signals
wire [1:0] mb_r = r;
wire [1:0] mb_g = g;
wire [1:0] mb_b = b;

// Video output conversion - handle both 12-bit color in Plus mode and 2-bit color in standard mode
reg [5:0] vga_r_reg, vga_g_reg, vga_b_reg;
reg vga_hs_reg, vga_vs_reg, vga_hb_reg, vga_vb_reg;

// Add debug counters
reg [15:0] vga_pixel_counter = 0;
reg [15:0] vga_frame_counter = 0;

always @(posedge clk_48) begin
    if (reset) begin
        vga_pixel_counter <= 0;
        vga_frame_counter <= 0;
    end else begin
        if (!VGA_HB && !VGA_VB) begin
            vga_pixel_counter <= vga_pixel_counter + 1;
            
            // Log every 1000th pixel for debugging
            if (vga_pixel_counter % 1000 == 0) begin
                //$display("[VGA_OUT] Pixel %d: R=%h G=%h B=%h", 
                //        vga_pixel_counter, VGA_R, VGA_G, VGA_B);
            end
        end
        
        if (VGA_VB) begin
            vga_frame_counter <= vga_frame_counter + 1;
            //$display("[VGA_OUT] Frame %d complete: %d pixels", vga_frame_counter, vga_pixel_counter);
            vga_pixel_counter <= 0;
        end
    end
end

assign VGA_R = plus_mode ? plus_r[3:0] : {mb_r, mb_r, mb_r};
assign VGA_G = plus_mode ? plus_g[3:0] : {mb_g, mb_g, mb_g};
assign VGA_B = plus_mode ? plus_b[3:0] : {mb_b, mb_b, mb_b};

assign VGA_HS = ~hs;  // Invert for VGA
assign VGA_VS = ~vs;  // Invert for VGA
assign VGA_HB = hbl;
assign VGA_VB = vbl;

// SDRAM interface
mock_sdram sdram
(
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
    
    // Actual signals used in simulation
    .init(~rom_loaded),
    .clk(clk_48),
    .clkref(ce_ref),

    // Memory interface - handle ROM downloads during reset, CPR during normal operation
    .oe(RESET ? 1'b0 : mem_rd & ~mf2_ram_en),  // Allow reads during cartridge writes
    .we(RESET ? (ioctl_download & ioctl_wr & rom_download) : (cart_wr | (mem_wr & ~mf2_ram_en & ~mf2_rom_en))),  // ROM writes during reset, cart during normal
    .addr(RESET ? ioctl_addr[22:0] : (cart_wr ? cart_addr[22:0] : mf2_rom_en ? { 9'h0ff, cpu_addr[13:0] } : ram_a)),  // Use ioctl addr during reset
    .bank(2'b00),  // Cartridge data goes to bank 0
    .din(RESET ? ioctl_dout : (cart_wr ? cart_data : cpu_dout)),  // Use ioctl data during reset
    .dout(ram_dout),

    // Video memory access
    .vram_addr({2'b10, vram_addr, 1'b0}),
    .vram_dout(vram_dout),

    // Tape access (not used in verilator sim)
    .tape_addr(),
    .tape_din(8'h00),
    .tape_dout(),
    .tape_wr(1'b0),
    .tape_wr_ack(),
    .tape_rd(1'b0),
    .tape_rd_ack()
);

// CRTC interface signals
wire [13:0] MA;
wire [4:0] RA;
wire crtc_de;
wire crtc_vs;
wire crtc_hs;
wire field;
wire cursor;
wire cclk_en_n;
wire cclk_en_p;

// Connect CRTC signals from motherboard
assign MA = motherboard.MA;
assign RA = motherboard.RA;
assign crtc_de = ~(motherboard.vblank || motherboard.hblank);   // was crtc_de
assign crtc_vs = motherboard.vsync;   // was crtc_vs
assign crtc_hs = motherboard.hsync;   // was crtc_hs
assign field = motherboard.field;
assign cclk_en_n = ce_16; //motherboard.cclk_en_n;
assign cclk_en_p = ce_16; //motherboard.cclk_en_p;

endmodule