module tzxplayer #(
    parameter TZX_MS = 64000,       // CE periods for one milliseconds
    // Default: ZX Spectrum
    parameter NORMAL_PILOT_LEN    = 2168,
    parameter NORMAL_SYNC1_LEN    = 667,
    parameter NORMAL_SYNC2_LEN    = 735,
    parameter NORMAL_ZERO_LEN     = 855,
    parameter NORMAL_ONE_LEN      = 1710,
    parameter HEADER_PILOT_PULSES = 8063, // this is the header length
    parameter NORMAL_PILOT_PULSES = 3223  // this is the non-header length

    // Amstrad CPC
    //NORMAL_PILOT_LEN    = 2000,
    //NORMAL_SYNC1_LEN    = 855,
    //NORMAL_SYNC2_LEN    = 855,
    //NORMAL_ZERO_LEN     = 855,
    //NORMAL_ONE_LEN      = 1710,
    //HEADER_PILOT_PULSES = 4095, // no difference between header and data pilot lengths
    //NORMAL_PILOT_PULSES = 4095
) (
    input         clk,
    input         ce,
    input         restart_tape,

    input   [7:0] host_tap_in,     // 8bits fifo input
    output        tzx_req,         // request for new byte (edge trigger)
    input         tzx_ack,         // new data available
    output        loop_start,      // active for one clock if a loop starts
    output        loop_next,       // active for one clock at the next iteration
    output        stop,           // tape should be stopped
    output        stop48k,        // tape should be stopped in 48k mode
    output        cass_read,      // tape read signal
    input         cass_motor,     // 1 = tape motor is powered
    output        cass_running    // tape is running
);

// State definitions
localparam TZX_HEADER = 0;
localparam TZX_NEWBLOCK = 1;
localparam TZX_LOOP_START = 2;
localparam TZX_LOOP_END = 3;
localparam TZX_PAUSE = 4;
localparam TZX_PAUSE2 = 5;
localparam TZX_STOP48K = 6;
localparam TZX_HWTYPE = 7;
localparam TZX_TEXT = 8;
localparam TZX_MESSAGE = 9;
localparam TZX_ARCHIVE_INFO = 10;
localparam TZX_CUSTOM_INFO = 11;
localparam TZX_GLUE = 12;
localparam TZX_TONE = 13;
localparam TZX_PULSES = 14;
localparam TZX_DATA = 15;
localparam TZX_NORMAL = 16;
localparam TZX_TURBO = 17;
localparam TZX_PLAY_TONE = 18;
localparam TZX_PLAY_SYNC1 = 19;
localparam TZX_PLAY_SYNC2 = 20;
localparam TZX_PLAY_TAPBLOCK = 21;
localparam TZX_PLAY_TAPBLOCK2 = 22;
localparam TZX_PLAY_TAPBLOCK3 = 23;
localparam TZX_PLAY_TAPBLOCK4 = 24;
localparam TZX_DIRECT = 25;
localparam TZX_DIRECT2 = 26;
localparam TZX_DIRECT3 = 27;

reg  [7:0] tap_fifo_do;
reg [16:0] tick_cnt;
reg [23:0] wave_cnt;
reg        wave_period;
reg        wave_inverted;
reg        skip_bytes;
reg        playing;  // 1 = tap or wav file is playing
reg  [2:0] bit_cnt;

reg  [4:0] tzx_state;
reg  [7:0] tzx_offset;
reg [15:0] pause_len;
reg [15:0] ms_counter;
reg [15:0] pilot_l;
reg [15:0] sync1_l;
reg [15:0] sync2_l;
reg [15:0] zero_l;
reg [15:0] one_l;
reg [15:0] pilot_pulses;
reg  [3:0] last_byte_bits;
reg [23:0] data_len;
reg [15:0] pulse_len;
reg        end_period;
reg        cass_motor_D;
reg [21:0] motor_counter;
reg [15:0] loop_iter;
reg [31:0] data_len_dword;

assign cass_read = wave_period;
assign cass_running = playing;
assign tap_fifo_do = host_tap_in;

