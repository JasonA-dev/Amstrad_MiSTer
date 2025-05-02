module GX4000_memory
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Memory interface
    output [22:0] mem_addr,
    output  [7:0] mem_data,
    output        mem_wr,
    output        mem_rd,
    input   [7:0] mem_q,
    
    // Cartridge interface
    input         cart_download,
    input  [24:0] cart_addr,
    input   [7:0] cart_data,
    input         cart_wr,
    
    // RAM expansion interface
    output [18:0] exp_ram_addr,
    output  [7:0] exp_ram_data,
    output        exp_ram_wr,
    output        exp_ram_rd,
    input   [7:0] exp_ram_q
);

    // Memory banking registers
    reg [7:0] bank_select;
    reg [7:0] bank_config[0:7];
    reg [7:0] ram_config;
    reg [7:0] exp_ram_bank;
    reg [7:0] bank_protect[0:7];
    reg [7:0] bank_access[0:7];
    
    // Cartridge RAM
    reg [7:0] cart_ram[0:16383]; // 16KB cartridge RAM
    
    // Memory state
    reg [2:0] active_bank;
    reg [7:0] bank_offset;
    reg       exp_ram_en;
    reg       bank_locked;
    reg [7:0] access_error;
    
    // Memory protection
    localparam PROT_NONE = 8'h00;
    localparam PROT_READ = 8'h01;
    localparam PROT_WRITE = 8'h02;
    localparam PROT_FULL = 8'h03;
    
    // Error codes
    localparam ERROR_NONE = 8'h00;
    localparam ERROR_PROTECTED = 8'h01;
    localparam ERROR_INVALID_BANK = 8'h02;
    localparam ERROR_LOCKED = 8'h03;
    
    // Memory processing
    always @(posedge clk_sys) begin
        if (reset) begin
            bank_select <= 8'h00;
            for (integer i = 0; i < 8; i = i + 1) begin
                bank_config[i] <= 8'h00;
                bank_protect[i] <= PROT_NONE;
                bank_access[i] <= 8'h00;
            end
            ram_config <= 8'h00;
            exp_ram_bank <= 8'h00;
            active_bank <= 3'h0;
            bank_offset <= 8'h00;
            exp_ram_en <= 0;
            bank_locked <= 0;
            access_error <= ERROR_NONE;
        end else if (gx4000_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    8'h60: begin
                        if (!bank_locked) begin
                            bank_select <= cpu_data;
                        end else begin
                            access_error <= ERROR_LOCKED;
                        end
                    end
                    8'h61: bank_config[0] <= cpu_data;
                    8'h62: bank_config[1] <= cpu_data;
                    8'h63: bank_config[2] <= cpu_data;
                    8'h64: bank_config[3] <= cpu_data;
                    8'h65: bank_config[4] <= cpu_data;
                    8'h66: bank_config[5] <= cpu_data;
                    8'h67: bank_config[6] <= cpu_data;
                    8'h68: bank_config[7] <= cpu_data;
                    8'h69: ram_config <= cpu_data;
                    8'h6A: exp_ram_bank <= cpu_data;
                    8'h6B: exp_ram_en <= cpu_data[0];
                    8'h6C: bank_protect[0] <= cpu_data[1:0];
                    8'h6D: bank_protect[1] <= cpu_data[1:0];
                    8'h6E: bank_protect[2] <= cpu_data[1:0];
                    8'h6F: bank_protect[3] <= cpu_data[1:0];
                    8'h70: bank_protect[4] <= cpu_data[1:0];
                    8'h71: bank_protect[5] <= cpu_data[1:0];
                    8'h72: bank_protect[6] <= cpu_data[1:0];
                    8'h73: bank_protect[7] <= cpu_data[1:0];
                    8'h74: bank_locked <= cpu_data[0];
                endcase
            end
            
            // Bank selection
            if (!bank_locked) begin
                active_bank <= bank_select[2:0];
                bank_offset <= bank_config[active_bank];
            end
            
            // Cartridge RAM access
            if (cart_download && cart_wr) begin
                cart_ram[cart_addr[13:0]] <= cart_data;
            end
            
            // Access tracking
            if (cpu_rd || cpu_wr) begin
                if (bank_protect[active_bank] == PROT_FULL) begin
                    access_error <= ERROR_PROTECTED;
                end else if (cpu_wr && bank_protect[active_bank] == PROT_WRITE) begin
                    access_error <= ERROR_PROTECTED;
                end else if (cpu_rd && bank_protect[active_bank] == PROT_READ) begin
                    access_error <= ERROR_PROTECTED;
                end else begin
                    bank_access[active_bank] <= bank_access[active_bank] + 1;
                end
            end
        end
    end
    
    // Memory address generation
    wire [22:0] base_addr = {bank_offset, cpu_addr[13:0]};
    wire [22:0] cart_addr_internal = {8'h00, cpu_addr[13:0]};
    wire [18:0] exp_addr = {exp_ram_bank[4:0], cpu_addr[13:0]};
    
    // Memory interface selection
    wire is_cart = (cpu_addr[15:14] == 2'b00);
    wire is_exp_ram = exp_ram_en && (cpu_addr[15:14] == 2'b11);
    
    // Memory protection check
    wire access_allowed = (bank_protect[active_bank] == PROT_NONE) ||
                         (cpu_wr && bank_protect[active_bank] != PROT_WRITE) ||
                         (cpu_rd && bank_protect[active_bank] != PROT_READ);
    
    // Memory interface
    assign mem_addr = is_cart ? cart_addr_internal : base_addr;
    assign mem_data = cpu_data;
    assign mem_wr = cpu_wr && !is_exp_ram && access_allowed;
    assign mem_rd = cpu_rd && !is_exp_ram && access_allowed;
    
    // Expansion RAM interface
    assign exp_ram_addr = exp_addr;
    assign exp_ram_data = cpu_data;
    assign exp_ram_wr = cpu_wr && is_exp_ram && access_allowed;
    assign exp_ram_rd = cpu_rd && is_exp_ram && access_allowed;
    
    // Memory output
    wire [7:0] cart_ram_data = cart_ram[cpu_addr[13:0]];
    wire [7:0] exp_ram_data_internal = exp_ram_q;
    wire [7:0] final_data = is_cart ? cart_ram_data : (is_exp_ram ? exp_ram_data_internal : mem_q);
    
    // Memory output with error status
    assign mem_data = access_allowed ? final_data : access_error;

endmodule 