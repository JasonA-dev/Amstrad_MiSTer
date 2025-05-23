// DMA command fetch state machine
localparam DMA_IDLE      = 2'b00;
localparam DMA_FETCH_LO  = 2'b01;
localparam DMA_FETCH_HI  = 2'b10;
localparam DMA_EXECUTE   = 2'b11;

module GX4000_audio
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Audio input from CPC
    input   [7:0] cpc_audio_l,
    input   [7:0] cpc_audio_r,
    
    // Sprite interface
    input   [7:0] sprite_id,
    input         sprite_collision,
    input   [7:0] sprite_movement,
    
    // Video sync
    input         hblank,
    input         vblank,
    
    // Audio output
    output reg [7:0] audio_l,
    output reg [7:0] audio_r,
    
    // Status output
    output  [7:0] audio_status,
    
    // Audio control registers
    input   [7:0] audio_control,
    input   [7:0] audio_config,
    input   [7:0] audio_volume,
    
    // DMA outputs
    output reg [2:0] dma_status,
    output        dma_irq,

    // PSG interface
    output  [7:0] psg_address,
    output  [7:0] psg_data,
    output        psg_wr,
    input   [7:0] psg_ch_a,
    input   [7:0] psg_ch_b,
    input   [7:0] psg_ch_c,

    // Add input for DMA HSYNC pulse
    input dma_hsync_pulse,

    // Add ASIC RAM interface for DMA
    output reg [13:0] asic_ram_addr,
    input      [7:0]  asic_ram_q,

    // Add video_control input
    input   [7:0] video_control
);

    // DMA state for each channel
    reg [1:0] dma_state;
    reg [1:0] dma_active_ch; // 0,1,2 (round-robin)
    reg [15:0] dma_command;
    reg       dma_pending;

    // Audio registers
    reg [7:0] volume_l;
    reg [7:0] volume_r;
    reg [7:0] tone_l;
    reg [7:0] tone_r;
    reg [7:0] phase_l;
    reg [7:0] phase_r;
    reg [7:0] noise_phase;
    
    // Sound effect registers
    reg [7:0] sfx_volume[0:3];
    reg [7:0] sfx_freq[0:3];
    reg [7:0] sfx_pan[0:3];
    reg [3:0] sfx_active;
    reg [7:0] sfx_phase[0:3];
    
    // Filter registers
    reg [7:0] filter_resonance;
    reg [7:0] filter_mode;
    reg [7:0] filter_state;
    reg [7:0] filter_coeff[0:3];  // Filter coefficients for different modes
    
    // Reverb registers
    reg [7:0] reverb_level;
    reg [7:0] reverb_time;
    reg [7:0] reverb_buffer[0:1023];
    reg [9:0] reverb_pos;
    reg [7:0] reverb_coeff[0:3];  // Reverb coefficients for different modes
    
    // Audio compression registers
    reg [7:0] comp_threshold;
    reg [7:0] comp_attack;
    reg [7:0] comp_release;
    reg [7:0] comp_gain;
    reg [7:0] comp_level;
    reg [7:0] comp_ratio;  // Added compression ratio
    
    // Limiter registers
    reg [7:0] limit_threshold;
    reg [7:0] limit_release;
    reg [7:0] limit_level;
    reg [7:0] limit_coeff;  // Limiter coefficient
    
    // Audio processing pipeline
    reg [7:0] audio_pipeline[0:7];  // Pipeline stages for audio processing
    reg [7:0] audio_temp[0:3];      // Temporary storage for processing
    
    // Audio processing constants
    localparam FILTER_LOWPASS = 2'b00;   // Low-pass filter
    localparam FILTER_HIGHPASS = 2'b01;  // High-pass filter
    localparam FILTER_BANDPASS = 2'b10;  // Band-pass filter
    localparam FILTER_NOTCH = 2'b11;     // Notch filter

    localparam REVERB_ROOM = 2'b00;      // Room reverb
    localparam REVERB_HALL = 2'b01;      // Hall reverb
    localparam REVERB_PLATE = 2'b10;     // Plate reverb
    localparam REVERB_SPRING = 2'b11;    // Spring reverb

    // DMA registers
    reg [15:0] dma_addr[2:0];
    reg [7:0] dma_prescaler[2:0];
    reg [2:0] internal_dma_status;
    reg dma_clear;
    reg dma_irq_reg;

    // DMA state for each channel
    reg [11:0] dma_pause[2:0];
    reg [15:0] dma_repeat[2:0];
    reg [11:0] dma_loopcount[2:0];
    reg [1:0] dma_channel;
    reg [7:0] prev_reg;
    reg [7:0] irq_cause;

    // Add input for DMA HSYNC pulse
    reg prev_dma_hsync_pulse;

    assign dma_irq = dma_irq_reg;

    // integer declarations for for-loops
    integer i;
    integer ch;

    // Initialize registers
    initial begin
        volume_l = 8'h00;
        volume_r = 8'h00;
        tone_l = 8'h00;
        tone_r = 8'h00;
        phase_l = 8'h00;
        phase_r = 8'h00;
        noise_phase = 8'h00;
        filter_resonance = 8'h00;
        filter_mode = 8'h00;
        filter_state = 8'h00;
        reverb_level = 8'h00;
        reverb_time = 8'h00;
        reverb_pos = 10'h000;
        comp_threshold = 8'h00;
        comp_attack = 8'h00;
        comp_release = 8'h00;
        comp_gain = 8'h00;
        comp_level = 8'h00;
        comp_ratio = 8'h00;
        limit_threshold = 8'h00;
        limit_release = 8'h00;
        limit_level = 8'h00;
        limit_coeff = 8'h00;
        sfx_active = 4'h0;
        for (i = 0; i < 4; i = i + 1) begin
            sfx_volume[i] = 8'h00;
            sfx_freq[i] = 8'h00;
            sfx_pan[i] = 8'h00;
            sfx_phase[i] = 8'h00;
            filter_coeff[i] = 8'h00;
            reverb_coeff[i] = 8'h00;
        end
        for (i = 0; i < 8; i = i + 1) begin
            audio_pipeline[i] = 8'h00;
        end
        for (i = 0; i < 4; i = i + 1) begin
            audio_temp[i] = 8'h00;
        end
        dma_clear <= 1'b0;
        internal_dma_status <= 3'b000;
        for (i = 0; i < 3; i = i + 1) begin
            dma_addr[i] <= 16'h0000;
            dma_prescaler[i] <= 8'h00;
        end
        dma_irq_reg <= 1'b0;
        for (ch = 0; ch < 3; ch = ch + 1) begin
            dma_pause[ch] <= 0;
            dma_repeat[ch] <= 0;
            dma_loopcount[ch] <= 0;
        end
    end

    // DMA command processing
    always @(posedge clk_sys) begin
        if (reset) begin
            dma_state <= DMA_IDLE;
            dma_active_ch <= 2'b00;
            dma_command <= 16'h0000;
            dma_pending <= 1'b0;
        end else begin
            case (dma_state)
                DMA_IDLE: begin
                    if (dma_pending) begin
                        dma_state <= DMA_FETCH_LO;
                    end
                end
                DMA_FETCH_LO: begin
                    dma_command[7:0] <= asic_ram_q;
                    dma_state <= DMA_FETCH_HI;
                end
                DMA_FETCH_HI: begin
                    dma_command[15:8] <= asic_ram_q;
                    dma_state <= DMA_EXECUTE;
                end
                DMA_EXECUTE: begin
                    case (dma_command[15:12])
                        4'h0: begin // LOAD PSG register
                            psg_address <= (dma_command[11:8]);
                            psg_data <= dma_command[7:0];
                            psg_wr <= 1;
                            prev_reg <= psg_address;
                        end
                        4'h1: begin // PAUSE
                            dma_pause[dma_active_ch] <= dma_command[11:0] - 1;
                        end
                        4'h2: begin // REPEAT
                            dma_repeat[dma_active_ch] <= dma_addr[dma_active_ch];
                            dma_loopcount[dma_active_ch] <= dma_command[11:0];
                        end
                        4'h4: begin // Control
                            if (dma_command[0]) begin // LOOP
                                if (dma_loopcount[dma_active_ch] > 0) begin
                                    dma_addr[dma_active_ch] <= dma_repeat[dma_active_ch];
                                    dma_loopcount[dma_active_ch] <= dma_loopcount[dma_active_ch] - 1;
                                end
                            end
                            if (dma_command[4]) begin // INT
                                irq_cause <= dma_active_ch * 2;
                                // TODO: Implement status update using asic_ram_addr/asic_ram_q, not direct array access.
                            end
                            if (dma_command[5]) begin // STOP
                                dma_status[dma_active_ch] <= 0;
                            end
                        end
                        default: begin
                            // Unknown command
                        end
                    endcase
                    dma_addr[dma_active_ch] <= dma_addr[dma_active_ch] + 2;
                    psg_wr <= 0; // Clear PSG write after use
                    // Move to next channel for next HSYNC
                    dma_active_ch <= (dma_active_ch == 2) ? 0 : dma_active_ch + 1;
                    dma_state <= DMA_IDLE;
                end
            endcase
        end
    end

    // DMA trigger from video_control
    always @(posedge clk_sys) begin
        if (reset) begin
            dma_pending <= 1'b0;
        end else begin
            // Bit 0: DMA start, Bit 1: DMA stop
            if (video_control[0]) begin
                dma_pending <= 1'b1;
            end
            if (video_control[1]) begin
                dma_pending <= 1'b0;
            end
        end
    end

endmodule 
