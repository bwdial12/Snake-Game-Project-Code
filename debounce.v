// N=20 gives ~10ms debounce at 100MHz (2^20 cycles)
module debounce #(parameter N = 20) (
    input  clk,
    input  rst,
    input  in,
    output reg out
);
    reg [N-1:0] cnt;
    reg         q0, q1;

    always @(posedge clk) begin
        q0 <= in;
        q1 <= q0;
    end

    always @(posedge clk) begin
        if(rst) begin
            cnt <= 0;
            out <= 0;
        end else if(q1 == out)
            cnt <= 0;
        else begin
            cnt <= cnt + 1;
            if(&cnt) out <= q1;
        end
    end
endmodule
