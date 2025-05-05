`timescale 1ns/1ns

module top (
    input  wire        clk_48,
    //input  wire        clk_24,
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
    output reg   ioctl_wait=1'b0
);

reg ce_pix = 1'b1;

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

//----------------------------------------------------------------
// Reset logic
reg RESET = 1;
reg rom_loaded = 0;
always @(posedge clk_48) begin
    reg ioctl_downlD;
    ioctl_downlD <= ioctl_download;
    if (ioctl_downlD & ~ioctl_download) rom_loaded <= 1;
    RESET <= reset | ~rom_loaded;
end
//----------------------------------------------------------------


wire        rom_download = ioctl_download && (ioctl_index[4:0] < 4);
wire        tape_download = ioctl_download && (ioctl_index == 4);

// A 8MB bank is split to 2 halves
// Fist 4 MB is OS ROM + RAM pages + MF2 ROM
// Second 4 MB is max. 256 pages of HI rom

reg         boot_wr = 0;
reg  [22:0] boot_a;
reg   [1:0] boot_bank;
reg   [7:0] boot_dout;

reg [255:0] rom_map = '0;

reg         romdl_wait = 0;
reg [8:0] page;
reg       combo;

initial begin
    page <= 0;
    combo <= 0;
end

always @(posedge clk_48) begin
    reg old_download;

    if(rom_download & ioctl_wr) begin
        romdl_wait <= 1;
        boot_dout <= ioctl_dout;
        boot_a[13:0] <= ioctl_addr[13:0];

        if(ioctl_index) begin
            boot_a[22]    <= page[8];
            boot_a[21:14] <= page[7:0] + ioctl_addr[21:14];
            boot_bank     <= {1'b0, &ioctl_index[7:6]};
        end
        else begin
            case(ioctl_addr[24:14])
                0,4: boot_a[22:14] <= 9'h000; //OS
                1,5: boot_a[22:14] <= 9'h100; //BASIC
                2,6: boot_a[22:14] <= 9'h107; //AMSDOS
                3,7: boot_a[22:14] <= 9'h0ff; //MF2
                default: romdl_wait <= 0;
            endcase

            case(ioctl_addr[24:14])
                0,1,2,3: boot_bank <= 0; //CPC6128
                4,5,6,7: boot_bank <= 1; //CPC664
            endcase
        end
    end

    if(rom_download) begin
        if(ioctl_wr) begin
            if(ioctl_addr == 0) begin
                if(ioctl_index[7:6]==1) begin
                    page <= 0;
                    combo <= 0;
                end
                else if(ioctl_index[7:6]==2) begin
                    page <= 9'h100;
                    combo <= 0;
                end
                else if(ioctl_index[7:6]==3) begin
                    page <= 9'h180;
                    combo <= 0;
                end
                else if(ioctl_index[7:6]==0) begin
                    page <= 9'h000;
                    combo <= 1;
                end
            end
            else begin
                if(combo && &boot_a[13:0]) begin
                    combo <= 0;
                    page <= 9'h1FF;
                end
            end
        end
        else begin
            if(boot_wr) begin
                {boot_wr, romdl_wait} <= 0;
                if(boot_a[22]) rom_map[boot_a[21:14]] <= 1;
            end
        end
    end

    old_download <= ioctl_download;
    if(~old_download & ioctl_download & rom_download) begin
        if(ioctl_index) begin
            page <= 9'h1EE; // some unused page for malformed file extension
            combo <= 0;
        end
    end
end


Amstrad_motherboard motherboard
(
	.reset(reset),
	.clk(clk_48),
	.ce_16(ce_16),

	.right_shift_mod(st_right_shift_mod),
	.keypad_mod(st_keypad_mod),
	.ps2_key(ps2_key),
	.Fn(Fn),

	.no_wait(0 & ~tape_motor),
	.ppi_jumpers({2'b11, 0, 1'b1}),
	.crtc_type(0),
	.sync_filter(1),

	.joy1(joy1),
	.joy2(joy2),

	.tape_in(tape_play),
	.tape_out(tape_rec),
	.tape_motor(tape_motor),

	.audio_l(audio_l),
	.audio_r(audio_r),

	.mode(mode),

	.hblank(hbl),
	.vblank(vbl),
	.hsync(hs),
	.vsync(vs),
	.red(r),
	.green(g),
	.blue(b),
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
	.cpu_addr(cpu_addr),
	.cpu_dout(cpu_dout),
	.cpu_din(cpu_din),
	.iorq(iorq),
	.rd(rd),
	.wr(wr),
	.m1(m1),
	.nmi(NMI),
	.irq(IRQ),
	.cursor(cursor),

	.key_nmi(key_nmi),
	.key_reset(key_reset)
);

// Memory interface signals
wire [7:0] ram_dout;
wire [22:0] ram_a;
wire mem_wr;
wire mem_rd;

// Video memory interface signals
wire [14:0] vram_addr;
wire [15:0] vram_dout;

// ROM memory interface signals
wire [7:0] rom_dout;
wire [7:0] rom_dout_b;
wire [15:0] cpu_addr;
wire [7:0] cpu_dout;
wire [7:0] cpu_din;

// Memory access control
wire is_rom_access = (ram_a[15:14] == 2'b00);  // 0000-3FFF is ROM
wire is_ram_access = (ram_a[15:14] != 2'b00);  // 4000-FFFF is RAM
wire is_vram_access = (ram_a[15:14] == 2'b10); // 8000-BFFF is VRAM

// CPU data input multiplexing
wire [7:0] cpu_din = is_rom_access ? ram_dout : 
                     is_ram_access ? ram_dout :
                     is_vram_access ? ram_dout : 8'hFF;

// Video and audio signals from motherboard
wire [1:0] cpc_r, cpc_g, cpc_b;
wire [7:0] cpc_audio_l, cpc_audio_r;

// Video and audio signals from GX4000
wire [1:0] gx4000_r, gx4000_g, gx4000_b;
wire [7:0] gx4000_audio_l, gx4000_audio_r;

// Mode selection
reg gx4000_mode = 0;  // Default to CPC mode

// Connect motherboard outputs to intermediate signals
assign cpc_r = r;
assign cpc_g = g;
assign cpc_b = b;
assign cpc_audio_l = audio_l;
assign cpc_audio_r = audio_r;

// Combine video outputs based on mode
assign r = gx4000_mode ? gx4000_r : cpc_r;
assign g = gx4000_mode ? gx4000_g : cpc_g;
assign b = gx4000_mode ? gx4000_b : cpc_b;

// Combine audio outputs based on mode
assign audio_l = gx4000_mode ? gx4000_audio_l : cpc_audio_l;
assign audio_r = gx4000_mode ? gx4000_audio_r : cpc_audio_r;

// Video signal assignments
assign VGA_R = {r, r, r, r, r, r};  // Expand 2-bit to 6-bit
assign VGA_G = {g, g, g, g, g, g};  // Expand 2-bit to 6-bit
assign VGA_B = {b, b, b, b, b, b};  // Expand 2-bit to 6-bit
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_HB = hbl;
assign VGA_VB = vbl;

// Instantiate single dpram for all memory
dpram #(
    .data_width_g(8),
    .addr_width_g(14)
) memory (
    // Port A - CPU interface
    .clock_a(clk_48),
    .ram_cs(1'b1),
    .wren_a(mem_wr),
    .address_a(ram_a[13:0]),
    .data_a(cpu_dout),
    .q_a(ram_dout),

    // Port B - Video/ROM interface
    .clock_b(clk_48),
    .ram_cs_b(1'b1),
    .wren_b(ioctl_wr & rom_download),
    .address_b(vram_addr[13:0]),
    .data_b(ioctl_dout),
    .q_b(vram_dout[7:0])
);

endmodule