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
    wire [7:0] io_control;  // Changed back to wire
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
    
    // Connect CRTC interface signals
    assign crtc_enable = crtc_reg_wr;
    assign crtc_cs_n = ~crtc_reg_wr;
    assign crtc_r_nw = ~crtc_reg_wr;
    assign crtc_rs = crtc_reg_sel[0];
    assign crtc_data = crtc_reg_data;

    // Connect ASIC sync signals
    assign asic_hsync_in = hsync;
    assign asic_vsync_in = crtc_vsync;
    assign asic_hblank_in = hblank;
    assign asic_vblank_in = vblank;
    
    // Sprite-related signals from video module
    wire [3:0] sprite_id;
    wire       sprite_active;
    wire [7:0] collision_reg;
    
    // CRTC update interface signals
    wire        crtc_reg_wr;
    wire [3:0]  crtc_reg_sel;
    wire [7:0]  crtc_reg_data;

    // GA40010 (Gate Array) update interface signals
    wire        ga_reg_wr;
    wire [3:0]  ga_reg_sel;
    wire [7:0]  ga_reg_data;

    // Real ASIC sync signal inputs
    wire        asic_hsync_in;
    wire        asic_vsync_in;
    wire        asic_hblank_in;
    wire        asic_vblank_in;
    
    // Video mode registers
    reg [7:0] config_mode;
    reg [4:0] mrer_mode;
    reg [7:0] asic_mode;
    reg       asic_enabled;

    // Video mode handling
    always @(posedge clk_sys) begin
        if (reset) begin
            config_mode <= 8'h00;
            mrer_mode <= 5'h00;
            asic_mode <= 8'h00;
            asic_enabled <= 1'b0;
        end else if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
            if (cpu_addr[0] == 0) begin
                case (cpu_data_in[4:0])
                    5'h00: begin
                        config_mode <= cpu_data_in;
                    end
                    5'h01: begin
                        mrer_mode <= cpu_data_in[4:0];
                    end
                    5'h02: begin
                        asic_mode <= cpu_data_in;
                        // Enable ASIC in Plus mode for modes 0x02, 0x62, and 0x82
                        asic_enabled <= ((cpu_data_in == 8'h02) || (cpu_data_in == 8'h62) || (cpu_data_in == 8'h82)) && plus_mode;
                    end
                endcase
            end
        end
    end

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
        .plus_mode(plus_mode & use_asic),  // plus_mode & use_asic
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video mode inputs
        .config_mode(config_mode),
        .mrer_mode(mrer_mode),
        .asic_mode(asic_mode),
        .asic_enabled(asic_enabled),
        
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
        
        .asic_control(asic_control),
        .asic_status(asic_status),
        .asic_config(asic_config),
        .video_control(video_control),
        .video_status(video_status),
        .video_config(video_config),
        .video_palette(video_palette),
        .video_effect(video_effect),
        .sprite_control(sprite_control),
        .sprite_status(sprite_status),
        .sprite_config(sprite_config),
        .sprite_priority(sprite_priority),
        .sprite_collision(sprite_collision),

        // ASIC RAM interface
        .asic_ram_addr(asic_ram_addr),
        .asic_ram_rd(asic_ram_rd),
        .asic_ram_wr(asic_ram_wr),
        .asic_ram_din(asic_ram_din),
        .asic_ram_q(asic_ram_q),
        
        // CRTC update interface
        .crtc_reg_wr(crtc_reg_wr),
        .crtc_reg_sel(crtc_reg_sel),
        .crtc_reg_data(crtc_reg_data),

        // GA40010 (Gate Array) update interface
        .ga_reg_wr(ga_reg_wr),
        .ga_reg_sel(ga_reg_sel),
        .ga_reg_data(ga_reg_data),

        // Real ASIC sync signal inputs
        .asic_hsync_in(asic_hsync_in),
        .asic_vsync_in(asic_vsync_in),
        .asic_hblank_in(asic_hblank_in),
        .asic_vblank_in(asic_vblank_in),
        
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
        .audio_status(audio_status),
        .audio_control(io_control),            // Connect to I/O control register
        .audio_config(io_config),              // Connect to I/O config register
        .audio_volume(io_volume)               // Connect to I/O volume register
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


// ASIC Control Registers (0x7F00-0x7F0F)
reg [7:0] asic_control;
reg [7:0] asic_config;
reg [7:0] asic_version;

// Video Control Registers (0x7F10-0x7F1F)
reg [7:0] video_control;
reg [7:0] video_status;
reg [7:0] video_config;
reg [7:0] video_palette;
reg [7:0] video_effect;

// Sprite Control Registers (0x7F20-0x7F2F)
reg [7:0] sprite_control;
reg [7:0] sprite_status;
reg [7:0] sprite_config;
reg [7:0] sprite_priority;
reg [7:0] sprite_collision;

// Audio Control Registers (0x7F30-0x7F3F)
reg [7:0] audio_control;
reg [7:0] audio_config;
reg [7:0] audio_volume;

// ASIC RAM: 16KB (0x4000 bytes)
reg [7:0] asic_ram [0:16383];

// ASIC RAM read data
reg [7:0] asic_ram_q_reg;
assign asic_ram_q = asic_ram_q_reg;

// ASIC RAM access tracking
reg [13:0] last_asic_ram_addr;
reg [7:0] last_asic_ram_din;
reg last_asic_ram_wr;
reg last_asic_ram_rd;

// Add ASIC RAM access from CPU
wire cpu_asic_ram_access = plus_mode && use_asic && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF);
wire [13:0] cpu_asic_ram_addr = cpu_addr[13:0];  // Map 0x4000-0x7FFF to 0x0000-0x3FFF
wire [7:0] cpu_asic_ram_data = cpu_data_in;

// Modify ASIC RAM interface to include CPU access
assign asic_ram_addr = cpu_asic_ram_access ? cpu_asic_ram_addr : asic_ram_addr;
assign asic_ram_din = cpu_asic_ram_access ? cpu_asic_ram_data : asic_ram_din;
assign asic_ram_wr = cpu_asic_ram_access ? cpu_wr : 1'b0;  // Only allow writes from CPU
assign asic_ram_rd = cpu_asic_ram_access ? cpu_rd : asic_ram_rd;

// ASIC RAM read/write logic
always @(posedge clk_sys) begin
    if (reset) begin
        asic_ram_q_reg <= 8'h00;
        last_asic_ram_addr <= 14'h0000;
        last_asic_ram_din <= 8'h00;
        last_asic_ram_wr <= 1'b0;
        last_asic_ram_rd <= 1'b0;
        // Clear RAM on reset
        for (integer i = 0; i < 16384; i = i + 1) begin
            asic_ram[i] = 8'h00;
        end
    end else begin
        // Track last access for debugging
        last_asic_ram_addr <= asic_ram_addr;
        last_asic_ram_din <= asic_ram_din;
        last_asic_ram_wr <= asic_ram_wr;
        last_asic_ram_rd <= asic_ram_rd;

        // Write from CPU to ASIC RAM
        if (asic_ram_wr && cpu_asic_ram_access) begin
            asic_ram[asic_ram_addr] <= asic_ram_din;
            // Update read data immediately on write
            asic_ram_q_reg <= asic_ram_din;
            // Debug output
            //$display("[ASIC RAM] CPU Write: addr=%04X, data=%02X", asic_ram_addr, asic_ram_din);
        end
        // Read for video/other modules
        else if (asic_ram_rd) begin
            asic_ram_q_reg <= asic_ram[asic_ram_addr];
            // Debug output
            //$display("[ASIC RAM] Read: addr=%04X, data=%02X", asic_ram_addr, asic_ram[asic_ram_addr]);
        end
    end
end

// Add ASIC RAM access logging
always @(posedge clk_sys) begin
    if (cpu_wr && cpu_asic_ram_access) begin
        //$display("[ASIC] CPU Write to ASIC RAM: addr=%04X, data=%02X", cpu_addr, cpu_data_in);
    end
    if (cpu_rd && cpu_asic_ram_access) begin
        //$display("[ASIC] CPU Read from ASIC RAM: addr=%04X", cpu_addr);
    end
end

// Connect CPU data output for ASIC RAM reads
assign cpu_data_out = (cpu_asic_ram_access && cpu_rd) ? asic_ram_q : 
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

// I/O Control Registers (0x7F30-0x7F3F)
reg [7:0] io_config;
reg [7:0] io_volume;

// Initialize I/O registers
initial begin
    io_config = 8'h00;
    io_volume = 8'h00;
end

// Handle I/O register writes
always @(posedge clk_sys) begin
    if (reset) begin
        io_config <= 8'h00;
        io_volume <= 8'h00;
        
        // Initialize control registers from ASIC RAM
        asic_control <= asic_ram[16'h3F00 - 16'h4000];  // 0x7F00 -> 0x3F00
        asic_config <= asic_ram[16'h3F02 - 16'h4000];
        asic_version <= asic_ram[16'h3F03 - 16'h4000];
        
        // Video Control Registers
        video_control <= asic_ram[16'h3F10 - 16'h4000];
        video_status <= asic_ram[16'h3F11 - 16'h4000];
        video_config <= asic_ram[16'h3F12 - 16'h4000];
        video_palette <= asic_ram[16'h3F13 - 16'h4000];
        video_effect <= asic_ram[16'h3F14 - 16'h4000];
        
        // Sprite Control Registers
        sprite_control <= asic_ram[16'h3F20 - 16'h4000];
        sprite_status <= asic_ram[16'h3F21 - 16'h4000];
        sprite_config <= asic_ram[16'h3F22 - 16'h4000];
        sprite_priority <= asic_ram[16'h3F23 - 16'h4000];
        sprite_collision <= asic_ram[16'h3F24 - 16'h4000];
        
        // Audio Control Registers
        audio_control <= asic_ram[16'h3F30 - 16'h4000];
        audio_config <= asic_ram[16'h3F31 - 16'h4000];
        audio_volume <= asic_ram[16'h3F32 - 16'h4000];
        
    end else if (cpu_wr && cpu_addr[15:8] == 8'h7F) begin
        case (cpu_addr[7:0])
            // ASIC Control Registers
            8'h00: begin 
                asic_control <= cpu_data_in;
                asic_ram[16'h3F00 - 16'h4000] <= cpu_data_in;
            end
            8'h02: begin
                asic_config <= cpu_data_in;
                asic_ram[16'h3F02 - 16'h4000] <= cpu_data_in;
            end
            8'h03: begin
                asic_version <= cpu_data_in;
                asic_ram[16'h3F03 - 16'h4000] <= cpu_data_in;
            end
            
            // Video Control Registers
            8'h10: begin
                video_control <= cpu_data_in;
                asic_ram[16'h3F10 - 16'h4000] <= cpu_data_in;
            end
            8'h11: begin
                video_status <= cpu_data_in;
                asic_ram[16'h3F11 - 16'h4000] <= cpu_data_in;
            end
            8'h12: begin
                video_config <= cpu_data_in;
                asic_ram[16'h3F12 - 16'h4000] <= cpu_data_in;
            end
            8'h13: begin
                video_palette <= cpu_data_in;
                asic_ram[16'h3F13 - 16'h4000] <= cpu_data_in;
            end
            8'h14: begin
                video_effect <= cpu_data_in;
                asic_ram[16'h3F14 - 16'h4000] <= cpu_data_in;
            end
            
            // Sprite Control Registers
            8'h20: begin
                sprite_control <= cpu_data_in;
                asic_ram[16'h3F20 - 16'h4000] <= cpu_data_in;
            end
            8'h21: begin
                sprite_status <= cpu_data_in;
                asic_ram[16'h3F21 - 16'h4000] <= cpu_data_in;
            end
            8'h22: begin
                sprite_config <= cpu_data_in;
                asic_ram[16'h3F22 - 16'h4000] <= cpu_data_in;
            end
            8'h23: begin
                sprite_priority <= cpu_data_in;
                asic_ram[16'h3F23 - 16'h4000] <= cpu_data_in;
            end
            8'h24: begin
                sprite_collision <= cpu_data_in;
                asic_ram[16'h3F24 - 16'h4000] <= cpu_data_in;
            end
            
            // Audio Control Registers
            8'h30: begin
                audio_control <= cpu_data_in;
                asic_ram[16'h3F30 - 16'h4000] <= cpu_data_in;
            end
            8'h31: begin
                audio_config <= cpu_data_in;
                asic_ram[16'h3F31 - 16'h4000] <= cpu_data_in;
            end
            8'h32: begin
                audio_volume <= cpu_data_in;
                asic_ram[16'h3F32 - 16'h4000] <= cpu_data_in;
            end
            
            8'h31: io_config <= cpu_data_in;
            8'h32: io_volume <= cpu_data_in;
        endcase
    end
end
endmodule 