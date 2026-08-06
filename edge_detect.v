module edge_detect (
    input  clk,
    input  sig,
    output pos,
    output neg
);
    reg prev;

    always @(posedge clk) prev <= sig;

    assign pos =  sig & ~prev;
    assign neg = ~sig &  prev;
endmodule
