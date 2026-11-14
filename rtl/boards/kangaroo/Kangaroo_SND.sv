// Based on MAME kangaroo.cpp (Ville Laitinen, Aaron Giles, BSD-3-Clause)

module Kangaroo_SND
(
    input         reset,
    input         clk_10m,

    input   [7:0] sound_latch,
    input         sound_latch_wr,

    input         vblank,

    output signed [15:0] sound_out,

    input         pause,

    output chip_pool_pkg::z80r_i_t z80_1_i,
    input  chip_pool_pkg::z80r_o_t z80_1_o,
    output chip_pool_pkg::ayr_i_t  ay_0_i,
    input  chip_pool_pkg::ay_o_t   ay_0_o,
    output [11:0] snd_rom_a,
    input   [7:0] snd_rom_d,
    output ram_pool_pkg::pram_i_t sp_i,
    input  ram_pool_pkg::pram_o_t sp_o
);

reg [2:0] div = 3'd0;
always_ff @(posedge clk_10m) begin
    div <= div + 3'd1;
end
wire cen_2m5 = (div[1:0] == 2'd0);
wire cen_1m25 = (div == 3'd0);

wire [15:0] snd_A;
wire  [7:0] snd_Dout;
wire n_m1, n_mreq, n_iorq, n_rd, n_wr, n_rfsh;

assign n_m1 = z80_1_o.m1_n; assign n_mreq = z80_1_o.mreq_n; assign n_iorq = z80_1_o.iorq_n;
assign n_rd = z80_1_o.rd_n; assign n_wr = z80_1_o.wr_n; assign n_rfsh = z80_1_o.rfsh_n;
assign snd_A = z80_1_o.a; assign snd_Dout = z80_1_o.dout;

wire mem_access = ~n_mreq & n_rfsh;
wire io_access  = ~n_iorq;
wire any_access = mem_access | io_access;

wire cs_sndrom  = mem_access & (snd_A[15:12] == 4'h0);
wire cs_sndram  = mem_access & (snd_A[15:12] == 4'h4);
wire cs_slatch  = any_access & (snd_A[15:12] == 4'h6) & ~n_rd;
wire cs_ay_data = any_access & (snd_A[15:12] == 4'h7) & ~n_wr;
wire cs_ay_addr = any_access & (snd_A[15:12] == 4'h8) & ~n_wr;

wire [7:0] sndrom_D;
wire [7:0] sndram_D;
wire [7:0] ay_Dout;

wire [7:0] snd_Din =
    cs_sndrom                  ? sndrom_D :
    (cs_sndram & ~n_rd)       ? sndram_D :
    cs_slatch                  ? sound_latch :
    8'hFF;

assign snd_rom_a = snd_A[11:0];
assign sndrom_D = snd_rom_d;

assign sp_i.a_addr = {6'd0, snd_A[9:0]}; assign sp_i.a_d = snd_Dout; assign sp_i.a_we = cs_sndram & ~n_wr;
assign sp_i.b_addr = 16'd0; assign sp_i.b_d = 8'd0; assign sp_i.b_we = 1'b0;
assign sndram_D = sp_o.a_q;

wire ay_bdir = cs_ay_data | cs_ay_addr;
wire ay_bc1  = cs_ay_addr;

wire [7:0] ayA_raw, ayB_raw, ayC_raw;

assign ay_0_i.rst_n = reset; assign ay_0_i.ce = cen_1m25; assign ay_0_i.bdir = ay_bdir; assign ay_0_i.bc1 = ay_bc1;
assign ay_0_i.din = snd_Dout; assign ay_0_i.ioa_in = 8'h00; assign ay_0_i.iob_in = 8'h00;
assign ay_Dout = ay_0_o.dout; assign ayA_raw = ay_0_o.a; assign ayB_raw = ay_0_o.b; assign ayC_raw = ay_0_o.c;

reg n_irq = 1'b1;
reg vblank_last = 0;
always_ff @(posedge clk_10m) begin
    if(!reset) begin
        n_irq <= 1'b1;
        vblank_last <= 0;
    end
    else begin
        vblank_last <= vblank;
        if(vblank & ~vblank_last)
            n_irq <= 1'b0;
        if(~n_m1 & ~n_iorq)
            n_irq <= 1'b1;
    end
end

wire [9:0] ay_sum = {2'b00, ayA_raw} + {2'b00, ayB_raw} + {2'b00, ayC_raw};

wire signed [15:0] ay_signed = {1'b0, ay_sum, 5'd0} - 16'sd12288;

assign sound_out = ay_signed;

assign z80_1_i.reset_n = reset; assign z80_1_i.ce = cen_2m5 & ~pause; assign z80_1_i.int_n = n_irq; assign z80_1_i.nmi_n = 1'b1;
assign z80_1_i.di = snd_Din;

endmodule
