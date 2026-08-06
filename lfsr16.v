
// maximal-length 16-bit LFSR
// feedback taps at bits 0, 3, 9, 14 -- gate-level XOR chain
module lfsr16 (
    input         clk,
    input         rst,
    input         en,
    output [15:0] val
);
    reg [15:0] sr;

    wire t0, t1, fb;
    xor g0(t0, sr[0],  sr[3]);
    xor g1(t1, sr[9],  sr[14]);
    xor g2(fb, t0, t1);

    always @(posedge clk) begin
        if(rst)     sr <= 16'hACE1;
        else if(en) sr <= {fb, sr[15:1]};
    end

    assign val = sr;
endmodule