always @(posedge clk) begin
    if (restart_tape) begin
        tzx_offset <= 0;
        tzx_state <= TZX_HEADER;
        pulse_len <= 0;
        motor_counter <= 0;
        wave_period <= 0;
        playing <= 0;
        tzx_req <= tzx_ack;
        loop_start <= 0;
        loop_next <= 0;
        loop_iter <= 0;
        wave_inverted <= 0;
    end else begin
        // simulate tape motor momentum
        // don't change the playing state if the motor is switched in 50 ms
        // Opera Soft K17 protection needs this!
        cass_motor_D <= cass_motor;
        if (cass_motor_D != cass_motor) begin
            motor_counter <= 50*TZX_MS;
        end else if (motor_counter != 0) begin
            if (ce) motor_counter <= motor_counter - 1;
        end else begin
            playing <= cass_motor;
        end

        if (!playing) begin
            //cass_read <= 1;
        end

        if (pulse_len != 0) begin
            if (ce) begin
                tick_cnt <= tick_cnt + 3500;
                if (tick_cnt >= TZX_MS) begin
                    tick_cnt <= tick_cnt - TZX_MS;
                    wave_cnt <= wave_cnt + 1;
                    if (wave_cnt == pulse_len - 1) begin
                        wave_cnt <= 0;
                        if (wave_period == end_period) begin
                            pulse_len <= 0;
                        end else begin
                            wave_period <= ~wave_period;
                        end
                    end
                end
            end
        end else begin
            wave_cnt <= 0;
            tick_cnt <= 0;
        end

        loop_start <= 0;
        loop_next <= 0;
        stop <= 0;
        stop48k <= 0;

        if (playing && pulse_len == 0 && tzx_req == tzx_ack) begin
            tzx_req <= ~tzx_ack; // default request for new data

            case (tzx_state)
                TZX_HEADER: begin
                    wave_period <= 1;
                    wave_inverted <= 0;
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 8'h0A) begin // skip 9 bytes, offset lags 1
                        tzx_state <= TZX_NEWBLOCK;
                    end
                end

                TZX_NEWBLOCK: begin
                    tzx_offset <= 0;
                    ms_counter <= 0;
                    case (tap_fifo_do)
                        8'h10: tzx_state <= TZX_NORMAL;
                        8'h11: tzx_state <= TZX_TURBO;
                        8'h12: tzx_state <= TZX_TONE;
                        8'h13: tzx_state <= TZX_PULSES;
                        8'h14: tzx_state <= TZX_DATA;
                        8'h15: tzx_state <= TZX_DIRECT;
                        // 8'h18: null; // CSW recording (not implemented)
                        // 8'h19: null; // Generalized data block (not implemented)
                        8'h20: tzx_state <= TZX_PAUSE;
                        8'h21: tzx_state <= TZX_TEXT; // Group start
                        // 8'h22: null; // Group end
                        // 8'h23: null; // Jump to block (not implemented)
                        8'h24: tzx_state <= TZX_LOOP_START;
                        8'h25: tzx_state <= TZX_LOOP_END;
                        // 8'h26: null; // Call sequence (not implemented)
                        // 8'h27: null; // Return from sequence (not implemented)
                        // 8'h28: null; // Select block (not implemented)
                        8'h2A: tzx_state <= TZX_STOP48K;
                        // 8'h2B: null; // Set signal level (not implemented)
                        8'h30: tzx_state <= TZX_TEXT;
                        8'h31: tzx_state <= TZX_MESSAGE;
                        8'h32: tzx_state <= TZX_ARCHIVE_INFO;
                        8'h33: tzx_state <= TZX_HWTYPE;
                        8'h35: tzx_state <= TZX_CUSTOM_INFO;
                        8'h5A: tzx_state <= TZX_GLUE;
                    endcase
                end

                TZX_LOOP_START: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        loop_iter[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        loop_iter[15:8] <= tap_fifo_do;
                        tzx_state <= TZX_NEWBLOCK;
                        loop_start <= 1;
                    end
                end

                TZX_LOOP_END: begin
                    if (loop_iter > 1) begin
                        loop_iter <= loop_iter - 1;
                        loop_next <= 1;
                    end else begin
                        tzx_req <= tzx_ack; // don't request new byte
                    end
                    tzx_state <= TZX_NEWBLOCK;
                end

                TZX_PAUSE: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        pause_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        pause_len[15:8] <= tap_fifo_do;
                        tzx_state <= TZX_PAUSE2;
                        if (pause_len[7:0] == 0 && tap_fifo_do == 0) begin
                            stop <= 1;
                        end
                    end
                end

                TZX_PAUSE2: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    if (ms_counter != 0) begin
                        if (ce) begin
                            ms_counter <= ms_counter - 1;
                            // Set pulse level to low after 1 ms
                            if (ms_counter == 1) begin
                                wave_inverted <= 0;
                                wave_period <= 0;
                                end_period <= 0;
                            end
                        end
                    end else if (pause_len != 0) begin
                        pause_len <= pause_len - 1;
                        ms_counter <= TZX_MS;
                    end else begin
                        tzx_state <= TZX_NEWBLOCK;
                    end
                end

                TZX_STOP48K: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 3) begin
                        stop48k <= 1;
                        tzx_state <= TZX_NEWBLOCK;
                    end
                end

                TZX_HWTYPE: begin
                    tzx_offset <= tzx_offset + 1;
                    // 0, 1-3, 1-3, ...
                    if (tzx_offset == 0) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        if (data_len[7:0] == 1) begin
                            tzx_state <= TZX_NEWBLOCK;
                        end else begin
                            data_len[7:0] <= data_len[7:0] - 1;
                            tzx_offset <= 1;
                        end
                    end
                end

                TZX_MESSAGE: begin
                    // skip display time, then then same as TEXT DESRCRIPTION
                    tzx_state <= TZX_TEXT;
                end

                TZX_TEXT: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == data_len[7:0]) begin
                        tzx_state <= TZX_NEWBLOCK;
                    end
                end

                TZX_ARCHIVE_INFO: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        data_len[15:8] <= tap_fifo_do;
                    end else begin
                        tzx_offset <= 2;
                        data_len <= data_len - 1;
                        if (data_len == 1) begin
                            tzx_state <= TZX_NEWBLOCK;
                        end
                    end
                end

                TZX_CUSTOM_INFO: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 8'h10) begin
                        data_len_dword[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 8'h11) begin
                        data_len_dword[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 8'h12) begin
                        data_len_dword[23:16] <= tap_fifo_do;
                    end else if (tzx_offset == 8'h13) begin
                        data_len_dword[31:24] <= tap_fifo_do;
                    end else if (tzx_offset == 8'h14) begin
                        tzx_offset <= 8'h14;
                        if (data_len_dword == 1) begin
                            tzx_state <= TZX_NEWBLOCK;
                        end else begin
                            data_len_dword <= data_len_dword - 1;
                        end
                    end
                end

                TZX_GLUE: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 8'h08) begin
                        tzx_state <= TZX_NEWBLOCK;
                    end
                end

                TZX_TONE: begin
                    tzx_offset <= tzx_offset + 1;
                    // 0, 1, 2, 3, 4, 4, 4, ...
                    if (tzx_offset == 0) begin
                        pilot_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        pilot_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        pilot_pulses[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        tzx_req <= tzx_ack; // don't request new byte
                        pilot_pulses[15:8] <= tap_fifo_do;
                    end else begin
                        tzx_offset <= 4;
                        tzx_req <= tzx_ack; // don't request new byte
                        if (pilot_pulses == 0) begin
                            tzx_req <= ~tzx_ack; // default request for new data
                            tzx_state <= TZX_NEWBLOCK;
                        end else begin
                            pilot_pulses <= pilot_pulses - 1;
                            if (!wave_inverted) begin
                                wave_period <= ~wave_period;
                                end_period <= ~wave_period; // request pulse
                            end else begin
                                wave_inverted <= 0;
                                end_period <= wave_period;
                            end
                            pulse_len <= pilot_l;
                        end
                    end
                end

                TZX_PULSES: begin
                    tzx_offset <= tzx_offset + 1;
                    // 0, 1-2+3, 1-2+3, ...
                    if (tzx_offset == 0) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        one_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        tzx_req <= tzx_ack; // don't request new byte
                        if (!wave_inverted) begin
                            wave_period <= ~wave_period;
                            end_period <= ~wave_period; // request pulse
                        end else begin
                            wave_inverted <= 0;
                            end_period <= wave_period;
                        end
                        pulse_len <= {tap_fifo_do, one_l[7:0]};
                    end else if (tzx_offset == 3) begin
                        if (data_len[7:0] == 1) begin
                            tzx_state <= TZX_NEWBLOCK;
                        end else begin
                            data_len[7:0] <= data_len[7:0] - 1;
                            tzx_offset <= 1;
                        end
                    end
                end

                TZX_DATA: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        zero_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        zero_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        one_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        one_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 4) begin
                        last_byte_bits <= tap_fifo_do[3:0];
                    end else if (tzx_offset == 5) begin
                        pause_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 6) begin
                        pause_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 7) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 8) begin
                        data_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 9) begin
                        data_len[23:16] <= tap_fifo_do;
                        tzx_state <= TZX_PLAY_TAPBLOCK;
                    end
                end

                TZX_NORMAL: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        pause_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        pause_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        data_len[15:8] <= tap_fifo_do;
                        data_len[23:16] <= 0;
                    end else if (tzx_offset == 4) begin
                        // this is the first data byte to determine if it's a header or data block (on Speccy)
                        tzx_req <= tzx_ack; // don't request new byte
                        pilot_l <= NORMAL_PILOT_LEN;
                        sync1_l <= NORMAL_SYNC1_LEN;
                        sync2_l <= NORMAL_SYNC2_LEN;
                        zero_l <= NORMAL_ZERO_LEN;
                        one_l <= NORMAL_ONE_LEN;
                        if (tap_fifo_do == 0) begin
                            pilot_pulses <= HEADER_PILOT_PULSES;
                        end else begin
                            pilot_pulses <= NORMAL_PILOT_PULSES;
                        end
                        last_byte_bits <= 4'h8;
                        tzx_state <= TZX_PLAY_TONE;
                    end
                end

                TZX_TURBO: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        pilot_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 1) begin
                        pilot_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        sync1_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        sync1_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 4) begin
                        sync2_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 5) begin
                        sync2_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 6) begin
                        zero_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 7) begin
                        zero_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 8) begin
                        one_l[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 9) begin
                        one_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 10) begin
                        pilot_pulses[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 11) begin
                        pilot_pulses[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 12) begin
                        last_byte_bits <= tap_fifo_do[3:0];
                    end else if (tzx_offset == 13) begin
                        pause_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 14) begin
                        pause_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 15) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 16) begin
                        data_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 17) begin
                        data_len[23:16] <= tap_fifo_do;
                        tzx_state <= TZX_PLAY_TONE;
                    end
                end

                TZX_PLAY_TONE: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    if (!wave_inverted) begin
                        wave_period <= ~wave_period;
                        end_period <= ~wave_period; // request pulse
                    end else begin
                        end_period <= wave_period;
                        wave_inverted <= 0;
                    end
                    pulse_len <= pilot_l;
                    if (pilot_pulses == 1) begin
                        tzx_state <= TZX_PLAY_SYNC1;
                    end else begin
                        pilot_pulses <= pilot_pulses - 1;
                    end
                end

                TZX_PLAY_SYNC1: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    wave_period <= ~wave_period;
                    end_period <= ~wave_period; // request pulse
                    pulse_len <= sync1_l;
                    tzx_state <= TZX_PLAY_SYNC2;
                end

                TZX_PLAY_SYNC2: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    wave_period <= ~wave_period;
                    end_period <= ~wave_period; // request pulse
                    pulse_len <= sync2_l;
                    tzx_state <= TZX_PLAY_TAPBLOCK;
                end

                TZX_PLAY_TAPBLOCK: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    bit_cnt <= 3'h7;
                    tzx_state <= TZX_PLAY_TAPBLOCK2;
                end

                TZX_PLAY_TAPBLOCK2: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    bit_cnt <= bit_cnt - 1;
                    if (bit_cnt == 0 || (data_len == 1 && ((bit_cnt == (8 - last_byte_bits)) || (last_byte_bits == 0)))) begin
                        data_len <= data_len - 1;
                        tzx_state <= TZX_PLAY_TAPBLOCK3;
                    end
                    if (!wave_inverted) begin
                        wave_period <= ~wave_period;
                        end_period <= wave_period; // request full period
                    end else begin
                        end_period <= ~wave_period;
                        wave_inverted <= 0;
                    end
                    if (!tap_fifo_do[bit_cnt]) begin
                        pulse_len <= zero_l;
                    end else begin
                        pulse_len <= one_l;
                    end
                end

                TZX_PLAY_TAPBLOCK3: begin
                    if (data_len == 0) begin
                        wave_period <= ~wave_period;
                        wave_inverted <= 1;
                        tzx_state <= TZX_PAUSE2;
                    end else begin
                        tzx_state <= TZX_PLAY_TAPBLOCK4;
                    end
                end

                TZX_PLAY_TAPBLOCK4: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    tzx_state <= TZX_PLAY_TAPBLOCK2;
                end

                TZX_DIRECT: begin
                    tzx_offset <= tzx_offset + 1;
                    if (tzx_offset == 0) begin
                        zero_l[7:0] <= tap_fifo_do; // here this is used for one bit, too
                    end else if (tzx_offset == 1) begin
                        zero_l[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 2) begin
                        pause_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 3) begin
                        pause_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 4) begin
                        last_byte_bits <= tap_fifo_do[3:0];
                    end else if (tzx_offset == 5) begin
                        data_len[7:0] <= tap_fifo_do;
                    end else if (tzx_offset == 6) begin
                        data_len[15:8] <= tap_fifo_do;
                    end else if (tzx_offset == 7) begin
                        data_len[23:16] <= tap_fifo_do;
                        tzx_state <= TZX_DIRECT2;
                        bit_cnt <= 3'h7;
                    end
                end

                TZX_DIRECT2: begin
                    tzx_req <= tzx_ack; // don't request new byte
                    bit_cnt <= bit_cnt - 1;
                    if (bit_cnt == 0 || (data_len == 1 && ((bit_cnt == (8 - last_byte_bits)) || (last_byte_bits == 0)))) begin
                        data_len <= data_len - 1;
                        tzx_state <= TZX_DIRECT3;
                    end

                    pulse_len <= zero_l;
                    wave_period <= tap_fifo_do[bit_cnt];
                    end_period <= tap_fifo_do[bit_cnt];
                end

                TZX_DIRECT3: begin
                    if (data_len == 0) begin
                        wave_inverted <= 0;
                        tzx_state <= TZX_PAUSE2;
                    end else begin
                        tzx_state <= TZX_DIRECT2;
                    end
                end
            endcase
        end
    end
end

endmodule 