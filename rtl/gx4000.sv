module PlusMode
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    input         use_asic,       // Control whether to use the ASIC for video processing
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Video interface
    input   [1:0] r_in,
    input   [1:0] g_in,
    input   [1:0] b_in,
    input         hblank,
    input         vblank,
    output  [1:0] r_out,
    output  [1:0] g_out,
    output  [1:0] b_out,
    
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
    output        plus_bios_valid
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
    
    // Cartridge interface signals
    wire [24:0] cart_addr_int;  // Internal cartridge address
    wire [7:0]  cart_data_int;  // Internal cartridge data
    wire        cart_wr_int;    // Internal cartridge write
    wire        cart_rd = 1'b0; // Fixed to 0 as it's only an input to cart_inst
    
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
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .io_dout(io_dout),
        .joy1(joy1),
        .joy2(joy2),
        .joy_swap(joy_swap)
    );

    // Video module instance (with integrated sprite handling)
    GX4000_video video_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode & use_asic),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video input
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hblank(hblank),
        .vblank(vblank),
        
        // Video output
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        
        // Sprite interface outputs (for audio module)
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        .collision_reg(collision_reg)
    );

    // Advanced Cartridge Interface Device (ACID) module instance
    GX4000_ACID acid_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode & use_asic),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpu_data_out(),
        
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
        .cpu_data(cpu_data),
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
        .audio_status(audio_status),
        .sample_wr(1'b0),                     // Not used in simulation
        .sample_addr(16'h0000),               // Not used in simulation
        .sample_data(8'h00)                   // Not used in simulation
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
        .plus_bios_version(plus_bios_version)
    );

endmodule 