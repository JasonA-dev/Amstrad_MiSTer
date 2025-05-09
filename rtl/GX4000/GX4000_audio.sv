module GX4000_audio
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
    
    // Audio input from CPC
    input   [7:0] cpc_audio_l,
    input   [7:0] cpc_audio_r,
    
    // Sprite interface
    input   [7:0] sprite_id,
    input         sprite_collision,
    input   [7:0] sprite_movement,
    
    // Sample interface
    input         sample_wr,
    input  [15:0] sample_addr,
    input   [7:0] sample_data,
    
    // Video sync
    input         hblank,
    input         vblank,
    
    // Audio output
    output  [7:0] audio_l,
    output  [7:0] audio_r,
    
    // Status output
    output  [7:0] audio_status
);

    // Audio registers
    reg [7:0] volume_l;
    reg [7:0] volume_r;
    reg [7:0] tone_l;
    reg [7:0] tone_r;
    
    // Sound effect registers
    reg [7:0] sfx_volume[0:3];
    reg [7:0] sfx_freq[0:3];
    // reg [7:0] sfx_env[0:3]; // Future: Envelope control for sound effects
    reg [7:0] sfx_pan[0:3];
    reg       sfx_active[0:3];
    
    // Filter registers
    // reg [7:0] filter_cutoff; // Future: Cutoff frequency for audio filter
    reg [7:0] filter_resonance;
    reg [7:0] filter_mode;
    
    // Reverb registers
    reg [7:0] reverb_level;
    reg [7:0] reverb_time;
    // reg [7:0] reverb_feedback; // Future: Feedback amount for reverb effect
    
    // Audio state
    reg [7:0] phase_l;
    reg [7:0] phase_r;
    reg [7:0] noise_phase;
    reg [7:0] sfx_phase[0:3];
    reg [7:0] filter_state;
    reg [7:0] reverb_buffer[0:1023];
    reg [9:0] reverb_pos;
    
    // Sample playback registers
    reg [7:0] sample_mem[0:65535];  // 64KB sample memory
    reg [15:0] sample_start[0:3];
    reg [15:0] sample_end[0:3];
    reg [15:0] sample_pos[0:3];
    reg [7:0] sample_rate[0:3];
    // reg [1:0] sample_format[0:3]; // Future: Format specification for sample playback
    reg sample_loop[0:3];
    reg sample_active[0:3];
    
    // Waveform generation
    reg [7:0] wave_table[0:255];  // Waveform lookup table
    // reg [1:0] wave_type[0:3]; // Future: Waveform type selection for each channel
    
    // Envelope generators
    reg [7:0] env_attack[0:3];
    reg [7:0] env_decay[0:3];
    reg [7:0] env_sustain[0:3];
    reg [7:0] env_release[0:3];
    reg [7:0] env_level[0:3];
    reg [1:0] env_state[0:3];
    
    // Audio compression registers
    reg [7:0] comp_threshold;
    // reg [7:0] comp_ratio; // Future: Compression ratio for dynamics processing
    reg [7:0] comp_attack;
    reg [7:0] comp_release;
    reg [7:0] comp_gain;
    reg [7:0] comp_level;
    
    // Limiter registers
    reg [7:0] limit_threshold;
    reg [7:0] limit_release;
    reg [7:0] limit_level;
    
    // Noise generation registers
    reg [7:0] noise_type[0:3];
    reg [7:0] noise_freq[0:3];
    reg [7:0] noise_seed[0:3];
    reg [7:0] noise_state[0:3];
    
    // Audio sync registers
    reg [7:0] sync_counter;
    reg [7:0] sync_phase;
    reg [7:0] sync_error;
    // reg [7:0] sync_correction; // Future: Correction value for audio/video sync
    
    // Status registers
    reg [7:0] status_buffer;
    reg [7:0] status_error;
    // reg [7:0] status_processing; // Future: Status register for audio processing state
    
    // Audio processing
    always @(posedge clk_sys) begin
        if (reset) begin
            // Reset all registers
            volume_l <= 8'h00;
            volume_r <= 8'h00;
            tone_l <= 8'h00;
            tone_r <= 8'h00;
            phase_l <= 8'h00;
            phase_r <= 8'h00;
            noise_phase <= 8'h00;
            
            for (integer i = 0; i < 4; i = i + 1) begin
                sfx_volume[i] <= 8'h00;
                sfx_freq[i] <= 8'h00;
                // sfx_env[i] <= 8'h00;
                sfx_pan[i] <= 8'h00;
                sfx_active[i] <= 0;
                sfx_phase[i] <= 8'h00;
            end
            
            // filter_cutoff <= 8'h7F;
            filter_resonance <= 8'h00;
            filter_mode <= 8'h00;
            
            reverb_level <= 8'h00;
            reverb_time <= 8'h00;
            // reverb_feedback <= 8'h00;
            reverb_pos <= 10'h000;
            
            // Reset sample playback
            for (integer i = 0; i < 4; i = i + 1) begin
                sample_start[i] <= 16'h0000;
                sample_end[i] <= 16'h0000;
                sample_pos[i] <= 16'h0000;
                sample_rate[i] <= 8'h00;
                // sample_format[i] <= 2'b00;
                sample_loop[i] <= 0;
                sample_active[i] <= 0;
                // wave_type[i] <= 2'b00;
                env_attack[i] <= 8'h00;
                env_decay[i] <= 8'h00;
                env_sustain[i] <= 8'h00;
                env_release[i] <= 8'h00;
                env_level[i] <= 8'h00;
                env_state[i] <= 2'b00;
            end
            
            // Initialize waveform table
            for (integer i = 0; i < 256; i = i + 1) begin
                wave_table[i] <= i;  // Linear ramp for now
            end
            
            // Reset compression
            comp_threshold <= 8'h80;
            // comp_ratio <= 8'h40;
            comp_attack <= 8'h10;
            comp_release <= 8'h20;
            comp_gain <= 8'h80;
            comp_level <= 8'h00;
            
            // Reset limiter
            limit_threshold <= 8'hF0;
            limit_release <= 8'h20;
            limit_level <= 8'h00;
            
            // Reset noise
            for (integer i = 0; i < 4; i = i + 1) begin
                noise_type[i] <= 8'h00;
                noise_freq[i] <= 8'h00;
                noise_seed[i] <= 8'h01;
                noise_state[i] <= 8'h00;
            end
            
            // Reset sync
            sync_counter <= 8'h00;
            sync_phase <= 8'h00;
            sync_error <= 8'h00;
            // sync_correction <= 8'h00;
            
            // Reset status
            status_buffer <= 8'h00;
            status_error <= 8'h00;
            // status_processing <= 8'h00;
            
        end else if (gx4000_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    // Basic audio
                    8'h40: volume_l <= cpu_data;
                    8'h41: volume_r <= cpu_data;
                    8'h42: tone_l <= cpu_data;
                    8'h43: tone_r <= cpu_data;
                    8'h46: sfx_volume[0] <= cpu_data;
                    8'h47: sfx_freq[0] <= cpu_data;
                    8'h49: sfx_pan[0] <= cpu_data;
                    8'h4A: sfx_active[0] <= cpu_data[0];
                    8'h4B: sfx_volume[1] <= cpu_data;
                    8'h4C: sfx_freq[1] <= cpu_data;
                    8'h4E: sfx_pan[1] <= cpu_data;
                    8'h4F: sfx_active[1] <= cpu_data[0];
                    8'h50: sfx_volume[2] <= cpu_data;
                    8'h51: sfx_freq[2] <= cpu_data;
                    8'h53: sfx_pan[2] <= cpu_data;
                    8'h54: sfx_active[2] <= cpu_data[0];
                    8'h55: sfx_volume[3] <= cpu_data;
                    8'h56: sfx_freq[3] <= cpu_data;
                    8'h58: sfx_pan[3] <= cpu_data;
                    8'h59: sfx_active[3] <= cpu_data[0];
                    
                    // Filters
                    8'h5B: filter_resonance <= cpu_data;
                    8'h5C: filter_mode <= cpu_data;
                    
                    // Reverb
                    8'h5D: reverb_level <= cpu_data;
                    8'h5E: reverb_time <= cpu_data;
                endcase
            end
            
            // Audio generation
            phase_l <= 8'(phase_l + 1);
            phase_r <= 8'(phase_r + 1);
            noise_phase <= 8'(noise_phase + 1);
            
            // Sound effect generation
            for (integer i = 0; i < 4; i = i + 1) begin
                if (sfx_active[i]) begin
                    sfx_phase[i] <= 8'(sfx_phase[i] + sfx_freq[i]);
                end
            end
            
            // Filter processing
            case (filter_mode)
                8'h00: filter_state <= filter_state; // Bypass
                8'h01: begin // Low-pass
                    filter_state <= ((filter_state * filter_resonance) >> 8) + 
                                   (((phase_l + phase_r) * (8'hFF - filter_resonance)) >> 8);
                end
                8'h02: begin // High-pass
                    filter_state <= (((phase_l + phase_r) * filter_resonance) >> 8) + 
                                   ((filter_state * (8'hFF - filter_resonance)) >> 8);
                end
            endcase
            
            // Reverb processing
            reverb_pos <= 10'(reverb_pos + 1);
            reverb_buffer[reverb_pos] <= (phase_l + phase_r) >> 1;
            
            // Sample memory write
            if (sample_wr) begin
                sample_mem[sample_addr] <= sample_data;
            end
            
            // Sample playback
            for (integer i = 0; i < 4; i = i + 1) begin
                if (sample_active[i]) begin
                    // Update sample position
                    sample_pos[i] <= 16'(sample_pos[i] + sample_rate[i]);
                    
                    // Handle sample end
                    if (sample_pos[i] >= sample_end[i]) begin
                        if (sample_loop[i]) begin
                            sample_pos[i] <= sample_start[i];
                        end else begin
                            sample_active[i] <= 0;
                        end
                    end
                end
            end
            
            // Envelope generation
            for (integer i = 0; i < 4; i = i + 1) begin
                if (sfx_active[i]) begin
                    case (env_state[i])
                        2'b00: begin // Attack
                            if (env_level[i] < 8'hFF) begin
                                env_level[i] <= env_level[i] + env_attack[i];
                            end else begin
                                env_state[i] <= 2'b01;
                            end
                        end
                        2'b01: begin // Decay
                            if (env_level[i] > env_sustain[i]) begin
                                env_level[i] <= env_level[i] - env_decay[i];
                            end else begin
                                env_state[i] <= 2'b10;
                            end
                        end
                        2'b10: begin // Sustain
                            env_level[i] <= env_sustain[i];
                        end
                        2'b11: begin // Release
                            if (env_level[i] > 0) begin
                                env_level[i] <= env_level[i] - env_release[i];
                            end else begin
                                env_state[i] <= 2'b00;
                            end
                        end
                    endcase
                end
            end
            
            // Compression processing
            if (comp_level > comp_threshold) begin
                comp_level <= comp_level - comp_attack;
            end else begin
                comp_level <= comp_level + comp_release;
            end
            
            // Limiter processing
            if (limit_level > limit_threshold) begin
                limit_level <= limit_level - limit_release;
            end else begin
                limit_level <= limit_level + 1;
            end
            
            // Enhanced noise generation
            for (integer i = 0; i < 4; i = i + 1) begin
                if (noise_freq[i] > 0) begin
                    noise_state[i] <= 8'(noise_state[i] + 1);
                    if (noise_state[i] >= noise_freq[i]) begin
                        noise_state[i] <= 0;
                        case (noise_type[i])
                            8'h00: begin // White noise
                                noise_seed[i] <= {noise_seed[i][6:0], noise_seed[i][7] ^ noise_seed[i][5] ^ noise_seed[i][4] ^ noise_seed[i][1]};
                            end
                            8'h01: begin // Pink noise
                                noise_seed[i] <= {noise_seed[i][6:0], noise_seed[i][7] ^ noise_seed[i][3]};
                            end
                            8'h02: begin // Brown noise
                                noise_seed[i] <= 8'(noise_seed[i] + 1);
                            end
                        endcase
                    end
                end
            end
            
            // Audio sync with video
            if (hblank) begin
                sync_counter <= 8'(sync_counter + 1);
                if (sync_counter >= 8'hFF) begin
                    sync_counter <= 0;
                    sync_phase <= sync_phase + 1;
                end
            end
            
            // Status updates
            status_buffer <= {sample_active[0], sample_active[1], sample_active[2], sample_active[3], 
                            sfx_active[0], sfx_active[1], sfx_active[2], sfx_active[3]};
            status_error <= {comp_level > comp_threshold, limit_level > limit_threshold, 
                           sync_error > 0, status_buffer == 8'h00};
            // status_processing <= {comp_level[7], limit_level[7], sync_phase[0], 
            //                     noise_state[0][7], noise_state[1][7], noise_state[2][7], noise_state[3][7]};
        end
    end
    
    // Audio mixing
    wire [7:0] tone_out_l = (phase_l < tone_l) ? 8'hFF : 8'h00;
    wire [7:0] tone_out_r = (phase_r < tone_r) ? 8'hFF : 8'h00;
    // wire [7:0] noise_out_l = (noise_phase < noise_l) ? 8'hFF : 8'h00; // Future: Left channel noise output
    // wire [7:0] noise_out_r = (noise_phase < noise_r) ? 8'hFF : 8'h00; // Future: Right channel noise output
    
    // Sound effect mixing
    wire [7:0] sfx_out_l = 0;
    wire [7:0] sfx_out_r = 0;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sfx_mix
            wire [7:0] sfx_wave = (sfx_phase[i] < sfx_freq[i]) ? 8'hFF : 8'h00;
            assign sfx_out_l = sfx_out_l + 8'((sfx_wave * sfx_volume[i] * (8'hFF - sfx_pan[i]) * env_level[i]) >> 24);
            assign sfx_out_r = sfx_out_r + 8'((sfx_wave * sfx_volume[i] * sfx_pan[i] * env_level[i]) >> 24);
        end
    endgenerate
    
    // Sprite sound effects
    wire [7:0] sprite_sound_l = sprite_collision ? 8'hFF : 8'h00;
    wire [7:0] sprite_sound_r = sprite_movement ? 8'hFF : 8'h00;
    
    // Reverb mixing
    wire [7:0] reverb_out = reverb_buffer[(reverb_pos - reverb_time) & 10'h3FF];
    
    // Sample playback mixing
    wire [7:0] sample_out_l = 0;
    wire [7:0] sample_out_r = 0;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sample_mix
            wire [7:0] sample_data = sample_mem[sample_pos[i]];
            wire [7:0] sample_wave = wave_table[sample_data];
            assign sample_out_l = sample_out_l + (sample_wave * sfx_volume[i] * (8'hFF - sfx_pan[i]) * env_level[i]) >> 24;
            assign sample_out_r = sample_out_r + (sample_wave * sfx_volume[i] * sfx_pan[i] * env_level[i]) >> 24;
        end
    endgenerate
    
    // Enhanced noise output
    wire [7:0] enhanced_noise_out_l = 0;
    wire [7:0] enhanced_noise_out_r = 0;
    generate
        for (i = 0; i < 4; i = i + 1) begin : noise_mix
            wire [7:0] noise_wave = noise_seed[i];
            assign enhanced_noise_out_l = enhanced_noise_out_l + 8'((noise_wave * sfx_volume[i] * (8'hFF - sfx_pan[i])) >> 16);
            assign enhanced_noise_out_r = enhanced_noise_out_r + 8'((noise_wave * sfx_volume[i] * sfx_pan[i]) >> 16);
        end
    endgenerate
    
    // Audio compression
    wire [7:0] compressed_l = (sample_out_l * comp_gain) >> 8;
    wire [7:0] compressed_r = (sample_out_r * comp_gain) >> 8;
    
    // Audio limiting
    wire [7:0] limited_l = (compressed_l > limit_threshold) ? limit_threshold : compressed_l;
    wire [7:0] limited_r = (compressed_r > limit_threshold) ? limit_threshold : compressed_r;
    
    // Final audio output with all effects
    assign audio_l = ((cpc_audio_l * volume_l) >> 8) + 
                     ((tone_out_l * volume_l) >> 8) + 
                     // (noise_out_l * volume_l) >> 8 + // Commented out
                     enhanced_noise_out_l + 
                     sfx_out_l + 
                     limited_l +
                     sprite_sound_l + 
                     ((reverb_out * reverb_level) >> 8);
    
    assign audio_r = ((cpc_audio_r * volume_r) >> 8) + 
                     ((tone_out_r * volume_r) >> 8) + 
                     // (noise_out_r * volume_r) >> 8 + // Commented out
                     enhanced_noise_out_r + 
                     sfx_out_r + 
                     limited_r +
                     sprite_sound_r + 
                     ((reverb_out * reverb_level) >> 8);
    
    // Status output
    assign audio_status = {status_buffer[7:4], status_error[3:0]};

endmodule 
