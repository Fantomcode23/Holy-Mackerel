`ifndef __ADD_FLOAT_V__
`define __ADD_FLOAT_V__

module addfloat
#(parameter
    FLOAT_WIDTH = 64
)
(
    input wire rst_n, clk, start,
    input wire op_sub, // high for subtraction, low for addition
    input wire [FLOAT_WIDTH - 1:0] op1, op2,
    output reg [FLOAT_WIDTH - 1:0] result,
    output reg nan_flag,
    output reg overflow_flag,
    output reg underflow_flag,
    output reg zero_flag,
    output done
);

localparam EXP_WIDTH = (FLOAT_WIDTH == 64) ? 11 : 8;
localparam FRACTION_WIDTH = (FLOAT_WIDTH == 64) ? 52 : 23;
localparam FULL_FRACTION_WIDTH = FRACTION_WIDTH + 3;
localparam SIGN_BIT = FLOAT_WIDTH - 1;
localparam EXP_MSB = SIGN_BIT - 1;
localparam EXP_LSB = EXP_MSB - EXP_WIDTH + 1;
localparam EXP_MAX = (2 ** EXP_WIDTH) - 1;
localparam FRACTION_MSB = EXP_LSB - 1;
localparam NAN_VALUE = (FLOAT_WIDTH == 64) ? 64'hFFF8_0000_0000_0000 : 32'hFFC0_0000;
localparam INF_VALUE = (FLOAT_WIDTH == 64) ? 64'h7FF0_0000_0000_0000 : 32'h7F80_0000;
localparam ZERO_DATA_WIDTH = 7;
localparam STAGES = 7;
localparam STAGES_WIDTH = 3;

reg [STAGES_WIDTH - 1:0] stage;
assign done = (stage == STAGES - 1);
wire [STAGES_WIDTH - 1:0] next_stage = (stage < STAGES - 1) ? stage + 1 : stage;

reg reset = 1'b0;

always @(negedge rst_n) begin
    reset = 1'b1;
end

always @(posedge clk) begin
    if (start || reset) begin
        stage <= 0;
        reset = 1'b0;
    end else begin
        stage <= next_stage;
    end
end

wire [EXP_WIDTH - 1:0] exp1 = op1[EXP_MSB:EXP_LSB];
wire [EXP_WIDTH - 1:0] exp2 = op2[EXP_MSB:EXP_LSB];

wire [FRACTION_WIDTH - 1:0] frac1 = op1[FRACTION_MSB:0];
wire [FRACTION_WIDTH - 1:0] frac2 = op2[FRACTION_MSB:0];

wire exp1_bigger = exp1 > exp2;
wire exp2_bigger = exp1 < exp2;
wire frac2_bigger = frac1 < frac2;

wire sign1 = op1[SIGN_BIT];
wire sign2 = op2[SIGN_BIT];

wire operation = sign1 ^ sign2 ^ op_sub;
wire swap_operands = (exp1 == exp2) && frac2_bigger || exp2_bigger;

reg [FLOAT_WIDTH - 1:0] left_operand, right_operand;

always @(posedge clk) begin
    if (stage == 0) begin
        if (swap_operands) begin
            left_operand <= op2;
            right_operand <= op1;
        end else begin
            left_operand <= op1;
            right_operand <= op2;
        end
    end
end

wire [FRACTION_WIDTH - 1:0] left_frac = left_operand[FRACTION_WIDTH - 1:0];
wire [EXP_WIDTH - 1:0] left_exp = left_operand[EXP_MSB:EXP_LSB];
wire [FRACTION_WIDTH - 1:0] right_frac = right_operand[FRACTION_WIDTH - 1:0];
wire [EXP_WIDTH - 1:0] right_exp = right_operand[EXP_MSB:EXP_LSB];
wire right_sign = right_operand[SIGN_BIT];
wire left_sign = left_operand[SIGN_BIT];

