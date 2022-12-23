module pe (
    input clk,
    input resetn,
    input en,
    input signed [7:0] in_a, in_b,
    output reg signed [26:0] sum, 
    output reg signed [7:0] out_a
);
    always @ (posedge clk or negedge resetn) begin
        if (!resetn) begin
            sum <= 0;
            out_a <= 0;
        end
        else begin
            if (en) sum <= sum + in_a * in_b;
            else sum <= sum;

            out_a <= in_a;
        end
    end
endmodule
