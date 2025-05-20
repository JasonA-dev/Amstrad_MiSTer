module PlusMode
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    input         use_asic,       // Control whether to use the ASIC for video processing
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data_in,   // Rename to cpu_data_in
    input         cpu_wr,
    input         cpu_rd,
    output  [7:0] cpu_data_out,  // Add output for data bus
    
    // Video interface
    input   [1:0] r_in,
    input   [1:0] g_in,
    input   [1:0] b_in,
    input         hblank,
    input         vblank,
    input         hsync,         // Added hsync input
    output  [3:0] r_out,
    output  [3:0] g_out,
    output  [3:0] b_out,
    
    // CRTC interface from motherboard
    input         cclk_en_n,     // Add Gate Array clock enable
    input         crtc_clken,    // Keep for backward compatibility
    input         crtc_nclken,
    input  [13:0] crtc_ma,
    input   [4:0] crtc_ra,
    input         crtc_de,
    input         crtc_field,
    input         crtc_cursor,
    input         crtc_vsync,
    input         crtc_hsync,
    
    // CRTC register write interface to motherboard
    output        crtc_enable,
    output        crtc_cs_n,
    output        crtc_r_nw,
    output        crtc_rs,
    output  [7:0] crtc_data,
    
    // Audio interface
    input   [7:0] cpc_audio_l,
    input   [7:0] cpc_audio_r,
    output  [7:0] audio_l,
    output  [7:0] audio_r,
    
    // Joystick interface
    input   [6:0] joy1,
    input   [6:0] joy2,
    input         joy_swap,
    
    // Cartridge interface - outputs to SDRAM
    output [24:0] cart_addr,
    output  [7:0] cart_data,
    output        cart_wr,
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    input   [7:0] ioctl_index,   // Added index to distinguish between file types
    
    // Status outputs
    output  [7:0] rom_type,
    output [15:0] rom_size,
    output [15:0] rom_checksum,
    output  [7:0] rom_version,
    output [31:0] rom_date,
    output [63:0] rom_title,
    output        asic_valid,
    output  [7:0] asic_status,
    output  [7:0] audio_status,
    
    // Plus-specific outputs
    output        plus_bios_valid,
    output        pri_irq
);

    // Internal signals
    wire [7:0] io_dout;
    wire [22:0] rom_addr;
    wire [7:0] rom_data;
    wire       rom_wr;
    wire       rom_rd;
    wire [7:0] rom_q;
    wire       auto_boot;
    wire [15:0] boot_addr;
    wire [15:0] plus_bios_checksum;
    wire [7:0]  plus_bios_version;
    
    // I/O signals
    wire [7:0] io_status;
    wire [7:0] io_control;
    wire [7:0] io_data;
    wire [7:0] io_direction;
    wire [7:0] io_interrupt;
    wire [7:0] io_timer;
    wire [7:0] io_clock;
    
    // Cartridge interface signals
    wire [24:0] cart_addr_int;  // Internal cartridge address
    wire [7:0]  cart_data_int;  // Internal cartridge data
    wire        cart_wr_int;    // Internal cartridge write
    wire        cart_rd = 1'b0; // Fixed to 0 as it's only an input to cart_inst
    
    // ASIC RAM interface wires
    wire [13:0] asic_ram_addr;
    wire        asic_ram_rd;
    wire        asic_ram_wr;
    wire [7:0]  asic_ram_din;
    wire [7:0]  asic_ram_q;
    
    // Use Gate Array clock enable for timing
    wire crtc_clken_actual = cclk_en_n;

    // Assign cartridge outputs
    assign cart_addr = cart_addr_int;
    assign cart_data = cart_data_int;
    assign cart_wr = cart_wr_int;
    
    // Sprite-related signals from video module
    wire [3:0] sprite_id;
    wire       sprite_active;
    wire [7:0] collision_reg;
    
    // I/O module instance
    GX4000_io io_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .io_dout(io_dout),
        
        // Joystick interface
        .joy1(joy1),
        .joy2(joy2),
        .joy_swap(joy_swap),
        
        // IO register outputs
        .io_status(io_status),
        .io_control(io_control),
        .io_data(io_data),
        .io_direction(io_direction),
        .io_interrupt(io_interrupt),
        .io_timer(io_timer),
        .io_clock(io_clock)
    );

    // Video module instance (with integrated sprite handling)
    GX4000_video video_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode & use_asic),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // CRTC Interface
        .cclk_en_n(cclk_en_n),     // Pass Gate Array clock enable
        .crtc_clken(crtc_clken_actual),  // Use actual clock enable
        .crtc_nclken(crtc_nclken),
        .crtc_ma(crtc_ma),
        .crtc_ra(crtc_ra),
        .crtc_de(crtc_de),
        .crtc_field(crtc_field),
        .crtc_cursor(crtc_cursor),
        .crtc_vsync(crtc_vsync),
        .crtc_hsync(crtc_hsync),
        
        // Video input
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hpos(crtc_ma[9:0]),
        .vpos(crtc_ra),
        .hblank(hblank),
        .vblank(vblank),
        
        // Video output
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        
        // Sprite interface outputs (for audio module)
        .sprite_active_out(sprite_active),
        .sprite_id_out(sprite_id),
        .collision_reg(collision_reg),
        
        // ASIC RAM interface
        .asic_ram_addr(asic_ram_addr),
        .asic_ram_rd(asic_ram_rd),
        .asic_ram_q(asic_ram_q),
        .asic_ram_wr(asic_ram_wr),
        .asic_ram_din(asic_ram_din),
        
        // Interrupt output
        .pri_irq(pri_irq)
    );

    // ACID module instance
    wire [7:0] acid_data_out;
    GX4000_ACID acid_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode & use_asic),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpu_data_out(acid_data_out),
        
        // Hardware register inputs
        .sprite_control(sprite_id),           // Connect sprite ID as control
        .sprite_collision(collision_reg),     // Connect collision register
        .audio_control(audio_status),         // Connect audio status as control
        .audio_status(audio_status),          // Connect audio status
        .video_status({6'b000000, sprite_active, 1'b0}), // Video status with sprite active bit
        
        // ASIC RAM interface
        .asic_ram_addr(asic_ram_addr),
        .asic_ram_rd(asic_ram_rd),
        .asic_ram_wr(asic_ram_wr),
        .asic_ram_din(asic_ram_din),
        .asic_ram_q(asic_ram_q),
        
        // Status outputs
        .asic_valid(asic_valid),
        .asic_status(asic_status)
    );

    // Audio module instance
    GX4000_audio audio_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode & use_asic),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data_in),  // Use cpu_data_in
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpc_audio_l(cpc_audio_l),
        .cpc_audio_r(cpc_audio_r),
        .sprite_id(sprite_id),                 // Connect to sprite signals from video module
        .sprite_collision(sprite_active),      // Use sprite_active as collision signal
        .sprite_movement(collision_reg),       // Use collision register
        .hblank(hblank),
        .vblank(vblank),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .audio_status(audio_status)
    );

    // Cartridge module instance
    GX4000_cartridge cart_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode),
        
        // Cartridge interface - connect to internal signals
        .cart_addr(cart_addr_int),
        .cart_data(cart_data_int),
        .cart_rd(cart_rd),
        .cart_wr(cart_wr_int),
        
        // ROM loading interface
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_download(ioctl_download),
        .ioctl_index(ioctl_index),
        
        // Memory interface
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_wr(rom_wr),
        .rom_rd(rom_rd),
        .rom_q(rom_q),
        
        // Auto-boot interface
        .auto_boot(auto_boot),
        .boot_addr(boot_addr),
        
        // Plus ROM validation outputs
        .plus_bios_valid(plus_bios_valid),
        .plus_bios_checksum(plus_bios_checksum),
        .plus_bios_version(plus_bios_version),
        
        // ROM information outputs
        .rom_type(rom_type),
        .rom_size(rom_size),
        .rom_checksum(rom_checksum),
        .rom_version(rom_version),
        .rom_date(rom_date),
        .rom_title(rom_title)
    );

    // Connect data sources to CPU data bus
    assign cpu_data_out = 
        (cpu_addr[15:8] == 8'h7F || cpu_addr[15:8] == 8'hDF) ? io_dout :
        (cpu_addr[15:8] == 8'hBC) ? acid_data_out :
        8'hFF;

    // Define ASIC page enabled signal
    wire asic_page_enabled = plus_mode && use_asic && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF);

    // Log all ASIC-related I/O port accesses
    always @(posedge clk_sys) begin
        if (cpu_wr) begin
            if ((cpu_addr[15:8] == 8'h7F) || (cpu_addr[15:8] == 8'hDF) ||
                (cpu_addr[15:8] == 8'hBC) || (cpu_addr[15:8] == 8'hBD) ||
                (cpu_addr[15:8] == 8'hBE) || (cpu_addr[15:8] == 8'hBF)) begin
                //$display("[ASIC] CPU WRITE to port %04X: Data=%02X", cpu_addr, cpu_data_in);
            end
        end
        if (cpu_rd) begin
            if ((cpu_addr[15:8] == 8'h7F) || (cpu_addr[15:8] == 8'hDF) ||
                (cpu_addr[15:8] == 8'hBC) || (cpu_addr[15:8] == 8'hBD) ||
                (cpu_addr[15:8] == 8'hBE) || (cpu_addr[15:8] == 8'hBF)) begin
                //$display("[ASIC] CPU READ from port %04X", cpu_addr);
            end
        end
    end

    // Log all accesses to ASIC I/O page (when enabled)
    always @(posedge clk_sys) begin
        if (asic_page_enabled) begin
            if (cpu_wr) begin
                //$display("[ASIC] CPU WRITE to ASIC page %04X: Data=%02X", cpu_addr, cpu_data_in);
            end
            if (cpu_rd) begin
                //$display("[ASIC] CPU READ from ASIC page %04X", cpu_addr);
            end
        end
    end
endmodule 