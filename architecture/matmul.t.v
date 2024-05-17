`ifndef __MATMUL_T_V__
`define __MATMUL_T_V__

`include "matmul.v"

`define HEIGHT 4
`define WIDTH 1
`define COMMON 2


module test_matmul();

task print_mat;
	parameter height = 1;
	parameter width = 1;
	input [height*width*32-1:0] mat;
	integer i,j;
	begin
		$display("-----------------");
		for(i=0; i<height; i=i+1) begin
			for(j=0; j<width; j=j+1) begin

				$write("%H ", mat[height*width*32-1]);
			end
			$write("");
		end
	end

endtask

reg rst_n = 1'b0;
reg clk = 1'b0;
reg start = 1'b0;

reg [`HEIGHT*`COMMON*32-1:0] a; // A = H x C
reg [`COMMON*`WIDTH*32-1:0] b; // B = C x W

reg [31:0] data [0:7]; //dummy

wire [`HEIGHT*`WIDTH*32-1:0] o;

wire done;

matmul #(.S(32), .W(`WIDTH), .H(`HEIGHT), .C(`COMMON)) m(rst_n, clk, start, a, b, o, done);

always begin
	#10
	clk = !clk;
end

always @(posedge done) begin
	//print_mat (a);
	//print_mat(`COMMON, `WIDTH, b);
	//print_mat(`HEIGHT, `WIDTH, o);
	$display("a");
	$display("%H", a);
	$display("b");
	$display("%H", b);
	$display("o");
	$display("%H", o);
end

initial begin
	$dumpfile("matmul.vcd");
	$dumpvars(0, test_matmul);

	rst_n = 1'b0;
	@(negedge clk);

	$readmemh("data/w1.txt", data);
	assign a = {data[0],data[1],data[2],data[3],data[4],data[5],data[6],data[7]};
	b = {32'h3f800000, 32'h3f800000};

	
	start = 1'b1;
	@(negedge clk);
	start = 1'b0;
	rst_n = 1'b1;
	#500;

	$finish;
end

endmodule

`endif
