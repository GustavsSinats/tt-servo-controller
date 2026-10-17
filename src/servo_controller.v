`default_nettype none

module tt_um_gustavssinats_servo_controller (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // IMPORTANT:
    // This must match the actual clock supplied to the chip.
    localparam integer CLK_HZ = 1000000;

    wire servo_pwm;
    wire [1:0] command;

    servo_controller #(
        .CLK_HZ(CLK_HZ),

        // Swap these if your servo rotates the opposite way.
        .CCW_US(1000),
        .CW_US(2000),

        .NEUTRAL_US(1500)
    ) controller (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (ena),

        .button_1  (ui_in[0]),
        .button_2  (ui_in[1]),
        .button_3  (ui_in[2]),

        .servo_pwm (servo_pwm),
        .command   (command)
    );

    // uo_out[0]   = servo control signal
    // uo_out[2:1] = stored command for debugging
    assign uo_out = {
        5'b00000,
        command,
        servo_pwm
    };

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused = &{ui_in[7:3], uio_in, 1'b0};

endmodule


module servo_controller #(
    // Must be an integer multiple of 1 MHz,
    // and at least 1 MHz.
    parameter integer CLK_HZ = 1000000,

    parameter integer CCW_US     = 1000,
    parameter integer CW_US      = 2000,
    parameter integer NEUTRAL_US = 1500
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,

    // Active-high buttons.
    input  wire button_1,
    input  wire button_2,
    input  wire button_3,

    output wire servo_pwm,
    output reg [1:0] command
);

    localparam integer CLOCKS_PER_US = CLK_HZ / 1000000;

    localparam integer DIV_WIDTH =
        (CLOCKS_PER_US <= 1) ? 1 : $clog2(CLOCKS_PER_US);

    localparam [DIV_WIDTH-1:0] DIV_LAST =
        DIV_WIDTH'(CLOCKS_PER_US - 1);

    localparam [14:0] CCW_PULSE     = 15'(CCW_US);
    localparam [14:0] CW_PULSE      = 15'(CW_US);
    localparam [14:0] NEUTRAL_PULSE = 15'(NEUTRAL_US);

    // Button synchronizers.
    reg [2:0] buttons_meta;
    reg [2:0] buttons_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            buttons_meta <= 3'b000;
            buttons_sync <= 3'b000;
        end else begin
            buttons_meta <= {
                button_3,
                button_2,
                button_1
            };

            buttons_sync <= buttons_meta;
        end
    end

    // Stored command:
    // 0 = neutral
    // 1 = anticlockwise command
    // 2 = clockwise command
    always @(posedge clk) begin
        if (!rst_n) begin
            command <= 2'd0;
        end else if (!enable) begin
            command <= 2'd0;
        end else begin
            if (buttons_sync[2])
                command <= 2'd0;
            else if (buttons_sync[0])
                command <= 2'd1;
            else if (buttons_sync[1])
                command <= 2'd2;
        end
    end

    reg [14:0] requested_pulse_us;

    always @(*) begin
        case (command)
            2'd1:
                requested_pulse_us = CCW_PULSE;

            2'd2:
                requested_pulse_us = CW_PULSE;

            default:
                requested_pulse_us = NEUTRAL_PULSE;
        endcase
    end

    reg [DIV_WIDTH-1:0] us_divider;

    // 0 through 19999 microseconds.
    reg [14:0] frame_us;

    // Pulse width used for the current frame.
    reg [14:0] active_pulse_us;

    always @(posedge clk) begin
        if (!rst_n) begin
            us_divider     <= {DIV_WIDTH{1'b0}};
            frame_us       <= 15'd0;
            active_pulse_us <= NEUTRAL_PULSE;

        end else if (!enable) begin
            us_divider     <= {DIV_WIDTH{1'b0}};
            frame_us       <= 15'd0;
            active_pulse_us <= NEUTRAL_PULSE;

        end else begin
            if (us_divider == DIV_LAST) begin
                us_divider <= {DIV_WIDTH{1'b0}};

                if (frame_us == 15'd19999) begin
                    frame_us <= 15'd0;

                    // Update only at the start of a new frame.
                    active_pulse_us <= requested_pulse_us;
                end else begin
                    frame_us <= frame_us + 15'd1;
                end
            end else begin
                us_divider <= us_divider + 1'b1;
            end
        end
    end

    assign servo_pwm =
        rst_n &&
        enable &&
        (frame_us < active_pulse_us);

endmodule

`default_nettype wire