wire left_is_nan = &left_exp && (left_frac != 0);
wire right_is_nan = &right_exp && (right_frac != 0);
wire left_is_inf = &left_exp && (left_frac == 0);
wire right_is_inf = &right_exp && (right_frac == 0);
wire left_is_zero = left_exp == 0;
wire right_is_zero = right_exp == 0;

reg [FULL_FRACTION_WIDTH - 1:0] left_frac_wide, right_frac_wide;

always @(posedge clk) begin
    if (stage == 1) begin
        left_frac_wide <= left_is_zero ? 0 : {2'b01, left_frac, 1'b0};
        right_frac_wide <= right_is_zero ? 0 : {2'b01, right_frac, 1'b0} >> (left_exp - right_exp);
    end
end

reg [FULL_FRACTION_WIDTH - 1:0] frac_result;

always @(posedge clk) begin
    if (stage == 2) begin
        if (operation == 0) begin
            frac_result <= left_frac_wide + right_frac_wide;
        end else begin
            frac_result <= left_frac_wide - right_frac_wide;
        end
    end
end

reg [FULL_FRACTION_WIDTH - 1:0] frac_before_rounding;
reg [EXP_WIDTH + 1:0] result_exp;

wire [ZERO_DATA_WIDTH - 1:0] zero_count = zero_cnt(frac_result[FULL_FRACTION_WIDTH - 1:0]);
wire [ZERO_DATA_WIDTH - 1:0] exp_correction1 = (zero_count == 0) ? 0 : zero_count - 1;
wire exp_correction2 = frac_result[FULL_FRACTION_WIDTH - 1];

always @(posedge clk) begin
    if (stage == 3) begin
        frac_before_rounding <= (frac_result << exp_correction1) >> exp_correction2;
        result_exp <= left_exp - exp_correction1 + exp_correction2;
    end
end

reg [FULL_FRACTION_WIDTH - 1:0] rounded_frac;

always @(posedge clk) begin
    if (stage == 4) begin
        rounded_frac <= frac_before_rounding + 1'b1;
    end
end

wire is_nan_result = left_is_nan || right_is_nan || (left_is_inf && right_is_inf && operation);
wire is_overflow_result = result_exp[EXP_WIDTH] && !result_exp[EXP_WIDTH - 1];
wire is_inf_result = !is_nan_result && (left_is_inf || right_is_inf || is_overflow_result);
wire is_zero_result = rounded_frac[FRACTION_WIDTH:0] == 0;
wire is_underflow_result = !is_zero_result && (result_exp[EXP_WIDTH] || (result_exp[EXP_WIDTH - 1:0] == 0));
wire result_sign = left_sign ^ (swap_operands && op_sub);

always @(posedge clk) begin
    if (stage == 5) begin
        if (is_nan_result) begin
            result <= NAN_VALUE;
            nan_flag <= 1'b1;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
            zero_flag <= 1'b0;
        end else if (is_inf_result) begin
            result <= INF_VALUE | (result_sign << SIGN_BIT);
            nan_flag <= 1'b0;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
            zero_flag <= 1'b0;
        end else if (is_underflow_result) begin
            result <= result_sign << SIGN_BIT;
            nan_flag <= 1'b0;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b1;
            zero_flag <= 1'b0;
        end else if (is_zero_result) begin
            result <= result_sign << SIGN_BIT;
            nan_flag <= 1'b0;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
            zero_flag <= 1'b1;
        end else begin
            result <= {result_sign, result_exp[EXP_WIDTH - 1:0], rounded_frac[FRACTION_WIDTH:1]};
            nan_flag <= 1'b0;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
            zero_flag <= 1'b0;
        end
    end
end

function [ZERO_DATA_WIDTH - 1:0] zero_cnt;
    input [FRACTION_WIDTH + 2:0] in;
    integer i;
    begin
        zero_cnt = FRACTION_WIDTH + 3;
        for (i = FRACTION_WIDTH + 2; i >= 0; i = i - 1) begin
            if (in[i] && zero_cnt == FRACTION_WIDTH + 3)
                zero_cnt = FRACTION_WIDTH - i + 2;
        end
    end
endfunction

endmodule
`endif
