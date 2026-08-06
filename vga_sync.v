
// 640x480 @60Hz VGA sync generator
// pixel clock: 25MHz derived from 100MHz /4
// H: 96 sync | 48 bp | 640 active | 16 fp = 800 total
// V:  2 sync | 33 bp | 480 active | 10 fp = 525 total
module vga_sync (
    input        clk,
    input        rst,
    output       hsync,
    output       vsync,
    output       active,
    output [9:0] px,
    output [9:0] py
);
    reg [1:0] div;
    always @(posedge clk) div <= div + 1;
    wire pclk_en = (div == 2'b00);

    reg [9:0] hcnt, vcnt;

    always @(posedge clk) begin
        if(rst) begin hcnt <= 0; vcnt <= 0; end
        else if(pclk_en) begin
            if(hcnt == 799) begin
                hcnt <= 0;
                vcnt <= (vcnt == 524) ? 10'd0 : vcnt + 1;
            end else
                hcnt <= hcnt + 1;
        end
    end

    // sync pulses active low -- dataflow assignments
    assign hsync  = (hcnt >= 96);
    assign vsync  = (vcnt >= 2);
    assign active = (hcnt >= 144 && hcnt < 784) && (vcnt >= 35 && vcnt < 515);
    assign px     = (hcnt >= 144) ? hcnt - 10'd144 : 10'd0;
    assign py     = (vcnt >= 35)  ? vcnt - 10'd35  : 10'd0;
endmodule
