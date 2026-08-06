
// 8-digit multiplexed 7-segment display driver
// val[31:28] = leftmost digit, val[3:0] = rightmost
module seg7_driver (
    input        clk,
    input        rst,
    input [31:0] val,
    output [7:0] an,
    output reg [6:0] seg
);
    localparam [6:0]
        C0=7'b1000000, C1=7'b1111001, C2=7'b0100100, C3=7'b0110000,
        C4=7'b0011001, C5=7'b0010010, C6=7'b0000010, C7=7'b1111000,
        C8=7'b0000000, C9=7'b0010000, CA=7'b0001000, CB=7'b0000011,
        CC=7'b1000110, CD=7'b0100001, CE=7'b0000110, CF=7'b0001110;

    reg [16:0] cnt;
    reg [2:0]  sel;

    always @(posedge clk) begin
        if(rst) begin cnt <= 0; sel <= 0; end
        else if(cnt == 99_999) begin cnt <= 0; sel <= sel + 1; end
        else cnt <= cnt + 1;
    end

    reg [3:0] nibble;
    always @(*) begin
        case(sel)
            3'd0: nibble = val[31:28]; 3'd1: nibble = val[27:24];
            3'd2: nibble = val[23:20]; 3'd3: nibble = val[19:16];
            3'd4: nibble = val[15:12]; 3'd5: nibble = val[11:8];
            3'd6: nibble = val[7:4];   3'd7: nibble = val[3:0];
            default: nibble = 4'h0;
        endcase
    end

    always @(*) begin
        case(nibble)
            4'h0: seg=C0; 4'h1: seg=C1; 4'h2: seg=C2; 4'h3: seg=C3;
            4'h4: seg=C4; 4'h5: seg=C5; 4'h6: seg=C6; 4'h7: seg=C7;
            4'h8: seg=C8; 4'h9: seg=C9; 4'ha: seg=CA; 4'hb: seg=CB;
            4'hc: seg=CC; 4'hd: seg=CD; 4'he: seg=CE; 4'hf: seg=CF;
            default: seg = 7'b1111111;
        endcase
    end

    // one-hot anode decode, active low -- dataflow
    assign an = ~(8'b00000001 << (7 - sel));
endmodule
